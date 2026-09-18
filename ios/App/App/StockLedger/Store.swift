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

    init(ledger: Ledger = LedgerStore.load(), settings: QuoteSettings = QuoteService.load()) {
        self.ledger = ledger
        self.quoteSettings = settings
    }

    var summary: LedgerSummary { Engine.summary(ledger) }
    var cashTotals: CashTotals { Engine.cashTotals(ledger) }

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

        var next = ledger
        for (symbol, live) in result.quotes {
            if let existing = next.quote(for: symbol) {
                // 绝不覆盖更新的报价；同日手动报价优先于自动报价。
                if existing.date > live.date || (existing.date == live.date && existing.source == nil) { continue }
            }
            next.quotes.removeAll { $0.symbol == symbol }
            next.quotes.append(Quote(symbol: symbol, price: live.price, date: live.date, source: live.source, fetchedAt: Date()))
            if let previous = live.previousClose, live.previousCloseDate != live.date {
                previousClose[symbol] = previous
                if let date = live.previousCloseDate { previousCloseDates[symbol] = date }
                else { previousCloseDates.removeValue(forKey: symbol) }
            }
        }
        commit(next)
        lastSyncedAt = Date()
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
