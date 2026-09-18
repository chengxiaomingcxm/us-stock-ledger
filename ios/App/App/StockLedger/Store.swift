import Foundation
import Combine

// 原生版 1.0 沿用原生 2.0 测试版的 Documents/ledger-v2.json。
// 不读取旧 Web 版的 Capacitor Preferences；产品重新编号不更改存储位置。

enum LedgerStore {
    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ledger-v2.json")
    }

    static func load() -> Ledger {
        guard let data = try? Data(contentsOf: fileURL) else { return Ledger() }
        let decoder = JSONDecoder()
        return (try? decoder.decode(Ledger.self, from: data)) ?? Ledger()
    }

    static func save(_ ledger: Ledger) throws {
        try write(encoded(ledger))
    }

    static func encoded(_ ledger: Ledger) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ledger)
    }

    static func write(_ data: Data) throws {
        try data.write(to: fileURL, options: .atomic)
    }

    static func exportText(_ ledger: Ledger) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(ledger), as: UTF8.self)
    }

    /// 示例账本：仅用于体验界面与计算，不包含任何真实数据。
    static func demo() -> Ledger {
        func amount(_ text: String) -> Decimal {
            Decimal(string: text, locale: Locale(identifier: "en_US")) ?? 0
        }
        var ledger = Ledger()
        var sequence = 0
        func trade(_ symbol: String, _ side: TradeSide, _ date: String,
                   _ quantity: String, _ price: String, _ fee: String, _ note: String = "") -> Trade {
            let record = Trade(id: UUID(), sequence: sequence, symbol: symbol, side: side,
                               date: date, quantity: amount(quantity), price: amount(price),
                               fee: amount(fee), note: note, source: "manual", externalId: nil)
            sequence += 1
            return record
        }
        ledger.trades = [
            trade("VOO", .buy, "2026-04-02", "15", "512.30", "1", "示例：买入 ETF"),
            trade("AAPL", .buy, "2026-06-15", "20", "198.40", "1"),
            trade("AAPL", .buy, "2026-07-06", "10", "212.75", "1"),
            trade("AAPL", .sell, "2026-08-12", "12", "231.20", "1.05", "示例：部分止盈"),
            trade("MSFT", .buy, "2026-05-20", "8", "428.90", "1"),
        ]
        ledger.quotes = [
            Quote(symbol: "AAPL", price: amount("229.15"), date: "2026-09-17", source: nil, fetchedAt: nil),
            Quote(symbol: "MSFT", price: amount("512.40"), date: "2026-09-17", source: nil, fetchedAt: nil),
            Quote(symbol: "VOO", price: amount("578.05"), date: "2026-09-17", source: nil, fetchedAt: nil),
        ]
        ledger.opening = CashOpening(amount: amount("5000"), date: "2026-04-01", note: "示例期初余额")
        ledger.cash = [
            CashRecord(id: UUID(), sequence: 0, date: "2026-04-01", kind: .deposit, amount: amount("20000"),
                       tax: nil, symbol: nil, note: "示例入金", source: "manual", externalId: nil),
            CashRecord(id: UUID(), sequence: 1, date: "2026-08-15", kind: .dividend, amount: amount("6.24"),
                       tax: amount("0.94"), symbol: "AAPL", note: "示例分红", source: "manual", externalId: nil),
            CashRecord(id: UUID(), sequence: 2, date: "2026-09-01", kind: .fee, amount: amount("1.25"),
                       tax: nil, symbol: nil, note: "示例账户费用", source: "manual", externalId: nil),
        ]
        return ledger
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published var undoTrade: UUID?
    @Published var errorMessage: String?
    /// 界面语言：中文 / English，跟随设置并持久化。
    @Published var language: AppLanguage {
        didSet {
            L10n.current = language
            UserDefaults.standard.set(language.rawValue, forKey: "app.language")
        }
    }
    /// 各股票上一交易日收盘价与日期，由行情同步填入；手动报价不参与今日盈亏基准。
    @Published var previousClose: [String: Decimal] = [:]
    @Published var previousCloseDates: [String: String] = [:]
    /// 行情来源设置（含 API Key），读写系统钥匙串。
    @Published private(set) var quoteSettings: QuoteSettings
    @Published private(set) var syncingQuotes = false
    @Published private(set) var quoteErrors: [String: String] = [:]
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var syncingHistory = false
    @Published private(set) var historyErrors: [String: String] = [:]
    @Published private(set) var historySyncedAt: Date?

    @Published private(set) var derived = LedgerDerived()
    @Published private(set) var rebuilding = false
    var summary: LedgerSummary { derived.summary }
    var cashTotals: CashTotals { derived.cash }
    var displayReturn: Engine.TodayResult { derived.displayReturn }
    var dayReturns: [Engine.DayReturn] { derived.days }
    var insights: InsightsPresentation { derived.insights }
    var openSymbols: [String] { derived.symbols }
    var orderedTrades: [Trade] { derived.trades }
    var orderedCash: [CashRecord] { derived.cashRecords }
    private var calculation: Task<LedgerDerived, Never>?
    private var generation = 0
    private var computedLedger: Ledger?
    private let persist: (Ledger) throws -> Void

    init(ledger: Ledger = LedgerStore.load(), settings: QuoteSettings = QuoteService.load(),
         persist: @escaping (Ledger) throws -> Void = LedgerStore.save) {
        self.ledger = ledger
        self.quoteSettings = settings
        self.persist = persist
        let saved = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app.language") ?? "") ?? .zhHans
        self.language = saved
        L10n.current = saved
        rebuild(ledger)
    }

    func setLanguage(_ value: AppLanguage) { language = value }
    private func rebuild(_ value: Ledger) {
        calculation?.cancel()
        generation += 1
        let token = generation
        rebuilding = true
        let cached = derived
        let unchanged = computedLedger.map {
            $0.trades == value.trades && $0.history.sessions == value.history.sessions
            && $0.history.closes == value.history.closes && $0.history.splits == value.history.splits
        } ?? false
        let worker = Task.detached(priority: .userInitiated) {
            LedgerDerived.compute(value, cached: cached, historyUnchanged: unchanged)
        }
        calculation = worker
        Task { [weak self] in
            let result = await worker.value
            guard let self, self.generation == token, !worker.isCancelled else { return }
            self.derived = result
            self.computedLedger = value
            self.rebuilding = false
        }
    }
    /// Save first; failed persistence leaves both the in-memory and disk ledger intact.
    @discardableResult
    func commit(_ next: Ledger) -> Bool {
        do { try persist(next) }
        catch { errorMessage = error.localizedDescription; return false }
        ledger = next
        rebuild(next)
        return true
    }

    /// Automatic refresh must not JSON-encode the entire history on the scrolling thread.
    private func commitRefresh(_ next: Ledger) async -> Bool {
        let token = generation
        do {
            let data = try await Task.detached(priority: .utility) { try LedgerStore.encoded(next) }.value
            guard !Task.isCancelled else { return false }
            guard token == generation else {
                errorMessage = "同步期间账本已修改，已保留最新账本，请重新同步行情。"
                return false
            }
            try LedgerStore.write(data)
            ledger = next
            rebuild(next)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 交易

    @discardableResult
    func saveTrade(_ trade: Trade) -> Bool {
        var next = ledger
        let isNew = !next.trades.contains { $0.id == trade.id }
        if let index = next.trades.firstIndex(where: { $0.id == trade.id }) {
            next.trades[index] = trade
        } else {
            var created = trade
            created.sequence = next.nextTradeSequence
            next.trades.append(created)
        }
        guard commit(next) else { return false }
        if isNew { undoTrade = trade.id }
        return true
    }

    func deleteTrade(_ id: UUID) {
        var next = ledger
        next.trades.removeAll { $0.id == id }
        if undoTrade == id { undoTrade = nil }
        commit(next)
    }

    func undoLastTrade() {
        guard let id = undoTrade else { return }
        deleteTrade(id)
    }

    // MARK: - 报价

    func setQuote(symbol: String, price: Decimal, date: String) {
        var next = ledger
        next.quotes.removeAll { $0.symbol == symbol }
        next.quotes.append(Quote(symbol: symbol, price: price, date: date, source: nil, fetchedAt: Date()))
        commit(next)
    }

    // MARK: - 行情

    func saveQuoteSettings(_ settings: QuoteSettings) throws {
        let clean = try QuoteService.validate(settings)
        try QuoteService.save(clean)
        quoteSettings = clean
        rebuild(ledger) // Invalidate a snapshot being prepared under the previous provider settings.
    }

    var openSymbolList: [String] { openSymbols }

    /// 同步全部持仓报价：请求失败只记录原因并保留已有价格，绝不写入零价或错误价格。
    func refreshQuotes() async {
        let recent = MarketClock.date(Date().addingTimeInterval(-10 * 86400))
        // Recently closed positions still contribute to the displayed session's return.
        let symbols = Set(Engine.summary(ledger).open.map(\.symbol))
            .union(ledger.trades.filter { $0.date >= recent }.map(\.symbol)).sorted()
        guard !symbols.isEmpty, !syncingQuotes else { return }
        let settings = quoteSettings
        syncingQuotes = true
        defer { syncingQuotes = false }

        let result = await QuoteService.fetchAll(symbols: symbols, settings: settings)
        guard !Task.isCancelled, settings == quoteSettings else { return }
        quoteErrors = result.errors
        guard !result.quotes.isEmpty else { return }

        var incoming: [Quote] = []
        for (symbol, live) in result.quotes {
            incoming.append(Quote(symbol: symbol, price: live.price, date: live.date, source: live.source, fetchedAt: Date(), previousClose: live.previousClose, previousCloseDate: live.previousCloseDate))
            if let previous = live.previousClose, live.previousCloseDate != live.date {
                previousClose[symbol] = previous
                if let date = live.previousCloseDate { previousCloseDates[symbol] = date }
                else { previousCloseDates.removeValue(forKey: symbol) }
            } else {
                previousClose.removeValue(forKey: symbol)
                previousCloseDates.removeValue(forKey: symbol)
            }
        }
        if await applyQuotes(incoming) { lastSyncedAt = Date() }
        else if let errorMessage, !Task.isCancelled { quoteErrors["账本"] = errorMessage }
    }

    /// 同步历史收盘价与交易日历：收益日历、月度统计和上一收盘价都基于这些数据。
    func syncHistory() async {
        guard !syncingHistory else { return }
        let cutoff = MarketClock.date(Date().addingTimeInterval(-100 * 86_400))
        var symbols = Set(Engine.summary(ledger).open.map(\.symbol)).union(ledger.trades.filter { $0.date >= cutoff }.map(\.symbol))
        symbols.insert("SPY") // 交易日历基准
        syncingHistory = true
        defer { syncingHistory = false }

        let result = await QuoteService.fetchSeriesAll(symbols: symbols.sorted())
        historyErrors = result.errors
        guard !result.series.isEmpty else { return }

        var sessions = Set(ledger.history.sessions)
        var closes: [String: PricePoint] = [:]
        for point in ledger.history.closes { closes[point.symbol + "|" + point.date] = point }
        var splits: [String: SplitEvent] = [:]
        for event in ledger.history.splits { splits[event.symbol + "|" + event.date] = event }

        var incoming: [Quote] = []
        for (symbol, series) in result.series {
            if symbol == "SPY" { sessions.formUnion(series.sessions) }
            for point in series.closes where symbol != "SPY" { closes[point.symbol + "|" + point.date] = point }
            for event in series.splits { splits[event.symbol + "|" + event.date] = event }
            guard symbol != "SPY", let latest = series.closes.last else { continue }
            let previous = series.closes.dropLast().last
            incoming.append(Quote(symbol: symbol, price: latest.price, date: latest.date, source: "yahoo-close", fetchedAt: Date(), previousClose: previous?.price, previousCloseDate: previous?.date))
            if series.closes.count > 1 {
                let previous = series.closes[series.closes.count - 2]
                if previous.date < latest.date {
                    previousClose[symbol] = previous.price
                    previousCloseDates[symbol] = previous.date
                }
            }
        }

        // 超出容量时整天淘汰，绝不按单条随意截断某个交易日。
        var all = closes.values.sorted { $0.date == $1.date ? $0.symbol < $1.symbol : $0.date < $1.date }
        while all.count > 25_000, let oldest = all.first?.date {
            all.removeAll { $0.date == oldest }
        }

        var next = ledger
        next.history = LedgerHistory(sessions: Array(sessions.sorted().suffix(4_000)),
                                     closes: all,
                                     splits: splits.values.sorted { $0.date == $1.date ? $0.symbol < $1.symbol : $0.date < $1.date },
                                     checkedAt: Date())
        let open = Set(Engine.summary(next).open.map(\.symbol))
        for quote in incoming where open.contains(quote.symbol) {
            if let existing = next.quote(for: quote.symbol),
               (existing.source == nil && existing.date >= quote.date) || (existing.date > quote.date && !(quote.source == "yahoo-close" && QuoteService.usesClosingPrices(quoteSettings))) { continue }
            next.quotes.removeAll { $0.symbol == quote.symbol }
            next.quotes.append(quote)
        }
        if await commitRefresh(next) { historySyncedAt = Date() }
        else if let errorMessage, !Task.isCancelled { historyErrors["账本"] = errorMessage }
    }

    /// 合并报价：绝不覆盖更新的报价；同日手动报价优先于自动报价。
    @discardableResult
    private func applyQuotes(_ incoming: [Quote]) async -> Bool {
        let open = Set(ledger.trades.map(\.symbol))
        var next = ledger
        var changed = false
        for quote in incoming where open.contains(quote.symbol) {
            if let existing = next.quote(for: quote.symbol),
               (existing.source == nil && existing.date >= quote.date) || (existing.date > quote.date && !(quote.source == "yahoo-close" && QuoteService.usesClosingPrices(quoteSettings))) { continue }
            next.quotes.removeAll { $0.symbol == quote.symbol }
            next.quotes.append(quote)
            changed = true
        }
        if changed { return await commitRefresh(next) }
        return true
    }

    // MARK: - 现金

    func saveCash(_ record: CashRecord) {
        var next = ledger
        if let index = next.cash.firstIndex(where: { $0.id == record.id }) {
            next.cash[index] = record
        } else {
            var created = record
            created.sequence = next.nextCashSequence
            next.cash.append(created)
        }
        commit(next)
    }

    func deleteCash(_ id: UUID) {
        var next = ledger
        next.cash.removeAll { $0.id == id }
        commit(next)
    }

    func setOpening(_ opening: CashOpening) {
        var next = ledger
        next.opening = opening
        commit(next)
    }

    /// 清除期初余额：现金余额回到“待设置期初”，已记录的入金出金与分红保留。
    func clearOpening() {
        var next = ledger
        next.opening = nil
        commit(next)
    }

    // MARK: - 备份

    func replace(with ledger: Ledger) {
        undoTrade = nil
        commit(ledger)
    }

    // MARK: - 示例与清空

    func loadDemo() {
        replace(with: LedgerStore.demo())
    }

    func clearAll() {
        replace(with: Ledger())
    }
}
