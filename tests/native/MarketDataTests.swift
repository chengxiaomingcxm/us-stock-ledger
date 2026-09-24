import Foundation

private final class MarketDataRequestCapture {
    private let lock = NSLock()
    private var stored: URLRequest?
    func set(_ request: URLRequest) { lock.lock(); stored = request; lock.unlock() }
    var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return stored }
}

@MainActor
enum MarketDataTests {
    static func run() async throws {
        let success = try fixture("tiingo_quote_success.json")
        let capture = MarketDataRequestCapture()
        let provider = TiingoMarketDataProvider { request in
            capture.set(request)
            return (success, response(request, status: 200))
        }
        let quote = try await provider.quotes(for: ["AAPL", "AAPL", "MSFT"], key: "EXAMPLE_CREDENTIAL")["AAPL"]
        NativeTests.check(quote?.price == Decimal(string: "233.12"), "Tiingo reference price decoded")
        NativeTests.check(quote?.previousClose == Decimal(string: "232.5"), "Tiingo previous close decoded")
        NativeTests.check(quote?.date == "2020-09-24", "Tiingo timestamp normalized to market date")
        NativeTests.check(quote?.volume == 1_234_567 && quote?.open == Decimal(string: "232.7"), "Tiingo OHLCV fields decoded")
        NativeTests.check(capture.request?.value(forHTTPHeaderField: "Authorization") == "Token EXAMPLE_CREDENTIAL", "Tiingo key sent in auth header")
        NativeTests.check(capture.request?.url?.path == "/iex/AAPL,MSFT", "unique symbols use the documented batch endpoint")

        let dailyCapture = MarketDataRequestCapture()
        let daily = TiingoMarketDataProvider { request in
            dailyCapture.set(request)
            return (try fixture("tiingo_daily_success.json"), response(request, status: 200))
        }
        let start = MarketClock.day("2020-09-22")!
        let end = MarketClock.day("2020-09-23")!
        let history = try await daily.historicalPrices(for: "AAPL", from: start, to: end, key: "EXAMPLE_CREDENTIAL")
        NativeTests.check(history.count == 2 && history.last?.price == Decimal(string: "233.12"), "Tiingo EOD history maps to ledger-domain prices")
        NativeTests.check(dailyCapture.request?.url?.path == "/tiingo/daily/AAPL/prices", "history uses the documented Tiingo EOD endpoint")
        NativeTests.check(dailyCapture.request?.value(forHTTPHeaderField: "Authorization") == "Token EXAMPLE_CREDENTIAL", "history key stays in the authorization header")

        for (status, expected) in [(401, MarketDataError.Kind.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .server(500)), (503, .server(503))] {
            let failing = TiingoMarketDataProvider { request in (Data(), response(request, status: status)) }
            do {
                _ = try await failing.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL")
                fatalError("FAIL: expected Tiingo HTTP error \(status)")
            } catch let error as MarketDataError {
                NativeTests.check(error.kind == expected, "Tiingo HTTP \(status) classified")
            }
        }

        let empty = TiingoMarketDataProvider { request in (try fixture("tiingo_quote_empty.json"), response(request, status: 200)) }
        await rejectsAsync("Tiingo empty result") { _ = try await empty.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL") }
        let invalid = TiingoMarketDataProvider { request in (try fixture("tiingo_quote_invalid.json"), response(request, status: 200)) }
        await rejectsAsync("Tiingo invalid JSON shape") { _ = try await invalid.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL") }
        let offline = TiingoMarketDataProvider { _ in throw URLError(.notConnectedToInternet) }
        await rejectsAsync("Tiingo offline") { _ = try await offline.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL") }
        let timeout = TiingoMarketDataProvider { _ in throw URLError(.timedOut) }
        await rejectsAsync("Tiingo timeout") { _ = try await timeout.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL") }
        await rejectsAsync("Tiingo missing key") { _ = try await provider.quotes(for: ["AAPL"], key: "") }

        let initialTime = Date(timeIntervalSince1970: 1_800_000_000)
        let mock = MockMarketDataProvider(result: ["AAPL": LiveQuote(price: 100, date: "2027-01-15", previousClose: nil, previousCloseDate: nil, source: "tiingo-live")], delayNanoseconds: 20_000_000)
        let service = MarketDataService(provider: mock, ttl: 60)
        async let first = service.quotes(for: ["AAPL", "AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime)
        async let second = service.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime)
        let (firstBatch, secondBatch) = await (first, second)
        NativeTests.check(firstBatch.quotes["AAPL"]?.price == 100 && secondBatch.quotes["AAPL"]?.price == 100, "concurrent quote requests share a result")
        let requestCountAfterConcurrent = await mock.requestCount
        NativeTests.check(requestCountAfterConcurrent == 1, "duplicate and concurrent symbols make one provider request")
        _ = await service.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime.addingTimeInterval(30))
        let requestCountAfterFreshHit = await mock.requestCount
        NativeTests.check(requestCountAfterFreshHit == 1, "fresh quote cache prevents another request")
        await mock.setFailure(MarketDataError(kind: .rateLimited))
        let stale = await service.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime.addingTimeInterval(61))
        NativeTests.check(stale.quotes["AAPL"]?.price == 100 && stale.quotes["AAPL"]?.isStale == true, "failed refresh returns marked stale cache")
        let requestCountAfterFailure = await mock.requestCount
        NativeTests.check(stale.errors["AAPL"] != nil && requestCountAfterFailure == 2, "stale fallback reports failure and retries only once")
        _ = await service.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime.addingTimeInterval(62))
        let requestCountDuringCooldown = await mock.requestCount
        NativeTests.check(requestCountDuringCooldown == 2, "429 cooldown prevents repeated requests")

        let refreshMock = MockMarketDataProvider(result: ["AAPL": LiveQuote(price: 101, date: "2027-01-15", previousClose: nil, previousCloseDate: nil, source: "tiingo-live")])
        let refreshService = MarketDataService(provider: refreshMock, ttl: 60)
        _ = await refreshService.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime)
        let refreshed = await refreshService.quotes(for: ["AAPL"], key: "EXAMPLE_CREDENTIAL", now: initialTime.addingTimeInterval(61))
        let refreshCount = await refreshMock.requestCount
        NativeTests.check(refreshed.quotes["AAPL"]?.price == 101 && refreshCount == 2, "expired quote cache refreshes from provider")

        var persistCalls = 0
        let trade = Trade(sequence: 1, symbol: "AAPL", side: .buy, date: "2026-09-24", quantity: 2, price: 50, fee: 0)
        let ledger = Ledger(trades: [trade], quotes: [Quote(symbol: "AAPL", price: 51, date: "2026-09-24")])
        let offlineProvider = MockMarketDataProvider(failure: MarketDataError(kind: .network))
        let offlineService = MarketDataService(provider: offlineProvider)
        let state = AppState(ledger: ledger,
                             settings: QuoteSettings(provider: .tiingo, tiingoKey: "EXAMPLE_CREDENTIAL", priceMode: "live"),
                             persist: { _ in persistCalls += 1 }, marketDataService: offlineService)
        await state.refreshQuotes()
        NativeTests.check(state.ledger.trades == ledger.trades && state.ledger.quote(for: "AAPL")?.price == 51,
                          "quote failure leaves transactions and saved price unchanged")
        NativeTests.check(persistCalls == 0, "quote failure does not persist a ledger change")

        let today = MarketClock.date(Date())
        var cursor = MarketClock.utcDay(today)!
        while Engine.knownClosed(MarketClock.utcDate(cursor)) { cursor = cursor.addingTimeInterval(-86_400) }
        let session = MarketClock.utcDate(cursor)
        cursor = cursor.addingTimeInterval(-86_400)
        while Engine.knownClosed(MarketClock.utcDate(cursor)) { cursor = cursor.addingTimeInterval(-86_400) }
        let previousSession = MarketClock.utcDate(cursor)
        var marked = Ledger()
        marked.trades = [Trade(sequence: 0, symbol: "AAPL", side: .buy, date: previousSession, quantity: 2, price: 50, fee: 0)]
        marked.history.sessions = [previousSession, session]
        marked.history.closes = [PricePoint(symbol: "AAPL", date: previousSession, price: 50),
                                 PricePoint(symbol: "AAPL", date: session, price: 55)]
        let updatedProvider = MockMarketDataProvider(result: ["AAPL": LiveQuote(price: 60, date: session,
            previousClose: 50, previousCloseDate: previousSession, source: "tiingo-live")])
        let updatedState = AppState(ledger: marked,
            settings: QuoteSettings(provider: .tiingo, tiingoKey: "EXAMPLE_CREDENTIAL", priceMode: "live"),
            persist: { _ in }, marketDataService: MarketDataService(provider: updatedProvider))
        while updatedState.rebuilding { try await Task.sleep(nanoseconds: 1_000_000) }
        let oldCalendarRevision = updatedState.insights.revision
        await updatedState.refreshQuotes()
        while updatedState.rebuilding { try await Task.sleep(nanoseconds: 1_000_000) }
        let sessionRow = updatedState.dayReturns.first { $0.date == session }
        let month = String(session.prefix(7))
        NativeTests.check(updatedState.summary.unrealized == 20, "API quote updates homepage unrealized profit")
        NativeTests.check(sessionRow?.profit == 20 && updatedState.insights.calendar[month]?.stats.profit == 20,
                          "API quote updates the matching calendar day and month total")
        NativeTests.check(updatedState.insights.revision != oldCalendarRevision,
                          "changed live profit publishes a new calendar presentation")
    }

    private static func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("tests/fixtures/\(name)"))
    }

    private static func response(_ request: URLRequest, status: Int) -> URLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private static func rejectsAsync(_ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); fatalError("FAIL: expected rejection: " + label) }
        catch { NativeTests.assertions += 1 }
    }
}
