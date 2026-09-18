import Foundation
import Security

// 原生版行情：来源设置与 API Key 存入系统钥匙串，报价按来源解析后写入账本。
// 口径与 1.x 一致：Yahoo 只提供“已完成交易日”的收盘价，Finnhub / 自定义接口提供最新报价。
// 任何解析失败都抛出明确原因，绝不用 0 或旧价格替代。

enum QuoteProvider: String, Codable, CaseIterable, Identifiable {
    case yahoo, finnhub, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yahoo: return "Yahoo 收盘价"
        case .finnhub: return "Finnhub 最新报价"
        case .custom: return "自定义 HTTPS 接口"
        }
    }

    var detail: String {
        switch self {
        case .yahoo: return "免密钥，取已完成交易日的收盘价，盘中不提供当日最新价。"
        case .finnhub: return "需 API Key，提供盘中最新报价与上一交易日收盘。"
        case .custom: return "地址必须为 HTTPS 且包含 {symbol} 占位符。"
        }
    }
}

enum QuoteError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct QuoteSettings: Codable, Equatable {
    var provider: QuoteProvider = .yahoo
    var url: String = ""
    var key: String = ""
    var interval: Int = 60
    var priceMode: String? = nil // nil/auto: completed close outside regular hours; close/live: explicit choice
}

struct LiveQuote {
    var price: Decimal
    var date: String
    var previousClose: Decimal?
    var previousCloseDate: String?
    var source: String
}

// MARK: - 美东交易日

enum MarketClock {
    static let timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -4)!

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let parser: DateFormatter = dayFormatter

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(_ time: Date = Date()) -> String { dayFormatter.string(from: time) }

    static func day(_ value: String) -> Date? { parser.date(from: value) }

    /// 按 UTC 零点换算日期，用于逐日推算（避免夏令时造成 23/25 小时偏差）。
    static func utcDay(_ value: String) -> Date? { utcFormatter.date(from: value) }
    static func utcDate(_ time: Date) -> String { utcFormatter.string(from: time) }

    /// 仅按周末推算上一个工作日，节假日由行情来源的收盘价序列决定，不在此猜测。
    static func previousWeekday(_ value: String) -> String? {
        guard let date = parser.date(from: value) else { return nil }
        var candidate = date
        for _ in 0 ..< 5 {
            guard let previous = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: candidate) else { return nil }
            candidate = previous
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: previous)
            if weekday != 1, weekday != 7 { return parser.string(from: previous) }
        }
        return nil
    }
}

// MARK: - 钥匙串

enum Keychain {
    private static let service = "com.personal.stockledger.market"
    private static let account = "quote-settings-v1"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func write(_ value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            for (key, item) in attributes { create[key] = item }
            guard SecItemAdd(create as CFDictionary, nil) == errSecSuccess else {
                throw QuoteError.message("钥匙串保存失败，原设置已保留。")
            }
        } else if status != errSecSuccess {
            throw QuoteError.message("钥匙串保存失败，原设置已保留。")
        }
        guard read() == value else { throw QuoteError.message("钥匙串保存校验失败，原设置已保留。") }
    }
}

// MARK: - 行情服务

enum QuoteService {
    static func load() -> QuoteSettings {
        guard let text = Keychain.read(),
              let data = text.data(using: .utf8),
              let settings = try? JSONDecoder().decode(QuoteSettings.self, from: data),
              let clean = try? validate(settings) else { return QuoteSettings() }
        return clean
    }

    static func save(_ settings: QuoteSettings) throws {
        let clean = try validate(settings)
        let data = try JSONEncoder().encode(clean)
        try Keychain.write(String(decoding: data, as: UTF8.self))
    }

    static func validate(_ raw: QuoteSettings) throws -> QuoteSettings {
        guard [0, 60, 300].contains(raw.interval) else { throw QuoteError.message("刷新间隔无效。") }
        guard raw.priceMode == nil || ["auto", "close", "live"].contains(raw.priceMode!) else { throw QuoteError.message("报价模式无效。") }
        var clean = raw
        clean.url = raw.url.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.key = raw.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.key.count > 2048 || clean.key.contains("\n") || clean.key.contains("\r") {
            throw QuoteError.message("API Key 格式无效。")
        }
        switch clean.provider {
        case .yahoo:
            break
        case .finnhub:
            if clean.key.isEmpty { throw QuoteError.message("请输入 Finnhub API Key。") }
        case .custom:
            let probe = clean.url.replacingOccurrences(of: "{symbol}", with: "AAPL")
            guard clean.url.contains("{symbol}"),
                  let url = URL(string: probe),
                  url.scheme == "https",
                  url.host?.isEmpty == false,
                  url.user == nil,
                  url.password == nil,
                  url.fragment == nil else {
                throw QuoteError.message("接口必须为 HTTPS，包含 {symbol}，且不含账号、密码或片段。")
            }
        }
        return clean
    }

    static func usesClosingPrices(_ settings: QuoteSettings, now: Date = Date()) -> Bool {
        if settings.priceMode == "close" || settings.provider == .yahoo { return true }
        if settings.priceMode == "live" { return false }
        let day = MarketClock.date(now)
        if Engine.knownClosed(day) { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MarketClock.timeZone
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return minutes < 570 || minutes >= 975
    }

    static func fetch(symbol: String, settings: QuoteSettings, now: Date = Date()) async throws -> LiveQuote {
        let clean = try validate(settings)
        if usesClosingPrices(clean, now: now) { return try await fetchYahoo(symbol: symbol, now: now) }
        switch clean.provider {
        case .yahoo:
            return try await fetchYahoo(symbol: symbol, now: now)
        case .finnhub:
            return try await fetchFinnhub(symbol: symbol, key: clean.key, now: now)
        case .custom:
            return try await fetchCustom(symbol: symbol, template: clean.url, key: clean.key, now: now)
        }
    }

    /// 每次刷新最多同时发起 2 个请求，避免触发免费档限流。
    static func fetchAll(symbols: [String], settings: QuoteSettings) async -> (quotes: [String: LiveQuote], errors: [String: String]) {
        var quotes: [String: LiveQuote] = [:]
        var errors: [String: String] = [:]
        var index = 0
        while index < symbols.count {
            let chunk = Array(symbols[index ..< min(index + 2, symbols.count)])
            index += 2
            await withTaskGroup(of: (String, LiveQuote?, String?).self) { group in
                for symbol in chunk {
                    group.addTask {
                        do {
                            return (symbol, try await fetch(symbol: symbol, settings: settings), nil)
                        } catch {
                            return (symbol, nil, (error as? QuoteError)?.errorDescription ?? error.localizedDescription)
                        }
                    }
                }
                for await (symbol, live, failure) in group {
                    if let live { quotes[symbol] = live }
                    if let failure { errors[symbol] = failure }
                }
            }
        }
        return (quotes, errors)
    }

    // MARK: 网络

    private static func get(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await NoRedirectSession.shared.data(for: request)
        } catch {
            throw QuoteError.message("连接失败：请检查网络与接口地址。")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw QuoteError.message("请求限流，请延长刷新间隔。") }
        if status == 401 || status == 403 { throw QuoteError.message("API Key 无效或无行情权限。") }
        guard status == 200 else { throw QuoteError.message("行情请求失败（\(status)）。") }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw QuoteError.message("接口未返回有效报价。")
        }
    }

    // MARK: Yahoo

    private static func fetchYahoo(symbol: String, now: Date) async throws -> LiveQuote {
        let series = try await fetchSeries(symbol: symbol, now: now)
        guard let latest = series.closes.last else { throw QuoteError.message("暂时没有已完成交易日的收盘价。") }
        let previous = series.closes.count > 1 ? series.closes[series.closes.count - 2] : nil
        return LiveQuote(price: latest.price,
                         date: latest.date,
                         previousClose: previous?.price,
                         previousCloseDate: previous?.date,
                         source: "yahoo-close")
    }

    // MARK: 日线序列（收益日历与上一收盘价）

    struct DailySeries {
        var closes: [PricePoint] = []   // 升序
        var splits: [SplitEvent] = []
        var sessions: [String] = []
    }

    private static func seriesURL(_ symbol: String) -> URL? {
        let provider = providerSymbol(symbol)
        let escaped = provider.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? provider
        return URL(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(escaped)?interval=1d&range=3mo&includePrePost=false&events=splits")
    }

    static func fetchSeries(symbol: String, now: Date = Date()) async throws -> DailySeries {
        guard let url = seriesURL(symbol) else { throw QuoteError.message("接口地址无效。") }
        let body = try await get(url, headers: ["User-Agent": "StockLedger/1.0 (personal portfolio)"])
        return try parseSeries(body, symbol: symbol, provider: providerSymbol(symbol), now: now)
    }

    /// 逐只获取日线；SPY 用于交易日历。失败只影响该股票，其他股票照常写入。
    static func fetchSeriesAll(symbols: [String]) async -> (series: [String: DailySeries], errors: [String: String]) {
        var series: [String: DailySeries] = [:]
        var errors: [String: String] = [:]
        var index = 0
        while index < symbols.count {
            let chunk = Array(symbols[index ..< min(index + 2, symbols.count)])
            index += 2
            await withTaskGroup(of: (String, DailySeries?, String?).self) { group in
                for symbol in chunk {
                    group.addTask {
                        do { return (symbol, try await fetchSeries(symbol: symbol), nil) }
                        catch { return (symbol, nil, (error as? QuoteError)?.errorDescription ?? error.localizedDescription) }
                    }
                }
                for await (symbol, value, failure) in group {
                    if let value { series[symbol] = value }
                    if let failure { errors[symbol] = failure }
                }
            }
        }
        return (series, errors)
    }

    static func parseSeries(_ raw: Any, symbol: String, provider: String, now: Date = Date()) throws -> DailySeries {
        guard let root = raw as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              chart["error"] == nil || chart["error"] is NSNull,
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any] else {
            throw QuoteError.message("行情服务未返回有效数据。")
        }
        guard meta["symbol"] as? String == provider,
              meta["currency"] as? String == "USD",
              meta["exchangeTimezoneName"] as? String == "America/New_York",
              let instrument = meta["instrumentType"] as? String,
              ["EQUITY", "ETF"].contains(instrument) else {
            throw QuoteError.message("未找到匹配的美元美股或 ETF。")
        }
        guard let times = (result["timestamp"] as? [Any])?.map({ strictDouble($0) }),
              let indicators = result["indicators"] as? [String: Any],
              let quote = (indicators["quote"] as? [[String: Any]])?.first,
              let closes = quote["close"] as? [Any],
              times.count == closes.count else {
            throw QuoteError.message("行情数据不完整。")
        }

        let regular = (meta["currentTradingPeriod"] as? [String: Any])?["regular"] as? [String: Any]
        let start = strictDouble(regular?["start"])
        let end = strictDouble(regular?["end"])
        let today = MarketClock.date(now)
        let hint = (meta["priceHint"] as? NSNumber)?.intValue
        let precision = (hint.map { (0 ... 8).contains($0) } ?? false) ? hint! : 8

        var points: [PricePoint] = []
        for index in times.indices {
            guard let seconds = times[index], seconds.isFinite, seconds > 0 else { continue }
            let time = Date(timeIntervalSince1970: seconds)
            guard time <= now else { continue }
            guard let value = price(closes[index]) else { continue }
            let date = MarketClock.date(time)
            if date > today { continue }
            if date == today {
                // 当日 K 线只在交易时段结束 15 分钟后视为已确认收盘，不使用假设的固定收盘时间。
                guard let start, let end, end > start,
                      MarketClock.date(Date(timeIntervalSince1970: start)) == date,
                      MarketClock.date(Date(timeIntervalSince1970: end)) == date,
                      now >= Date(timeIntervalSince1970: end + 900) else { continue }
            }
            points.append(PricePoint(symbol: symbol, date: date, price: round(value, scale: precision)))
        }
        points.sort { $0.date < $1.date }
        guard let last = points.last, last.price > 0, last.price < Decimal(1_000_000_000_000) else {
            throw QuoteError.message("暂时没有已完成交易日的收盘价。")
        }

        var splits: [SplitEvent] = []
        if let events = result["events"] as? [String: Any], let raw = events["splits"] as? [String: Any] {
            for case let item as [String: Any] in raw.values {
                guard let seconds = strictDouble(item["date"]), seconds > 0, seconds <= now.timeIntervalSince1970 else { continue }
                splits.append(SplitEvent(symbol: symbol, date: MarketClock.date(Date(timeIntervalSince1970: seconds))))
            }
        }
        return DailySeries(closes: points, splits: splits, sessions: points.map(\.date))
    }

    /// 兼容旧调用：只取最新一条收盘价。
    static func parseYahoo(_ raw: Any, symbol: String, provider: String, now: Date = Date()) throws -> LiveQuote {
        let series = try parseSeries(raw, symbol: symbol, provider: provider, now: now)
        guard let latest = series.closes.last else { throw QuoteError.message("暂时没有已完成交易日的收盘价。") }
        let previous = series.closes.count > 1 ? series.closes[series.closes.count - 2] : nil
        return LiveQuote(price: latest.price,
                         date: latest.date,
                         previousClose: previous?.price,
                         previousCloseDate: previous?.date,
                         source: "yahoo-close")
    }

    // MARK: Finnhub

    private static func fetchFinnhub(symbol: String, key: String, now: Date) async throws -> LiveQuote {
        let escaped = providerSymbol(symbol).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://finnhub.io/api/v1/quote?symbol=\(escaped)") else {
            throw QuoteError.message("接口地址无效。")
        }
        let body = try await get(url, headers: ["X-Finnhub-Token": key])
        return try parseFinnhub(body, symbol: symbol, now: now)
    }

    static func parseFinnhub(_ raw: Any, symbol: String, now: Date = Date()) throws -> LiveQuote {
        guard let body = raw as? [String: Any] else { throw QuoteError.message("接口未返回有效报价。") }
        guard let current = price(body["c"]), current > 0, current < Decimal(1_000_000_000_000) else {
            throw QuoteError.message("报价价格无效。")
        }
        guard let seconds = strictDouble(body["t"]), seconds > 0, seconds <= now.timeIntervalSince1970 + 60 else {
            throw QuoteError.message("报价时间无效或来自未来。")
        }
        var previous: Decimal?
        var previousDate: String?
        if let close = price(body["pc"]), close > 0, close < Decimal(1_000_000_000_000) {
            // The API supplies pc without its session date. Never invent a weekday date.
            previous = close
            previousDate = nil
        }
        return LiveQuote(price: round(current, scale: 8),
                         date: MarketClock.date(Date(timeIntervalSince1970: seconds)),
                         previousClose: previous,
                         previousCloseDate: previousDate,
                         source: "finnhub-live")
    }

    // MARK: 自定义接口

    private static func fetchCustom(symbol: String, template: String, key: String, now: Date) async throws -> LiveQuote {
        let escaped = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: template.replacingOccurrences(of: "{symbol}", with: escaped)) else {
            throw QuoteError.message("接口地址无效。")
        }
        var headers: [String: String] = [:]
        if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let body = try await get(url, headers: headers)
        return try parseCustom(body, symbol: symbol, now: now)
    }

    static func parseCustom(_ raw: Any, symbol: String, now: Date = Date()) throws -> LiveQuote {
        guard let body = raw as? [String: Any], body["error"] == nil || body["error"] is NSNull else {
            throw QuoteError.message("接口未返回有效报价。")
        }
        guard body["symbol"] as? String == symbol else { throw QuoteError.message("报价代码不匹配。") }
        guard body["currency"] as? String == "USD" else { throw QuoteError.message("报价币种不是美元。") }
        guard let stamp = body["timestamp"] as? String,
              stamp.range(of: "(Z|[+-]\\d{2}:\\d{2})$", options: .regularExpression) != nil,
              let time = ISO8601DateFormatter().date(from: stamp) else {
            throw QuoteError.message("报价时间缺少时区信息。")
        }
        guard time.timeIntervalSince1970 <= now.timeIntervalSince1970 + 60 else {
            throw QuoteError.message("报价时间来自未来。")
        }
        guard let value = price(body["price"]), value > 0, value < Decimal(1_000_000_000_000) else {
            throw QuoteError.message("报价价格无效。")
        }
        return LiveQuote(price: round(value, scale: 8),
                         date: MarketClock.date(time),
                         previousClose: nil,
                         previousCloseDate: nil,
                         source: "custom-live")
    }

    // MARK: 解析工具

    static func providerSymbol(_ symbol: String) -> String {
        symbol.replacingOccurrences(of: ".", with: "-")
    }

    /// 只接受十进制数字字符串（可含小数），拒绝科学计数法、空值与负号。
    private static func price(_ value: Any?) -> Decimal? {
        guard let text = strictText(value),
              text.range(of: "^\\d+(\\.\\d+)?$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US"))
    }

    private static func strictText(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func strictDouble(_ value: Any?) -> Double? {
        guard let text = strictText(value), let number = Double(text), number.isFinite else { return nil }
        return number
    }

    static func round(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}

/// 行情请求不跟随跳转、不保存 Cookie，避免把密钥带到其他主机。
private final class NoRedirectSession: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirectSession()

    private lazy var session: URLSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
