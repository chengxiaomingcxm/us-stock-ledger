import Foundation
import AppKit
import PDFKit

@main
struct NativeTests {
    static var assertions = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !value() { fatalError("FAIL: " + message) }
    }
    static func rejects(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("FAIL: expected rejection: " + label) }
        catch { assertions += 1 }
    }
    // Invented account, identifiers, dates, amounts and securities. No user statement data.
    static let fixture = """
    HSBC Investment services - composite statement INVSTM0011
    A/C no : 000-000000-000
    Transaction summary
    Securities Securities description
    ID Transaction date Unit price Quantity Settlement amount
    /Settlement date
    FOREIGN SHARES
    TEST SAMPLE CORPORATION (SHS)
    02JAN2026 05JAN2026 USD 10.12500 1 USD 10.13
    Reference: PURTEST001 Type: PUR
    06JAN2026 07JAN2026 USD 12.34500 1- USD 12.34
    Reference: SALTEST002 Type: SAL
    UNIT TRUSTS
    UTEST SAMPLE FUND (UNT)
    02JAN2026 05JAN2026 HKD 20.00000 2 HKD 40.00
    Reference: PURTEST003 Type: PUR
    Charges and income summary
    Date Charges/income description Charges amount Income amount
    07JAN2026 SALE TEST
    SAMPLE CORPORATION (SHS)
    OUR REFERENCE:SALTEST002
    XACT CHARGE USD 0.01
    08JAN2026 CASH DIVIDEND TEST
    SAMPLE CORPORATION (SHS)
    OUR REFERENCE:CORTEST004
    PAID BENEFITS USD 0.88
    Total charges and income USD 0.01 USD 0.88
    Exchange rate against HKD : USD 7.8000000
    """

    @MainActor
    static func main() async throws {
        let empty = Ledger()
        // Draw out of content-stream order to exercise PDFKit's visual column reconstruction.
        let pdf = NSMutableData()
        let consumer = CGDataConsumer(data: pdf as CFMutableData)!
        var box = CGRect(x: 0, y: 0, width: 900, height: 1000)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (i, line) in fixture.components(separatedBy: "\n").enumerated().reversed() {
            (line as NSString).draw(at: CGPoint(x: 20, y: 970 - i * 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        let document = PDFDocument(data: pdf as Data)!
        let extracted = StatementImport.pageText(document.page(at: 0)!)
        let visualReport = try HSBCStatement.parse(pages: [extracted], ledger: empty)
        check(visualReport.rows.count == 4, "PDFKit visual order parsing")
        let report = try HSBCStatement.parse(pages: [fixture], ledger: empty)
        check(report.rows.count == 4, "all rows previewed including excluded currency")
        check(report.rows.filter(\.selected).count == 3, "HKD excluded")
        check(empty.trades.isEmpty && empty.cash.isEmpty, "preview is read only")
        let imported = try HSBCStatement.candidate(rows: report.rows, ledger: empty, insertBefore: false)
        check(imported.trades.count == 2 && imported.cash.count == 1, "batch trade and dividend import")
        check(imported.cash[0].tax == nil && imported.cash[0].amount == Decimal(string: "0.88"), "unknown tax stays unknown")
        check(imported.cash.allSatisfy { $0.kind == .dividend }, "no invented deposits or separate trade fees")
        check(imported.trades[0].price == Decimal(string: "10.125"), "original price preserved")
        check(imported.trades[0].gross == Decimal(string: "10.13"), "bank-rounded buy cost")
        check(Engine.summary(imported).realized == Decimal(string: "2.21"), "bank settlement realized profit")
        check(Engine.summary(imported).fees == Decimal(string: "0.01"), "fee exactly once")
        var funded = imported
        funded.opening = CashOpening(amount: 100, date: "2026-01-01")
        funded.cash.append(CashRecord(sequence: 1, date: "2026-01-02", kind: .deposit, amount: 200))
        funded.cash.append(CashRecord(sequence: 2, date: "2026-01-03", kind: .withdraw, amount: 50))
        check(Engine.cashTotals(funded).balance == Decimal(string: "253.09"), "cash respects settlements and external flows")
        check(Engine.cashTotals(funded).investNetAll == Decimal(string: "0.88"), "external flows excluded from profit")
        check(Engine.cashTotals(imported).balance == nil, "no inferred opening balance")
        let again = try HSBCStatement.parse(pages: [fixture], ledger: imported)
        check(again.rows.allSatisfy { !$0.selected }, "repeat import disabled")
        rejects("stale preview cannot duplicate") { _ = try HSBCStatement.candidate(rows: report.rows, ledger: imported, insertBefore: false) }
        rejects("duplicate file in one batch") { _ = try HSBCStatement.parse(pages: [fixture, fixture], ledger: empty) }
        rejects("empty file") { _ = try HSBCStatement.parse(pages: [], ledger: empty) }
        rejects("wrong bank") { _ = try HSBCStatement.parse(pages: [fixture.replacingOccurrences(of: "HSBC", with: "Other")], ledger: empty) }
        rejects("bad date") { _ = try HSBCStatement.parse(pages: [fixture.replacingOccurrences(of: "02JAN2026", with: "32JAN2026")], ledger: empty) }
        rejects("bad amount") { _ = try HSBCStatement.parse(pages: [fixture.replacingOccurrences(of: "10.12500", with: "BAD")], ledger: empty) }
        rejects("missing reference") { _ = try HSBCStatement.parse(pages: [fixture.replacingOccurrences(of: "Reference: PURTEST001 Type: PUR", with: "")], ledger: empty) }
        rejects("wrong settlement") { _ = try HSBCStatement.parse(pages: [fixture.replacingOccurrences(of: "USD 10.13", with: "USD 90.13")], ledger: empty) }
        rejects("unknown income") { _ = try HSBCStatement.parse(pages: [fixture.replacingOccurrences(of: "PAID BENEFITS", with: "OTHER INCOME")], ledger: empty) }
        rejects("unsupported tax line") { _ = try HSBCStatement.parse(pages: [fixture + "\nWITHHOLDING TAX USD 0.22"], ledger: empty) }
        rejects("missing buy") {
            _ = try HSBCStatement.candidate(rows: report.rows.filter { $0.trade?.side != .buy }, ledger: empty, insertBefore: false)
        }
        var manual = empty
        var first = imported.trades[0]; first.externalId = nil; manual.trades = [first]
        let suspicious = try HSBCStatement.parse(pages: [fixture], ledger: manual)
        check(suspicious.rows.contains { $0.duplicate && !$0.selected }, "manual trade duplicate warning")
        manual.trades[0].price = Decimal(string: "10.13")!
        let rounded = try HSBCStatement.parse(pages: [fixture], ledger: manual)
        check(rounded.rows.contains { $0.duplicate && !$0.selected }, "rounded manual price still warns about duplication")
        var historical = imported
        historical.history.sessions = ["2026-01-01", "2026-01-02", "2026-01-05", "2026-01-06", "2026-01-07"]
        historical.history.closes = [PricePoint(symbol: "TEST", date: "2026-01-01", price: 10),
                                     PricePoint(symbol: "TEST", date: "2026-01-02", price: 10),
                                     PricePoint(symbol: "TEST", date: "2026-01-05", price: 11)]
        let history = Engine.dailyReturns(historical)
        check(history.allSatisfy { $0.profit != nil }, "settled trades keep complete daily returns")
        check(history.reduce(Decimal(0)) { $0 + ($1.profit ?? 0) } == Decimal(string: "2.21"), "daily returns reconcile to realized profit after closing")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(imported))
        check(decoded.trades[0].settlementAmount == imported.trades[0].settlementAmount, "backup retains settlement")
        var oldObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(imported)) as! [String: Any]
        oldObject["trades"] = (oldObject["trades"] as! [[String: Any]]).map { row -> [String: Any] in
            var row = row; row.removeValue(forKey: "settlementAmount"); row.removeValue(forKey: "settlementDate"); return row
        }
        let old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: oldObject))
        check(old.trades[0].settlementAmount == nil && old.trades.count == 2, "old 2.0 backup compatible")

        let failing = AppState(ledger: empty, settings: QuoteSettings(), persist: { _ in throw LedgerError.message("disk full") })
        check(!failing.commit(imported) && failing.ledger.trades.isEmpty, "save failure preserves in-memory ledger")
        let editing = AppState(ledger: imported, settings: QuoteSettings(), persist: { _ in })
        var edited = imported.trades[0]; edited.note = "changed note"
        check(editing.saveTrade(edited) && editing.undoTrade == nil, "editing does not turn undo into deletion")

        var large = empty
        let start = MarketClock.utcDay("2010-01-01")!
        for i in 0..<4000 {
            let day = MarketClock.utcDate(start.addingTimeInterval(Double(i) * 86400))
            large.history.sessions.append(day)
            for j in 0..<(i < 1000 ? 7 : 6) {
                large.history.closes.append(PricePoint(symbol: "T\(j)", date: day, price: Decimal(100 + i % 30)))
            }
            if i < 1000 { large.trades.append(Trade(sequence: i, symbol: "T0", side: .buy, date: day, quantity: 1, price: 100, fee: 0)) }
        }
        check(large.history.closes.count == 25000, "25k history fixture")
        let before = Date()
        let state = AppState(ledger: large, settings: QuoteSettings(), persist: { _ in })
        var heartbeats = 0
        while state.rebuilding {
            try await Task.sleep(nanoseconds: 1_000_000)
            heartbeats += 1
            check(Date().timeIntervalSince(before) < 30, "background computation completes")
        }
        check(heartbeats > 0 && state.dayReturns.count == 4000, "main actor remains responsive during history replay")
        let historyID = state.insights.revision
        check(state.insights.ticks.count <= 6, "bounded chart labels for 4000 days")
        check(state.insights.calendar.values.allSatisfy { $0.cells.count <= 37 }, "bounded calendar cells")
        let elapsed = Date().timeIntervalSince(before)
        var changed = large
        changed.quotes = [Quote(symbol: "T0", price: 110, date: large.history.sessions.last!)]
        state.commit(changed)
        while state.rebuilding { try await Task.sleep(nanoseconds: 1_000_000) }
        check(state.insights.revision == historyID, "quote refresh reuses history and presentation")
        for i in 0..<20 {
            changed.cash = [CashRecord(sequence: 0, date: "2026-01-01", kind: .deposit, amount: Decimal(i))]
            state.commit(changed)
        }
        while state.rebuilding { try await Task.sleep(nanoseconds: 1_000_000) }
        check(state.cashTotals.deposit == 19, "only newest computation is published")
        check(state.insights.revision == historyID, "cash change does not replay securities history")
        var market = Ledger()
        market.trades = [Trade(sequence: 0, symbol: "TEST", side: .buy, date: "2026-09-15", quantity: 1, price: 90, fee: 0)]
        market.quotes = [Quote(symbol: "TEST", price: 110, date: "2026-09-17", source: "yahoo-close", previousClose: 100, previousCloseDate: "2026-09-16")]
        let premarket = ISO8601DateFormatter().date(from: "2026-09-18T05:00:00Z")!
        let closed = Engine.displayedReturn(market, now: premarket)
        check(closed.pnl == 10 && closed.title == "最近收盘收益", "yesterday close remains valid after NY midnight")
        check(closed.caption.contains("2026-09-17"), "caption uses actual price date")
        market.trades.append(Trade(sequence: 1, symbol: "TEST", side: .buy, date: "2026-09-18", quantity: 10, price: 200, fee: 5))
        check(Engine.displayedReturn(market, now: premarket).pnl == 10, "future-session trades excluded from last-close return")
        var automatic = QuoteSettings(provider: .finnhub, key: "synthetic")
        check(QuoteService.usesClosingPrices(automatic, now: premarket), "automatic premarket mode requests completed closes")
        let midday = ISO8601DateFormatter().date(from: "2026-09-18T15:00:00Z")!
        check(!QuoteService.usesClosingPrices(automatic, now: midday), "automatic regular session uses configured API")
        automatic.priceMode = "close"
        check(QuoteService.usesClosingPrices(automatic, now: midday), "explicit closing mode stays closing during session")
        automatic.priceMode = "live"
        check(!QuoteService.usesClosingPrices(automatic, now: premarket), "explicit API mode respected")
        let mondayHoliday = ISO8601DateFormatter().date(from: "2026-09-07T15:00:00Z")!
        automatic.priceMode = nil
        check(QuoteService.usesClosingPrices(automatic, now: mondayHoliday), "known holiday uses completed closes")
        let oldSettings = Data(#"{"provider":"finnhub","url":"","key":"synthetic","interval":60}"#.utf8)
        let decodedSettings = try JSONDecoder().decode(QuoteSettings.self, from: oldSettings)
        check(decodedSettings.priceMode == nil, "old API settings remain readable")
        let persistedQuote = try JSONDecoder().decode(Quote.self, from: JSONEncoder().encode(market.quotes[0]))
        check(persistedQuote.previousClose == 100 && persistedQuote.previousCloseDate == "2026-09-16", "restart retains exact baseline")
        market.quotes[0].date = "2026-09-18"
        check(Engine.todayPnl(market, previousClose: ["TEST": 100], today: "2026-09-17").pnl == nil, "future quote cannot value a past session")
        print("PASS: \(assertions) assertions; 25,000 closes / 4,000 sessions / 1,000 trades: \(elapsed)s; main actor heartbeats: \(heartbeats)")
    }
}
