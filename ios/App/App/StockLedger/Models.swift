import Foundation

// 2.0：原生 SwiftUI 账本。1.x 数据不要求兼容，使用全新的 JSON 存储格式。
// 计算口径与 1.x 保持一致：移动平均成本、已实现/浮动收益、现金期初边界与买卖联动。

enum TradeSide: String, Codable, CaseIterable, Identifiable {
    case buy, sell
    var id: String { rawValue }
    var label: String { self == .buy ? "买入" : "卖出" }
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

    var gross: Decimal { quantity * price }
    var netCash: Decimal { side == .buy ? gross + fee : gross - fee }
}

struct Quote: Identifiable, Codable, Hashable {
    var symbol: String
    var price: Decimal
    var date: String
    var source: String?      // manual / yahoo-close / finnhub-live / custom-live
    var fetchedAt: Date?
    var id: String { symbol }

    /// 报价来源的中文说明；手动录入没有来源标记。
    var sourceLabel: String {
        switch source {
        case "yahoo-close": return "美股收盘"
        case "finnhub-live": return "Finnhub 报价"
        case "custom-live": return "接口报价"
        default: return "手动报价"
        }
    }

    var isLive: Bool { source == "finnhub-live" || source == "custom-live" }
}

enum CashKind: String, Codable, CaseIterable, Identifiable {
    case deposit, withdraw, dividend, fee
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deposit: return "入金"
        case .withdraw: return "出金"
        case .dividend: return "分红"
        case .fee: return "账户费用"
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
    var format: Int = 2
    var trades: [Trade] = []
    var quotes: [Quote] = []
    var cash: [CashRecord] = []
    var opening: CashOpening?
    var history: LedgerHistory = LedgerHistory()

    func quote(for symbol: String) -> Quote? { quotes.first { $0.symbol == symbol } }

    /// 交易按日期与录入顺序排列。
    var orderedTrades: [Trade] {
        trades.sorted { $0.date == $1.date ? $0.sequence < $1.sequence : $0.date < $1.date }
    }
    var orderedCash: [CashRecord] {
        cash.sorted { $0.date == $1.date ? $0.sequence < $1.sequence : $0.date < $1.date }
    }
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
            throw LedgerError.message("\(label)必须\(allowZero ? "不小于 0" : "大于 0")。")
        }
        return value
    }

    static func note(_ value: String, _ label: String = "备注") throws -> String {
        guard value.count <= 500 else { throw LedgerError.message("\(label)最多 500 字。") }
        return value
    }
}

enum LedgerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
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

    /// 用于「上次同步」等时间点的简短展示。
    static func clock(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: time)
    }
}
