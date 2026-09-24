import Foundation

// 原生版账本：格式 2 是 1.0 起的数据基线（`Ledger.currentFormat`），与旧 Web 版分开存储。
// 计算口径：移动平均成本、已实现/浮动收益、现金期初边界与买卖联动。

enum TradeSide: String, Codable, CaseIterable, Identifiable {
    case buy, sell
    var id: String { rawValue }
    var label: String { L10n.tr(self == .buy ? "买入" : "卖出") }
}

struct Trade: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var sequence: Int
    var symbol: String
    var side: TradeSide
    var date: String          // 美东成交日，YYYY-MM-DD
    var quantity: Decimal
    var price: Decimal
    var fee: Decimal
    var note: String = ""
    var source: String?       // manual / import
    var externalId: String?   // 券商成交编号
    var settlementAmount: Decimal? = nil // 银行给出的整笔交收额，避免半美分舍入差异
    var settlementDate: String? = nil

    var gross: Decimal {
        if let settlementAmount { return side == .buy ? settlementAmount - fee : settlementAmount + fee }
        return quantity * price
    }
    var netCash: Decimal { side == .buy ? gross + fee : gross - fee }
}

struct Quote: Identifiable, Codable, Hashable {
    var symbol: String
    var price: Decimal
    var date: String
    var source: String?      // manual / manual-close / yahoo-close / tiingo-live / finnhub-live / custom-live
    var fetchedAt: Date?
    var previousClose: Decimal? = nil
    var previousCloseDate: String? = nil
    var id: String { symbol }

    /// 报价来源的中文说明；手动录入没有来源标记。
    var sourceLabel: String {
        switch source {
        case "yahoo-close": return L10n.tr("美股收盘")
        case "manual-close": return L10n.tr("手动收盘价")
        case "tiingo-live": return L10n.tr("Tiingo 报价")
        case "finnhub-live": return L10n.tr("Finnhub 报价")
        case "custom-live": return L10n.tr("接口报价")
        default: return L10n.tr("手动报价")
        }
    }

    var isLive: Bool { source == "tiingo-live" || source == "finnhub-live" || source == "custom-live" }
    var isStale: Bool { source == "tiingo-live" && (fetchedAt.map { Date().timeIntervalSince($0) >= 60 } ?? true) }
}

enum CashKind: String, Codable, CaseIterable, Identifiable {
    case deposit, withdraw, dividend, fee
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deposit: return L10n.tr("入金")
        case .withdraw: return L10n.tr("出金")
        case .dividend: return L10n.tr("分红")
        case .fee: return L10n.tr("账户费用")
        }
    }
}

struct CashRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var sequence: Int
    var date: String
    var kind: CashKind
    var amount: Decimal        // 正数
    var tax: Decimal?          // 仅分红：预扣税费
    var symbol: String?
    var note: String = ""
    var source: String?
    var externalId: String?

    /// 单笔记录对余额的净影响。
    var net: Decimal {
        switch kind {
        case .deposit: return amount
        case .withdraw: return -amount
        case .dividend: return amount - (tax ?? 0)
        case .fee: return -amount
        }
    }
}

struct CashOpening: Codable, Hashable {
    var amount: Decimal        // 允许为零，不支持负数
    var date: String           // 期初日当天开始前的余额
    var note: String = ""
}

/// 历史收盘价与交易日历：只为收益日历与月度统计服务，不参与持仓成本计算。
struct PricePoint: Codable, Hashable {
    var symbol: String
    var date: String
    var price: Decimal
    var source: String? = nil // yahoo / tiingo / nasdaq / manual；旧账本缺失时保持兼容
}

struct SplitEvent: Codable, Hashable {
    var symbol: String
    var date: String
}

struct LedgerHistory: Codable {
    var sessions: [String] = []
    var closes: [PricePoint] = []
    var splits: [SplitEvent] = []
    var checkedAt: Date?
}

struct Ledger: Codable {
    /// 持久化格式代际。**结构没变就不要动这个数字**——抬高它等于声明与旧文件不兼容。
    /// 载入时会拒绝「比本版本更新」的文件（`LedgerStore.decode`），所以它同时是
    /// 「本版本能理解的上限」。见 DATA-COMPATIBILITY.md。
    static let currentFormat = 2
    var format: Int = Ledger.currentFormat
    var trades: [Trade] = []
    var quotes: [Quote] = []
    var cash: [CashRecord] = []
    var opening: CashOpening?
    var history: LedgerHistory = LedgerHistory()

    func quote(for symbol: String) -> Quote? { quotes.first { $0.symbol == symbol } }

    /// 排序规则只在这里定义一次：(美东日期, sequence) 升序。
    /// Swift 的 `sort` 不保证稳定，所以显式用数组下标做最终判据——这样即使备份里同日 sequence
    /// 重复（可解码但顺序有歧义），Buy/Sell 的相对顺序也是数据的纯函数，可复现，不随排序实现变化。
    static func sortedTrades(_ trades: [Trade]) -> [Trade] {
        trades.enumerated()
            .sorted { ($0.element.date, $0.element.sequence, $0.offset) < ($1.element.date, $1.element.sequence, $1.offset) }
            .map(\.element)
    }

    static func sortedCash(_ records: [CashRecord]) -> [CashRecord] {
        records.enumerated()
            .sorted { ($0.element.date, $0.element.sequence, $0.offset) < ($1.element.date, $1.element.sequence, $1.offset) }
            .map(\.element)
    }

    /// 交易 / 现金按日期与录入顺序排列。
    var orderedTrades: [Trade] { Ledger.sortedTrades(trades) }
    var orderedCash: [CashRecord] { Ledger.sortedCash(cash) }
    var nextTradeSequence: Int { (trades.map(\.sequence).max() ?? -1) + 1 }
    var nextCashSequence: Int { (cash.map(\.sequence).max() ?? -1) + 1 }
}

// MARK: - 校验

enum LedgerValidation {
    static func symbol(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespaces).uppercased()
        let pattern = "^[A-Z][A-Z0-9.\\-]{0,14}$"
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            throw LedgerError.message("股票代码须为 1–15 位大写字母、数字、点或连字符。")
        }
        return text
    }

    static func date(_ value: String) throws -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: value), formatter.string(from: parsed) == value else {
            throw LedgerError.message("日期必须是真实日期（YYYY-MM-DD）。")
        }
        let today = formatter.string(from: Date())
        guard value <= today else { throw LedgerError.message("日期不能晚于今天。") }
        return value
    }

    static func positive(_ value: Decimal, _ label: String, allowZero: Bool = false) throws -> Decimal {
        if value < 0 || (!allowZero && value == 0) {
            throw LedgerError.message(L10n.tr("{}必须{}。", label, allowZero ? L10n.tr("不小于 0") : L10n.tr("大于 0")))
        }
        return value
    }

    /// 默认的 `label` 也必须过词典：它会被当成**值**填进 `"{}最多 500 字。"`，
    /// 写死中文时英文界面会弹出「备注 is at most 500 characters.」。
    static func note(_ value: String, _ label: String = L10n.tr("备注")) throws -> String {
        guard value.count <= 500 else { throw LedgerError.message(L10n.tr("{}最多 500 字。", label)) }
        return value
    }
}

enum LedgerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return L10n.tr(text) }; return nil }
}

// MARK: - 格式化

enum Fmt {
    private static let money: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func money(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return money.string(from: value as NSDecimalNumber) ?? "—"
    }

    static func signedMoney(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        if value > 0 { return "+" + money(value) }
        if value < 0 { return "−" + money(-value) }
        return money(value)
    }

    static func quantity(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        f.locale = Locale(identifier: "en_US")
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    /// 不带货币符号，用于表单回填。
    static func moneyPlain(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        f.locale = Locale(identifier: "en_US")
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    static func percent(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US")
        let text = f.string(from: (value * 100) as NSDecimalNumber) ?? "0.00"
        return (value > 0 ? "+" : value < 0 ? "−" : "") + (value < 0 ? text.replacingOccurrences(of: "-", with: "") : text) + "%"
    }

    static var today: String { MarketClock.date() }

    /// 归属规则：`note` 只装**用户或银行/券商给的原文**，系统说明一律不写进去。
    /// 系统说明由结构化字段在展示时生成，因此天然跟随语言，也不会把值拼进查表键。
    /// 两种情况：
    /// - 导入的行 note 为空 → 用 `settlementDate` 重建；
    /// - 用户写过东西 → 原样返回，绝不覆盖。
    /// 1.0 之前把同一句系统说明写进了 `note`：那不再是兼容目标，原样显示即可。
    /// 底线不变——系统文案永远不会盖掉已经持久化的值。
    static func tradeNote(_ trade: Trade) -> String {
        guard trade.source == "hsbc-statement", let settlement = trade.settlementDate else { return trade.note }
        guard trade.note.isEmpty else { return trade.note }
        return L10n.tr("汇丰月结单；交收日 {}", settlement)
    }

    /// 同上：汇丰净额分红由 `source` + `tax` 表达，说明在展示时生成。
    static func cashNote(_ record: CashRecord) -> String {
        guard record.source == "hsbc-statement-net", record.tax == nil else { return record.note }
        guard record.note.isEmpty else { return record.note }
        return L10n.tr("汇丰 PAID BENEFITS 净额；税前金额与预扣税未披露")
    }

    /// 用于「上次同步」等时间点的简短展示。
    static func clock(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: time)
    }

    /// 日历格子里的紧凑金额：小数额保留两位小数，大数额用 k 表示。
    static func compactSigned(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let sign = number > 0 ? "+" : number < 0 ? "−" : ""
        let magnitude = abs(number)
        let text: String
        if magnitude >= 100_000 { text = String(format: "%.0fk", magnitude / 1000) }
        else if magnitude >= 10_000 { text = String(format: "%.1fk", magnitude / 1000) }
        else if magnitude >= 1_000 { text = String(format: "%.2fk", magnitude / 1000) }
        else if magnitude >= 100 { text = String(format: "%.0f", magnitude) }
        else { text = String(format: "%.2f", magnitude) }
        return sign + text
    }

    /// 同上，但带货币符号。符号排在正负号**之后**（`+$120`），与 `signedMoney` 同一种排法——
    /// 直接写 `"$" + compactSigned(...)` 会得到 `$+120`，英文里是错的。
    static func compactMoney(_ value: Decimal) -> String {
        let text = compactSigned(value)
        guard let sign = text.first, sign == "+" || sign == "−" else { return "$" + text }
        return String(sign) + "$" + String(text.dropFirst())
    }
}
