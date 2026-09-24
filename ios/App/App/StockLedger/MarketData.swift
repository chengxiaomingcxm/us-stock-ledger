import Foundation

struct MarketDataError: LocalizedError, Equatable {
    enum Kind: Equatable { case missingAPIKey, invalidURL, unauthorized, rateLimited, server(Int), network, decoding, noData, invalidQuote }
    let kind: Kind

    var errorDescription: String? {
        switch kind {
        case .missingAPIKey: return L10n.tr("请输入 Tiingo API Key。")
        case .invalidURL: return L10n.tr("接口地址无效。")
        case .unauthorized: return L10n.tr("API Key 无效或无行情权限。")
        case .rateLimited: return L10n.tr("请求限流，请延长刷新间隔。")
        case .server(let status): return L10n.tr("行情请求失败（{}）。", "\(status)")
        case .network: return L10n.tr("连接失败：请检查网络与接口地址。")
        case .decoding: return L10n.tr("接口未返回有效报价。")
        case .noData: return L10n.tr("行情服务未返回有效数据。")
        case .invalidQuote: return L10n.tr("报价数据无效。")
        }
    }
}

/// Provider responses are mapped here before they reach SwiftUI or the ledger.
protocol MarketDataProvider {
    func quotes(for symbols: [String], key: String) async throws -> [String: LiveQuote]
    func historicalPrices(for symbol: String, from startDate: Date, to endDate: Date, key: String) async throws -> [PricePoint]
}

private struct TiingoQuoteDTO: Decodable {
    let ticker: String
    let timestamp: String
    let tngoLast: Decimal?
    let last: Decimal?
    let prevClose: Decimal?
    let open: Decimal?
    let high: Decimal?
    let low: Decimal?
    let volume: Int64?

    enum CodingKeys: String, CodingKey { case ticker, timestamp, tngoLast, last, prevClose, open, high, low, volume }
}

struct TiingoMarketDataProvider: MarketDataProvider {
    private let load: (URLRequest) async throws -> (Data, URLResponse)

    init(load: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await NoRedirectSession.shared.data(for: $0) }) {
        self.load = load
    }

    func quotes(for symbols: [String], key: String) async throws -> [String: LiveQuote] {
        guard !key.isEmpty else { throw MarketDataError(kind: .missingAPIKey) }
        let requested = Array(Set(symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })).sorted()
        guard !requested.isEmpty else { return [:] }
        var providerToRequested: [String: [String]] = [:]
        for symbol in requested { providerToRequested[QuoteService.providerSymbol(symbol), default: []].append(symbol) }
        let tickers = providerToRequested.keys.sorted()
        let pathSymbols = tickers.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) }
        guard pathSymbols.count == tickers.count,
              let url = URL(string: "https://api.tiingo.com/iex/\(pathSymbols.joined(separator: ","))") else {
            throw MarketDataError(kind: .invalidURL)
        }

        let data = try await get(url, key: key)

        let rows: [TiingoQuoteDTO]
        do { rows = try JSONDecoder().decode([TiingoQuoteDTO].self, from: data) }
        catch { throw MarketDataError(kind: .decoding) }
        guard !rows.isEmpty else { throw MarketDataError(kind: .noData) }

        var result: [String: LiveQuote] = [:]
        let now = Date()
        for row in rows {
            let symbol = row.ticker.uppercased()
            guard let requestedSymbols = providerToRequested[symbol], let date = Self.timestamp(row.timestamp), date <= now.addingTimeInterval(60),
                  let price = row.tngoLast ?? row.last, price > 0, price < Decimal(1_000_000_000_000) else { continue }
            let previousClose = row.prevClose.flatMap { $0 > 0 ? $0 : nil }
            for requestedSymbol in requestedSymbols {
                result[requestedSymbol] = LiveQuote(price: QuoteService.round(price, scale: 8),
                                                    date: MarketClock.date(date), previousClose: previousClose,
                                                    previousCloseDate: nil, source: "tiingo-live",
                                                    open: row.open, high: row.high, low: row.low, volume: row.volume,
                                                    fetchedAt: now)
            }
        }
        guard !result.isEmpty else { throw MarketDataError(kind: .invalidQuote) }
        return result
    }

    func historicalPrices(for symbol: String, from startDate: Date, to endDate: Date, key: String) async throws -> [PricePoint] {
        try await historicalSeries(for: symbol, from: startDate, to: endDate, key: key).closes
    }

    func historicalSeries(for symbol: String, from startDate: Date, to endDate: Date, key: String, now: Date = Date()) async throws -> QuoteService.DailySeries {
        guard !key.isEmpty else { throw MarketDataError(kind: .missingAPIKey) }
        let ticker = QuoteService.providerSymbol(symbol)
        guard let escaped = ticker.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))),
              var components = URLComponents(string: "https://api.tiingo.com/tiingo/daily/\(escaped)/prices") else {
            throw MarketDataError(kind: .invalidURL)
        }
        components.queryItems = [URLQueryItem(name: "startDate", value: MarketClock.date(startDate)),
                                 URLQueryItem(name: "endDate", value: MarketClock.date(endDate))]
        guard let url = components.url else { throw MarketDataError(kind: .invalidURL) }
        let data = try await get(url, key: key)
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw MarketDataError(kind: .decoding) }
        return try QuoteService.parseTiingo(raw, symbol: symbol, now: now)
    }

    private func get(_ url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await load(request) }
        catch { throw MarketDataError(kind: .network) }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw MarketDataError(kind: .decoding) }
        if status == 401 || status == 403 { throw MarketDataError(kind: .unauthorized) }
        if status == 429 { throw MarketDataError(kind: .rateLimited) }
        guard status == 200 else { throw MarketDataError(kind: .server(status)) }
        return data
    }

    private static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }()
    }
}

struct MarketDataBatch {
    var quotes: [String: LiveQuote] = [:]
    var errors: [String: String] = [:]
}

/// Short-lived quote cache; stale values remain explicitly identifiable after a failed refresh.
actor MarketDataService {
    static let shared = MarketDataService(provider: TiingoMarketDataProvider())
    private struct Cached { var quote: LiveQuote; let fetchedAt: Date }

    private let provider: MarketDataProvider
    private let ttl: TimeInterval
    private var cache: [String: Cached] = [:]
    private var inFlight: [String: Task<[String: LiveQuote], Error>] = [:]
    private var rateLimitedUntil: Date?

    init(provider: MarketDataProvider, ttl: TimeInterval = 60) {
        self.provider = provider
        self.ttl = ttl
    }

    func clear() {
        cache.removeAll()
        rateLimitedUntil = nil
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    func quotes(for symbols: [String], key: String, now: Date = Date()) async -> MarketDataBatch {
        let unique = Array(Set(symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })).sorted()
        var result = MarketDataBatch()
        let missing = unique.filter { symbol in
            guard let entry = cache[symbol], now.timeIntervalSince(entry.fetchedAt) >= 0,
                  now.timeIntervalSince(entry.fetchedAt) < ttl else { return true }
            result.quotes[symbol] = entry.quote
            return false
        }
        guard !missing.isEmpty else { return result }
        if let rateLimitedUntil, now < rateLimitedUntil {
            addStaleOrError(for: missing, message: MarketDataError(kind: .rateLimited).localizedDescription, to: &result)
            return result
        }

        let requestKey = missing.joined(separator: ",")
        do {
            let task: Task<[String: LiveQuote], Error>
            if let existing = inFlight[requestKey] {
                task = existing
            } else {
                task = Task { try await provider.quotes(for: missing, key: key) }
                inFlight[requestKey] = task
            }
            let fetched = try await task.value
            inFlight.removeValue(forKey: requestKey)
            for symbol in missing {
                guard var quote = fetched[symbol] else {
                    result.errors[symbol] = MarketDataError(kind: .noData).localizedDescription
                    continue
                }
                quote.isStale = false
                quote.fetchedAt = quote.fetchedAt ?? now
                cache[symbol] = Cached(quote: quote, fetchedAt: now)
                result.quotes[symbol] = quote
            }
        } catch {
            inFlight.removeValue(forKey: requestKey)
            let message = error.localizedDescription
            if (error as? MarketDataError)?.kind == .rateLimited {
                rateLimitedUntil = now.addingTimeInterval(max(ttl, 60))
            }
            addStaleOrError(for: missing, message: message, to: &result)
        }
        return result
    }

    private func addStaleOrError(for symbols: [String], message: String, to result: inout MarketDataBatch) {
        for symbol in symbols {
            if var cached = cache[symbol] {
                cached.quote.isStale = true
                result.quotes[symbol] = cached.quote
            }
            result.errors[symbol] = message
        }
    }
}

actor MockMarketDataProvider: MarketDataProvider {
    private(set) var requestCount = 0
    var result: [String: LiveQuote]
    var historical: [String: [PricePoint]]
    var failure: MarketDataError?
    private let delayNanoseconds: UInt64

    init(result: [String: LiveQuote] = [:], historical: [String: [PricePoint]] = [:], failure: MarketDataError? = nil, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.historical = historical
        self.failure = failure
        self.delayNanoseconds = delayNanoseconds
    }

    func quotes(for symbols: [String], key: String) async throws -> [String: LiveQuote] {
        requestCount += 1
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if let failure { throw failure }
        return result.filter { symbols.contains($0.key) }
    }

    func historicalPrices(for symbol: String, from startDate: Date, to endDate: Date, key: String) async throws -> [PricePoint] {
        if let failure { throw failure }
        let start = MarketClock.date(startDate), end = MarketClock.date(endDate)
        return (historical[symbol] ?? []).filter { $0.date >= start && $0.date <= end }
    }

    func setFailure(_ value: MarketDataError?) { failure = value }
}
