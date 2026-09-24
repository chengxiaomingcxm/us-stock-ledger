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
        quoteHistoryGap()
        // 测试期间不得写真实的 Documents：诊断日志统一重定向到临时文件。
        Diagnostics.fileURLOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("stock-ledger-native-tests-diagnostics.log")
        EngineGoldenTests.run()
        try SafetyTests.run()
        try DiagnosticsTests.run()
        try await DemoModeTests.run()
        try CsvImportTests.run()
        try ErrorPathTests.run()
        try await MarketDataTests.run()
        try await LanguageTests.run()
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
        // note 只留给用户/来源数据：系统说明必须靠结构化字段在展示层生成（见 docs/ENGLISH_UI_AUDIT.md A1）。
        check(imported.trades.allSatisfy { $0.note.isEmpty } && imported.cash.allSatisfy { $0.note.isEmpty },
              "imported rows keep note empty")
        check(imported.trades.allSatisfy { $0.source == "hsbc-statement" && $0.settlementDate != nil },
              "source and settlement date stay structured")
        check(imported.cash.allSatisfy { $0.source == "hsbc-statement-net" && $0.externalId != nil },
              "dividend net amount stays structured")
        L10n.current = .en
        check(imported.trades.allSatisfy { Fmt.tradeNote($0).hasPrefix("HSBC statement; settlement ") },
              "english note is generated from structured fields")
        check(!Fmt.cashNote(imported.cash[0]).isEmpty, "english dividend note is generated too")
        L10n.current = .zhHans
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
        check(old.trades[0].settlementAmount == nil && old.trades.count == 2, "backup without settlement fields still decodes")

        // 合成演示结单（`tests/fixtures/hsbc-investment-statement-demo.pdf`，全部为虚构数据）。
        // 与上面的内联字符串不同，这里走的是**真实文件**路径：PDFKit 打开、按行重建文本层、
        // 再交给同一个 Parser，确保演示素材与解析器不会各自漂移。素材本身用
        // `scripts/make-demo-statement.mjs` 生成，该脚本会在写入后按同一套规则自检。
        let demoStatement = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/hsbc-investment-statement-demo.pdf")
        let demoPages = try StatementImport.pages(from: [demoStatement], password: "")
        check(demoPages.count == 1, "demo statement is a single page")
        check(demoPages[0].contains("SAMPLE / DEMONSTRATION ONLY"), "demo marking survives the text layer")
        let demoReport = try HSBCStatement.parse(pages: demoPages, ledger: empty)
        check(demoReport.rows.count == 6, "demo statement previews 4 trades and 2 dividends")
        check(demoReport.rows.filter(\.selected).count == 5, "non-USD fund row is not selected")
        let demoBuy = demoReport.rows.compactMap(\.trade).first { $0.symbol == "AAPL" && $0.side == .buy }
        check(demoBuy?.date == "2026-09-02" && demoBuy?.settlementDate == "2026-09-04", "demo buy keeps both dates")
        check(demoBuy?.quantity == 25 && demoBuy?.price == Decimal(string: "198.4"), "demo buy quantity and unit price")
        check(demoBuy?.fee == 1 && demoBuy?.settlementAmount == Decimal(string: "4961"), "demo buy links charge to settlement")
        check(demoBuy?.source == "hsbc-statement" && demoBuy?.externalId?.hasSuffix(":DEMO001AAPL") == true,
              "demo buy keeps source and bank reference")
        let demoSell = demoReport.rows.compactMap(\.trade).first { $0.side == .sell }
        check(demoSell?.symbol == "AAPL" && demoSell?.quantity == 10 && demoSell?.settlementAmount == Decimal(string: "2106.5"),
              "demo sell keeps quantity and settlement")
        let demoDividends = demoReport.rows.compactMap(\.cash).filter { $0.kind == .dividend }
        check(demoDividends.count == 2 && demoDividends.allSatisfy { $0.tax == nil && $0.source == "hsbc-statement-net" },
              "demo dividends stay net with unknown tax")
        check(demoDividends.map(\.amount).sorted() == [Decimal(string: "12.2")!, Decimal(string: "24.5")!],
              "demo dividend net amounts")
        check(demoReport.rows.contains { $0.trade?.symbol == "DEMOETF" && $0.issue != nil && !$0.selected },
              "non-USD unit trust is flagged instead of imported")
        let demoImported = try HSBCStatement.candidate(rows: demoReport.rows, ledger: empty, insertBefore: false)
        check(demoImported.trades.count == 3 && demoImported.cash.count == 2, "demo batch sizes")
        check(Engine.summary(demoImported).fees == 2, "each linked charge counted exactly once")
        check(empty.trades.isEmpty && empty.cash.isEmpty, "preview never mutates the ledger it was given")
        // 读结单不得写盘：把账本文件重定向到临时目录后逐字节比对（绝不指向真实 Documents）。
        let demoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stock-ledger-demo-statement-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: demoDirectory, withIntermediateDirectories: true)
        let demoFile = demoDirectory.appendingPathComponent("ledger-v2.json")
        let outerDemoFile = LedgerStore.fileURLOverride
        LedgerStore.fileURLOverride = demoFile
        var demoUserLedger = Ledger()
        demoUserLedger.trades = [Trade(sequence: 0, symbol: "KEEP", side: .buy, date: "2026-01-02",
                                       quantity: 1, price: 1, fee: 0)]
        try LedgerStore.save(demoUserLedger)
        let beforeDemoRead = try Data(contentsOf: demoFile)
        _ = try StatementImport.pages(from: [demoStatement], password: "")
        _ = try HSBCStatement.parse(pages: demoPages, ledger: try LedgerStore.decode(beforeDemoRead))
        check((try? Data(contentsOf: demoFile)) == beforeDemoRead, "reading a statement never writes the ledger file")
        LedgerStore.fileURLOverride = outerDemoFile
        try? FileManager.default.removeItem(at: demoDirectory)
        print("demo statement fixture: \(demoReport.rows.count) rows, \(demoImported.trades.count) trades, "
              + "\(demoImported.cash.count) dividends from \(demoStatement.lastPathComponent)")

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

    /// Yahoo 某天 close=null 时，只接受 Nasdaq 同日的明确收盘价，不猜盘中价。
    @MainActor
    private static func quoteHistoryGap() {
        // 使用真实日期的美东上午时刻，避免把时间戳误认成别的交易日。
        let dates = ["2026-09-21T13:30:00Z", "2026-09-22T13:30:00Z", "2026-09-23T13:30:00Z"]
        let chart: [String: Any] = ["chart": ["error": NSNull(), "result": [[
            "meta": ["symbol": "PFE", "currency": "USD", "exchangeTimezoneName": "America/New_York", "instrumentType": "EQUITY"],
            "timestamp": dates.map { ISO8601DateFormatter().date(from: $0)!.timeIntervalSince1970 },
            "indicators": ["quote": [["close": [27.74, NSNull(), 28.18]]]],
        ]]]]
        let now = ISO8601DateFormatter().date(from: "2026-09-24T11:00:00Z")!
        let yahoo = try! QuoteService.parseSeries(chart, symbol: "PFE", provider: "PFE", now: now)
        check(yahoo.missingDates == ["2026-09-22"] && yahoo.closes.count == 2, "Yahoo 空收盘价单独标记")
        let nasdaq: [String: Any] = ["status": ["rCode": 200], "data": [
            "symbol": "PFE", "tradesTable": ["rows": [
                ["date": "09/22/2026", "close": "$27.93"],
                ["date": "09/23/2026", "close": "$999"],
            ]],
        ]]
        let recovered = try! QuoteService.parseNasdaq(nasdaq, symbol: "PFE", missingDates: Set(yahoo.missingDates), now: now)
        check(recovered.count == 1 && recovered[0].date == "2026-09-22" && recovered[0].price == 27.93,
              "Nasdaq 只补指定日期的正式收盘价")
        var ledger = Ledger()
        ledger.trades = [Trade(sequence: 0, symbol: "PFE", side: .buy, date: "2026-09-21", quantity: 1, price: 27.74, fee: 0)]
        ledger.history.sessions = ["2026-09-21", "2026-09-22", "2026-09-23"]
        ledger.history.closes = yahoo.closes + recovered
        let returns = Engine.dailyReturns(ledger)
        check(returns.first { $0.date == "2026-09-22" }?.profit == 0.19, "补洞后当日收益恢复，按真实收盘价计算")
        let wrong: [String: Any] = ["status": ["rCode": 200], "data": ["symbol": "WRONG", "tradesTable": ["rows": []]]]
        check((try? QuoteService.parseNasdaq(wrong, symbol: "PFE", missingDates: ["2026-09-22"], now: now)) == nil,
              "代码不匹配时拒绝补价")

        let tiingoRows: [[String: Any]] = [
            ["date": "2026-09-22T00:00:00.000Z", "close": 27.95, "splitFactor": 1],
            ["date": "not-a-date", "close": 999, "splitFactor": 1],
        ]
        let tiingo = try! QuoteService.parseTiingo(tiingoRows, symbol: "PFE", now: now)
        check(tiingo.closes.count == 1 && tiingo.closes[0].price == 27.95 && tiingo.closes[0].source == "tiingo",
              "Tiingo 只接受有效已完成日线")
        let merged = QuoteService.mergeSeries(primary: tiingo, fallback: yahoo)
        check(merged.closes.first { $0.date == "2026-09-22" }?.price == 27.95 && merged.missingDates.isEmpty,
              "Tiingo 优先并补掉 Yahoo 明确缺口")

        let oldPoint = try! JSONDecoder().decode(PricePoint.self, from: Data(#"{"symbol":"PFE","date":"2026-09-21","price":27.74}"#.utf8))
        check(oldPoint.source == nil, "旧账本无行情来源字段仍可读取")
        let oldSettings = try! JSONDecoder().decode(QuoteSettings.self, from: Data(#"{"provider":"yahoo","url":"","key":"","interval":60}"#.utf8))
        check(oldSettings.tiingoKey == nil, "旧钥匙串设置无 Tiingo 字段仍可读取")

        var manualLedger = ledger
        manualLedger.history.closes = yahoo.closes
        let manualState = AppState(ledger: manualLedger, settings: QuoteSettings(), persist: { _ in })
        check(manualState.setHistoricalClose(symbol: "PFE", price: 27.93, date: "2026-09-22"), "可手工补已有交易日收盘")
        check(manualState.ledger.history.closes.first { $0.symbol == "PFE" && $0.date == "2026-09-22" }?.source == "manual",
              "手工收盘价带持久优先标记")
        check(!manualState.setHistoricalClose(symbol: "PFE", price: 1, date: "2026-09-20"),
              "拒绝给非收益日历日期补价")
    }
}
