import Foundation
import Combine

// 2.0 本地存储：全新的 JSON 账本（Documents/ledger-v2.json）。
// 不读取 1.x 的 Capacitor Preferences 数据；升级安装时 2.0 从空白账本开始。

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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ledger)
        try data.write(to: fileURL, options: .atomic)
    }

    static func exportText(_ ledger: Ledger) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(ledger), as: UTF8.self)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published var undoTrade: UUID?
    @Published var errorMessage: String?
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

    init(ledger: Ledger = LedgerStore.load(), settings: QuoteSettings = QuoteService.load()) {
        self.ledger = ledger
        self.quoteSettings = settings
    }

    var summary: LedgerSummary { Engine.summary(ledger) }
    var cashTotals: CashTotals { Engine.cashTotals(ledger) }
    var dayReturns: [Engine.DayReturn] { Engine.dailyReturns(ledger) }

    func commit(_ next: Ledger) {
        ledger = next
        do { try LedgerStore.save(next) } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - 交易

    func saveTrade(_ trade: Trade) {
        var next = ledger
        if let index = next.trades.firstIndex(where: { $0.id == trade.id }) {
            next.trades[index] = trade
        } else {
            var created = trade
            created.sequence = next.nextTradeSequence
            next.trades.append(created)
            undoTrade = created.id
        }
        commit(next)
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
    }

    var openSymbols: [String] { summary.open.map(\.symbol) }

    /// 同步全部持仓报价：请求失败只记录原因并保留已有价格，绝不写入零价或错误价格。
    func refreshQuotes() async {
        let symbols = openSymbols
        guard !symbols.isEmpty, !syncingQuotes else { return }
        let settings = quoteSettings
        syncingQuotes = true
        defer { syncingQuotes = false }

        let result = await QuoteService.fetchAll(symbols: symbols, settings: settings)
        quoteErrors = result.errors
        guard !result.quotes.isEmpty else { return }

        var incoming: [Quote] = []
        for (symbol, live) in result.quotes {
            incoming.append(Quote(symbol: symbol, price: live.price, date: live.date, source: live.source, fetchedAt: Date()))
            if let previous = live.previousClose, live.previousCloseDate != live.date {
                previousClose[symbol] = previous
                if let date = live.previousCloseDate { previousCloseDates[symbol] = date }
                else { previousCloseDates.removeValue(forKey: symbol) }
            }
        }
        applyQuotes(incoming)
        lastSyncedAt = Date()
    }

    /// 同步历史收盘价与交易日历：收益日历、月度统计和上一收盘价都基于这些数据。
    func syncHistory() async {
        guard !syncingHistory else { return }
        let cutoff = MarketClock.date(Date().addingTimeInterval(-100 * 86_400))
        var symbols = Set(openSymbols).union(ledger.trades.filter { $0.date >= cutoff }.map(\.symbol))
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
            incoming.append(Quote(symbol: symbol, price: latest.price, date: latest.date, source: "yahoo-close", fetchedAt: Date()))
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
        commit(next)
        applyQuotes(incoming)
        historySyncedAt = Date()
    }

    /// 合并报价：绝不覆盖更新的报价；同日手动报价优先于自动报价。
    @discardableResult
    private func applyQuotes(_ incoming: [Quote]) -> Bool {
        let open = Set(openSymbols)
        var next = ledger
        var changed = false
        for quote in incoming where open.contains(quote.symbol) {
            if let existing = next.quote(for: quote.symbol),
               existing.date > quote.date || (existing.date == quote.date && existing.source == nil) { continue }
            next.quotes.removeAll { $0.symbol == quote.symbol }
            next.quotes.append(quote)
            changed = true
        }
        if changed { commit(next) }
        return changed
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

    // MARK: - 备份

    func replace(with ledger: Ledger) {
        undoTrade = nil
        commit(ledger)
    }
}
