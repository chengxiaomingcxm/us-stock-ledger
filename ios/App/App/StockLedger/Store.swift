import Foundation
import Combine

// 原生版账本固定存在 Documents/ledger-v2.json（1.0 起的存储基线）。
// 不读取旧 Web 版的 Capacitor Preferences。

enum LedgerStore {
    /// 仅测试使用：把账本读写重定向到临时目录，避免测试碰到真实的 Documents。
    static var fileURLOverride: URL?

    /// 账本文件位置。
    static var fileURL: URL {
        if let fileURLOverride { return fileURLOverride }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ledger-v2.json")
    }

    /// 读取结果。「没有文件」与「文件读不出来」必须严格区分：
    /// 后者绝不能被当成空账本，否则下一次保存会用空账本覆盖仍可抢救的原文件。
    enum LoadResult {
        case missing          // 首次启动：文件不存在，是合法状态
        case loaded(Ledger)   // 正常读取
        case failed(String)   // 文件存在但无法读取/解码；原文件保持不动
    }

    static func loadResult() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            return .loaded(try decode(data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 账本读不出来时给用户看的一句话（也是暂停写入的说明）。
    static let unreadableMessage = "账本文件无法读取，已暂停写入以保护原文件；请到「设置 → 从备份恢复」。"
    /// 文件由更新版本的 App 写入：处置与「损坏」不同——不能建议「从备份恢复」，
    /// 那会用旧备份覆盖掉更完整的账本。
    static let newerFormatMessage = "账本由更新版本的 App 写入，本版本无法安全读取；请更新 App。不要用旧备份覆盖它。"

    /// 只读一眼文件里的格式代际；缺失或根本读不出来就交给完整解码去报错。
    private struct FormatProbe: Decodable { var format: Int? }

    /// 唯一解码入口：载入与「从备份恢复」共用，避免只守住一条路径。
    /// 拒绝比本版本更新的格式——否则会被「成功解码」成丢字段的账本，而下一次原子写入
    /// 就把它覆盖了，属于静默数据丢失（docs/PHASE_0_5_REVIEW.md P2-1 记的欠账）。
    static func decode(_ data: Data) throws -> Ledger {
        let decoder = JSONDecoder()
        if let found = (try? decoder.decode(FormatProbe.self, from: data))?.format,
           found > Ledger.currentFormat {
            throw LedgerError.message(newerFormatMessage)
        }
        return try decoder.decode(Ledger.self, from: data)
    }

    /// 读不出来时的横幅：格式代际问题给出它自己的处置建议，其余仍是通用那一句。
    static func bannerText(for failure: String) -> String {
        failure == L10n.tr(newerFormatMessage) ? L10n.tr(newerFormatMessage) : L10n.tr(unreadableMessage)
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

    /// 示例账本：全部为虚构数据，仅用于体验界面与计算。生成逻辑见 `DemoData`。
    static func demo(now: Date = Date()) -> Ledger { DemoData.ledger(now: now) }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published var undoTrade: UUID?
    /// 所有用户可见失败都在这里汇聚，顺便写入诊断日志（唯一汇聚点）。
    @Published var errorMessage: String? {
        didSet { if let errorMessage { Diagnostics.record("ERROR", errorMessage) } }
    }
    /// 非 nil 表示磁盘上的账本存在但读不出来：此时暂停一切写入以保护原文件。
    @Published private(set) var loadFailure: String?
    /// 示例模式：界面显示的是虚构数据，且所有写入都停在内存里，真实账本文件不受影响。
    @Published private(set) var demo = false
    /// 界面语言：中文 / English，跟随设置并持久化。
    @Published var language: AppLanguage {
        didSet {
            L10n.current = language
            UserDefaults.standard.set(language.rawValue, forKey: "app.language")
            // 派生缓存里存着「求值当时就已本地化」的标题与说明：Engine 用 L10n.tr 生成后固化成字符串
            // （Engine.displayedReturn → LedgerDerived.displayReturn），而缓存的失效键是账本与历史，不含语言。
            // 只重绘视图不足以修正它们，必须让缓存重算，否则界面会停在旧语言。
            // 见 docs/ENGLISH_UI_AUDIT.md A1。
            // 示例账本还要多一步：它的文案（note）在生成时就已本地化，只重算派生缓存
            // 不够，得按新语言重建示例数据本身；示例是只读沙盒，重建不会丢用户输入。
            if oldValue != language {
                if demo { enterDemo() } else { rebuild(ledger) }
            }
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
    /// 上一次已记录的行情失败集合，用于去重（行情失败会随每次刷新重复出现）。
    private var lastQuoteFailure = ""
    private var lastHistoryFailure = ""
    private let persist: (Ledger) throws -> Void
    private let marketDataService: MarketDataService

    /// 「磁盘读取结果 → 初始状态」只在这里定义一次：启动与退出示例模式共用。
    private static func restore(_ result: LedgerStore.LoadResult) -> (ledger: Ledger, failure: String?) {
        switch result {
        case .loaded(let value): return (value, nil)
        case .missing: return (Ledger(), nil)
        case .failed(let reason): return (Ledger(), reason)
        }
    }

    /// `ledger` 为 nil 时从磁盘读取；显式传入账本（测试 / 示例 / 截图工具）时完全不碰磁盘。
    init(ledger: Ledger? = nil, settings: QuoteSettings = QuoteService.load(),
         persist: @escaping (Ledger) throws -> Void = LedgerStore.save,
         marketDataService: MarketDataService = .shared) {
        let restored = Self.restore(ledger.map(LedgerStore.LoadResult.loaded) ?? LedgerStore.loadResult())
        self.ledger = restored.ledger
        self.loadFailure = restored.failure
        self.quoteSettings = settings
        self.persist = persist
        self.marketDataService = marketDataService
        let saved = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app.language") ?? "") ?? .zhHans
        self.language = saved
        L10n.current = saved
        // 必须在所有存储属性初始化完成之后才能读 self.loadFailure。
        if let loadFailure { Diagnostics.record("LOAD", loadFailure) }
        rebuild(self.ledger)
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
    /// 示例模式是只读沙盒：写入一律明确拒绝，既不落盘也不假装成功；
    /// 账本读取失败期间也会拒绝一切写入，避免用空账本覆盖原文件。
    @discardableResult
    func commit(_ next: Ledger) -> Bool {
        if demo {
            errorMessage = L10n.tr("示例模式是只读的，不会修改账本；请先退出示例模式。")
            return false
        }
        guard loadFailure == nil else {
            errorMessage = L10n.tr(LedgerStore.unreadableMessage)
            return false
        }
        do { try persist(next) }
        catch {
            // 系统异常的原文只进日志；界面给一句可读、可行动的话。
            Diagnostics.record("SAVE", error: error)
            errorMessage = L10n.tr("账本保存失败，磁盘上的原文件没有被改动；请重试。")
            return false
        }
        ledger = next
        rebuild(next)
        return true
    }

    /// Automatic refresh must not JSON-encode the entire history on the scrolling thread.
    private func commitRefresh(_ next: Ledger) async -> Bool {
        // 示例模式不发行情请求；即使走到了这里也绝不落盘。
        guard !demo, loadFailure == nil else { return false }
        let token = generation
        do {
            let data = try await Task.detached(priority: .utility) { try LedgerStore.encoded(next) }.value
            guard !Task.isCancelled else { return false }
            guard token == generation else {
                errorMessage = L10n.tr("同步期间账本已修改，已保留最新账本，请重新同步行情。")
                return false
            }
            try LedgerStore.write(data)
            ledger = next
            rebuild(next)
            return true
        } catch {
            Diagnostics.record("SAVE", error: error)
            errorMessage = L10n.tr("账本保存失败，磁盘上的原文件没有被改动；请重试。")
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
        guard !introducesOversell(next) else { return false }
        guard commit(next) else { return false }
        if isNew { undoTrade = trade.id }
        return true
    }

    @discardableResult
    func deleteTrade(_ id: UUID) -> Bool {
        var next = ledger
        next.trades.removeAll { $0.id == id }
        guard !introducesOversell(next) else { return false }
        guard commit(next) else { return false }
        if undoTrade == id { undoTrade = nil }
        return true
    }

    /// 手动录入路径的交易不变量：任何时点的卖出都不得超过当时持仓。
    /// 逐笔对比「违规时点」而不是只看最终持仓：只有 `next` 的每个违规时点在旧账本里都能找到
    /// （同一股票、同一日期、同一 sequence）且超额股数没有扩大，才认为这次改动是在**修复**历史脏数据。
    /// 新增另一只股票的超卖、扩大已有超卖、把违规提前到更早的时点、或删掉买入导致中间时点悬空，全部拒绝。
    private func introducesOversell(_ next: Ledger) -> Bool {
        let violations = Engine.oversells(next)
        guard !violations.isEmpty else { return false }  // 正常账本（绝大多数保存）只重放一次
        var existing: [Engine.Oversell.ID: Decimal] = [:]
        for item in Engine.oversells(ledger) { existing[item.id, default: 0] += item.quantity }
        for item in violations {
            guard let allowed = existing[item.id], item.quantity <= allowed else {
                errorMessage = L10n.tr("{} 在 {} 的卖出超过当时持仓，账本未改动。", item.symbol, item.date)
                return true
            }
        }
        return false
    }

    /// 行情失败会在每次刷新重复出现，只在「失败集合发生变化」时记一次，避免日志被刷满。
    /// 返回新的签名交给调用方保存（不用 inout，避免对 self 存储属性的重叠访问）。
    private func logFailures(_ errors: [String: String], kind: String, last: String) -> String {
        let signature = errors.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " | ")
        guard !signature.isEmpty, signature != last else { return last }
        Diagnostics.record(kind, signature)
        return signature
    }

    @discardableResult
    func undoLastTrade() -> Bool {
        guard let id = undoTrade else { return true }
        return deleteTrade(id)
    }

    // MARK: - 报价

    func setQuote(symbol: String, price: Decimal, date: String) {
        var next = ledger
        next.quotes.removeAll { $0.symbol == symbol }
        next.quotes.append(Quote(symbol: symbol, price: price, date: date, source: nil, fetchedAt: Date()))
        commit(next)
    }

    /// 最终兜底：只允许给账本已有标的、已有交易日补收盘价；手工值不会被后续接口覆盖。
    @discardableResult
    func setHistoricalClose(symbol: String, price: Decimal, date: String) -> Bool {
        errorMessage = nil
        guard price > 0, price < Decimal(1_000_000_000_000) else {
            errorMessage = L10n.tr("价格格式无效。")
            return false
        }
        guard ledger.trades.contains(where: { $0.symbol == symbol }), ledger.history.sessions.contains(date) else {
            errorMessage = L10n.tr("只能补录账本已有股票和收益日历中的交易日。")
            return false
        }
        var next = ledger
        next.history.closes.removeAll { $0.symbol == symbol && $0.date == date }
        next.history.closes.append(PricePoint(symbol: symbol, date: date, price: price, source: "manual"))
        next.history.closes.sort { $0.date == $1.date ? $0.symbol < $1.symbol : $0.date < $1.date }
        if next.quote(for: symbol).map({ $0.date <= date }) ?? true {
            let previous = next.history.closes.filter { $0.symbol == symbol && $0.date < date }.max { $0.date < $1.date }
            next.quotes.removeAll { $0.symbol == symbol }
            next.quotes.append(Quote(symbol: symbol, price: price, date: date, source: "manual-close", fetchedAt: Date(),
                                     previousClose: previous?.price, previousCloseDate: previous?.date))
        }
        guard commit(next) else { return false }
        if let quote = ledger.quote(for: symbol), quote.source == "manual-close" {
            if let previous = quote.previousClose, let previousDate = quote.previousCloseDate {
                previousClose[symbol] = previous
                previousCloseDates[symbol] = previousDate
            }
        } else if let quote = ledger.quote(for: symbol), date < quote.date,
                  ledger.history.closes.filter({ $0.symbol == symbol && $0.date < quote.date }).max(by: { $0.date < $1.date })?.date == date {
            previousClose[symbol] = price
            previousCloseDates[symbol] = date
        }
        return true
    }

    // MARK: - 行情

    func saveQuoteSettings(_ settings: QuoteSettings) throws {
        let clean = try QuoteService.validate(settings)
        try QuoteService.save(clean)
        quoteSettings = clean
        Task { await marketDataService.clear() }
        rebuild(ledger) // Invalidate a snapshot being prepared under the previous provider settings.
    }

    var openSymbolList: [String] { openSymbols }

    /// 手动刷新同时更新报价与收益日历；前台定时器仍只刷新报价。
    func refreshMarketData() async {
        await refreshQuotes()
        await syncHistory()
    }

    /// 同步全部持仓报价：请求失败只记录原因并保留已有价格，绝不写入零价或错误价格。
    func refreshQuotes() async {
        let recent = MarketClock.date(Date().addingTimeInterval(-10 * 86400))
        // Recently closed positions still contribute to the displayed session's return.
        let symbols = Set(Engine.summary(ledger).open.map(\.symbol))
            .union(ledger.trades.filter { $0.date >= recent }.map(\.symbol)).sorted()
        guard !symbols.isEmpty, !syncingQuotes, !demo else { return }
        let settings = quoteSettings
        syncingQuotes = true
        defer { syncingQuotes = false }

        let result = await QuoteService.fetchAll(symbols: symbols, settings: settings, marketDataService: marketDataService)
        guard !Task.isCancelled, settings == quoteSettings else { return }
        quoteErrors = result.errors
        lastQuoteFailure = logFailures(result.errors, kind: "QUOTE", last: lastQuoteFailure)
        guard !result.quotes.isEmpty else { return }

        var incoming: [Quote] = []
        for (symbol, live) in result.quotes {
            // 当前报价若跳过了一个日线缺口，保留历史同步已补齐的更近收盘基准。
            let history = ledger.history.closes.filter { $0.symbol == symbol && $0.date < live.date }.max { $0.date < $1.date }
            let useHistory = history.map { point in
                guard let previousDate = live.previousCloseDate else { return true }
                return point.date > previousDate
            } ?? false
            let previous = useHistory ? history?.price : live.previousClose
            let previousDate = useHistory ? history?.date : live.previousCloseDate
            incoming.append(Quote(symbol: symbol, price: live.price, date: live.date, source: live.source, fetchedAt: live.fetchedAt ?? Date(), previousClose: previous, previousCloseDate: previousDate))
            if let previous, previousDate != live.date {
                previousClose[symbol] = previous
                if let date = previousDate { previousCloseDates[symbol] = date }
                else { previousCloseDates.removeValue(forKey: symbol) }
            } else {
                previousClose.removeValue(forKey: symbol)
                previousCloseDates.removeValue(forKey: symbol)
            }
        }
        if await applyQuotes(incoming) { lastSyncedAt = Date() }
        else if let errorMessage, !Task.isCancelled { quoteErrors[L10n.tr("账本")] = errorMessage }
    }

    /// 同步历史收盘价与交易日历：收益日历、月度统计和上一收盘价都基于这些数据。
    func syncHistory() async {
        guard !syncingHistory, !demo else { return }
        let cutoff = MarketClock.date(Date().addingTimeInterval(-100 * 86_400))
        var symbols = Set(Engine.summary(ledger).open.map(\.symbol)).union(ledger.trades.filter { $0.date >= cutoff }.map(\.symbol))
        symbols.insert("SPY") // 交易日历基准
        syncingHistory = true
        defer { syncingHistory = false }

        let result = await QuoteService.fetchSeriesAll(symbols: symbols.sorted(), settings: quoteSettings)
        historyErrors = result.errors
        lastHistoryFailure = logFailures(result.errors, kind: "HISTORY", last: lastHistoryFailure)
        guard !result.series.isEmpty else { return }

        var sessions = Set(ledger.history.sessions)
        var closes: [String: PricePoint] = [:]
        for point in ledger.history.closes { closes[point.symbol + "|" + point.date] = point }
        var splits: [String: SplitEvent] = [:]
        for event in ledger.history.splits { splits[event.symbol + "|" + event.date] = event }

        var incoming: [Quote] = []
        for (symbol, series) in result.series {
            if symbol == "SPY" { sessions.formUnion(series.sessions) }
            for point in series.closes where symbol != "SPY" {
                let key = point.symbol + "|" + point.date
                if closes[key]?.source != "manual" { closes[key] = point }
            }
            for event in series.splits { splits[event.symbol + "|" + event.date] = event }
            guard symbol != "SPY" else { continue }
            let retained = closes.values.filter { $0.symbol == symbol }.sorted { $0.date < $1.date }
            guard let latest = retained.last else { continue }
            let previous = retained.dropLast().last
            let source = latest.source == "manual" ? "manual-close" : "yahoo-close"
            incoming.append(Quote(symbol: symbol, price: latest.price, date: latest.date, source: source, fetchedAt: Date(), previousClose: previous?.price, previousCloseDate: previous?.date))
            if retained.count > 1 {
                let previous = retained[retained.count - 2]
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
               (existing.source == nil && existing.date >= quote.date) || (existing.source == "manual-close" && existing.date >= quote.date)
                || (existing.date > quote.date && !(quote.source == "yahoo-close" && QuoteService.usesClosingPrices(quoteSettings))) { continue }
            next.quotes.removeAll { $0.symbol == quote.symbol }
            next.quotes.append(quote)
        }
        if await commitRefresh(next) { historySyncedAt = Date() }
        else if let errorMessage, !Task.isCancelled { historyErrors[L10n.tr("账本")] = errorMessage }
    }

    /// 合并报价：绝不覆盖更新的报价；同日手动报价优先于自动报价。
    @discardableResult
    private func applyQuotes(_ incoming: [Quote]) async -> Bool {
        let open = Set(ledger.trades.map(\.symbol))
        var next = ledger
        var changed = false
        for quote in incoming where open.contains(quote.symbol) {
            if let existing = next.quote(for: quote.symbol),
               (existing.source == nil && existing.date >= quote.date) || (existing.source == "manual-close" && existing.date >= quote.date)
                || (existing.date > quote.date && !(quote.source == "yahoo-close" && QuoteService.usesClosingPrices(quoteSettings))) { continue }
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

    @discardableResult
    func replace(with ledger: Ledger) -> Bool {
        guard commit(ledger) else { return false }
        undoTrade = nil
        return true
    }

    /// 用户明确选择用备份恢复：这是账本读取失败后唯一被放行的写入路径。
    /// 只有备份真正写盘成功才解除保护；写盘失败时保护状态、内存账本与原文件都不变。
    @discardableResult
    func replaceFromBackup(_ next: Ledger) -> Bool {
        let blocked = loadFailure
        loadFailure = nil
        guard commit(next) else {
            loadFailure = blocked
            return false
        }
        undoTrade = nil
        return true
    }

    // MARK: - 示例与清空

    /// 进入示例模式：只读沙盒，真实账本文件从头到尾不被触碰。
    /// 已知边界（`ponytail:`）：示例模式不跨启动保留——重启就回到用户自己的数据。
    /// 这是刻意选择，让示例数据永远不可能变成用户的账本。升级路径：用 `@AppStorage` 记住状态。
    func enterDemo() {
        demo = true
        undoTrade = nil
        errorMessage = nil
        let sample = LedgerStore.demo()
        ledger = sample
        rebuild(sample)
    }

    /// 退出示例模式：重新从磁盘读取，连「账本读不出来」的保护状态一起恢复。
    func exitDemo() {
        demo = false
        undoTrade = nil
        errorMessage = nil
        let restored = Self.restore(LedgerStore.loadResult())
        ledger = restored.ledger
        loadFailure = restored.failure
        rebuild(restored.ledger)
        if let failure = restored.failure { Diagnostics.record("LOAD", failure) }
    }

    func clearAll() {
        replace(with: Ledger())
    }
}
