import Foundation

/// Phase 4（任务书 §9 · Import）：原生 CSV 导入的最小回归。
///
/// 为什么需要它：`tests/csv-import.test.ts` 覆盖的是 **Web 引擎**，而原生与 Web 是两套独立实现，
/// 共享的只有概念口径、不是代码 —— Web 的 23 个用例证明不了 Swift 这一侧。
/// 这里只覆盖 §9 点名的四类（合法 / 非法 / 缺字段 / 重复），外加整批超卖与错误文案可翻译两条契约。
///
/// 注意：本文件不在 Xcode 工程里，但**必须**加进 `scripts/test-native.sh` 的编译列表，
/// 否则漏登记时脚本照样编译、照样打印 PASS —— 那就是本仓库踩过的「假绿」陷阱。
@MainActor
enum CsvImportTests {
    private static func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US"))!
    }

    private static let tradeCSV = """
    Date,Symbol,Side,Quantity,Price,Fee,TradeID,Note
    2026-09-10,AAPL,BUY,10,220.5,1,T-1001,DCA
    2026-09-11,MSFT,BUY,2,390,1,T-1002,Trim
    """

    static func run() throws {
        try valid()
        try missingFields()
        try invalidFile()
        try duplicates()
        try oversellBatch()
        try sameDayBatchOrder()
        try messages()
    }

    // MARK: - 合法 CSV

    private static func valid() throws {
        let report = try CsvImport.analyze(text: tradeCSV, ledger: Ledger())
        NativeTests.check(report.header.count == 8, "合法 CSV：识别到 8 列")
        NativeTests.check(report.rows.count == 2, "合法 CSV：两行都进入预览")
        NativeTests.check(report.rows.allSatisfy { $0.status == .ready && $0.selected },
                          "合法 CSV：行标记为可导入且默认勾选")
        NativeTests.check(report.batchError == nil, "合法 CSV：整批校验通过")
        NativeTests.check(report.rows[0].line == 2, "合法 CSV：行号是真实文件行号")
        NativeTests.check(report.rows[0].trade?.symbol == "AAPL"
                          && report.rows[0].trade?.side == .buy
                          && report.rows[0].trade?.date == "2026-09-10"
                          && report.rows[0].trade?.quantity == dec("10")
                          && report.rows[0].trade?.price == dec("220.5")
                          && report.rows[0].trade?.fee == dec("1")
                          && report.rows[0].trade?.externalId == "T-1001",
                          "合法 CSV：字段映射与取值逐一正确")

        NativeTests.check(CsvImport.detectMode(["Date", "Symbol", "Side", "Quantity", "Price"]) == .trade,
                          "成交明细表头识别为交易")
        NativeTests.check(CsvImport.detectMode(["Date", "Type", "Amount"]) == .cash,
                          "资金流水表头识别为现金")
    }

    // MARK: - 缺字段

    private static func missingFields() throws {
        // 行内缺值：只这一行报错，其它行不受影响。
        let sparse = """
        Date,Symbol,Side,Quantity,Price,Fee
        2026-09-10,,BUY,10,220.5,1
        2026-09-11,MSFT,BUY,2,390,1
        """
        let report = try CsvImport.analyze(text: sparse, ledger: Ledger())
        NativeTests.check(report.rows.count == 2, "缺值：两行都保留在预览里")
        NativeTests.check(report.rows[0].status == .error, "缺值：缺代码的行标为无法导入")
        NativeTests.check(report.rows[0].message == L10n.tr("缺少代码"), "缺值：给出可读原因")
        NativeTests.check(report.rows[0].trade == nil, "缺值：报错行不带交易")
        NativeTests.check(report.rows[1].status == .ready, "缺值：不影响同一文件里的其它行")

        // 整列缺失：整批拒绝，而不是把空值当 0 悄悄写进去。
        NativeTests.rejects("缺少必需列时整批拒绝") {
            _ = try CsvImport.analyze(text: "Date,Symbol,Side\n2026-09-10,AAPL,BUY", ledger: Ledger())
        }
    }

    // MARK: - 非法 CSV

    private static func invalidFile() throws {
        NativeTests.rejects("空文件没有可识别表头") {
            _ = try CsvImport.analyze(text: "", ledger: Ledger())
        }
        NativeTests.rejects("只有表头没有数据行") {
            _ = try CsvImport.analyze(text: "Date,Symbol,Side,Quantity,Price", ledger: Ledger())
        }
        NativeTests.rejects("无法识别的编码明确报错") {
            _ = try CsvImport.decode(Data([0x00, 0xd8, 0x00, 0xe0]))
        }
        // 行内取值非法不属于「整批失败」：这两条要变成无法导入的行，而不是抛异常终止预览。
        let badQuantity = try CsvImport.analyze(
            text: "Date,Symbol,Side,Quantity,Price\n2026-09-10,AAPL,BUY,abc,220.5", ledger: Ledger())
        NativeTests.check(badQuantity.rows.first?.status == .error, "非法 CSV：数量不是数字 → 该行无法导入")
        NativeTests.check(badQuantity.rows.first?.message?.isEmpty == false, "非法 CSV：报错行带可读原因")

        let future = try CsvImport.analyze(
            text: "Date,Symbol,Side,Quantity,Price\n2999-01-01,AAPL,BUY,1,1", ledger: Ledger())
        NativeTests.check(future.rows.first?.status == .error, "非法 CSV：日期晚于今天 → 该行无法导入")

        // `check` 的 autoclosure 是非抛出的，会抛的调用要先取出来。
        let decoded = try CsvImport.decode(Data("Date,Symbol".utf8))
        NativeTests.check(decoded == "Date,Symbol", "UTF-8 文本可解码")
    }

    // MARK: - 重复数据

    private static func duplicates() throws {
        // ① 与账本里已有成交编号相同 → 已导入，不重复记账。
        let withId = Ledger(trades: [Trade(sequence: 0, symbol: "AAPL", side: .buy, date: "2026-09-10",
                                          quantity: dec("10"), price: dec("220.5"), fee: dec("1"),
                                          externalId: "T-1001")])
        let byId = try CsvImport.analyze(text: tradeCSV, ledger: withId)
        NativeTests.check(byId.rows[0].status == .duplicate, "重复：成交编号已在账本里 → 已导入")
        NativeTests.check(byId.rows[0].selected == false, "重复：默认不勾选")
        NativeTests.check(byId.rows[1].status == .ready, "重复：只影响命中编号的那一行")

        // ② 没有编号，但日期/代码/方向/数量/单价/手续费完全相同 → 疑似重复。
        let noId = Ledger(trades: [Trade(sequence: 0, symbol: "AAPL", side: .buy, date: "2026-09-10",
                                         quantity: dec("10"), price: dec("220.5"), fee: dec("1"))])
        let bySignature = try CsvImport.analyze(text: tradeCSV, ledger: noId)
        NativeTests.check(bySignature.rows[0].status == .suspected, "重复：六项全同 → 疑似重复")

        // ③ 文件内部两条相同编号 → 第二条也算重复。
        let sameFile = """
        Date,Symbol,Side,Quantity,Price,Fee,TradeID
        2026-09-10,AAPL,BUY,10,220.5,1,T-9
        2026-09-11,AAPL,BUY,3,230,1,T-9
        """
        let inFile = try CsvImport.analyze(text: sameFile, ledger: Ledger())
        NativeTests.check(inFile.rows[0].status == .ready && inFile.rows[1].status == .duplicate,
                          "重复：文件内重复编号按第二条起跳过")
    }

    // MARK: - 整批超卖

    private static func oversellBatch() throws {
        let holding = Ledger(trades: [Trade(sequence: 0, symbol: "AAPL", side: .buy, date: "2026-09-01",
                                            quantity: dec("5"), price: dec("100"), fee: 0)])
        let report = try CsvImport.analyze(text: "Date,Symbol,Side,Quantity,Price,Fee\n2026-09-10,AAPL,SELL,6,120,0",
                                           ledger: holding)
        NativeTests.check(report.rows.first?.status == .ready, "超卖：单行本身是合法的")
        NativeTests.check(report.batchError != nil, "超卖：与账本叠加后整批拒绝并给出说明")

        let fits = try CsvImport.analyze(text: "Date,Symbol,Side,Quantity,Price,Fee\n2026-09-10,AAPL,SELL,5,120,0",
                                         ledger: holding)
        NativeTests.check(fits.batchError == nil, "超卖：卖满持仓不算超卖")
    }

    /// 独立手算：100@10 + 100@20 后卖 100@30，已实现 1500，余成本 1500。
    /// 之后原有的 1@10 加入，最终成本 1510、股数 101。反转买卖会错误算成 2000/2010。
    private static func sameDayBatchOrder() throws {
        let old = Ledger(trades: [
            Trade(sequence: 0, symbol: "AAA", side: .buy, date: "2026-01-01", quantity: 100, price: 10, fee: 0),
            Trade(sequence: 1, symbol: "AAA", side: .buy, date: "2026-01-02", quantity: 1, price: 10, fee: 0),
        ])
        let report = try CsvImport.analyze(text: "Date,Symbol,Side,Quantity,Price,Fee\n2026-01-02,AAA,BUY,100,20,0\n2026-01-02,AAA,SELL,100,30,0", ledger: old)
        let incoming = report.rows.compactMap(\.trade)
        let before = CsvImport.candidate(ledger: old, rows: report.rows, insertBeforeSameDay: true)
        NativeTests.check(before.orderedTrades.map(\.id) == [old.trades[0].id, incoming[0].id, incoming[1].id, old.trades[1].id], "插前：保留批次买卖顺序")
        NativeTests.check(CsvImport.validate(before) == nil, "插前：历史持仓合法")
        let summary = Engine.summary(before)
        NativeTests.check(summary.realized == 1500 && summary.cost == 1510 && summary.open.first?.quantity == 101,
                          "插前：已实现1500、剩余成本1510、股数101")
        let after = CsvImport.candidate(ledger: old, rows: report.rows, insertBeforeSameDay: false)
        NativeTests.check(after.orderedTrades.map(\.id) == [old.trades[0].id, old.trades[1].id, incoming[0].id, incoming[1].id], "追加：原有顺序不变")
        let empty = CsvImport.merge([], incoming, insertBeforeSameDay: true)
        NativeTests.check(empty.map(\.id) == incoming.map(\.id), "空账本插前：先买后卖不反转")
        NativeTests.check(CsvImport.validate(Ledger(trades: empty)) == nil, "空账本插前：不制造超卖")
        let mixed = CsvImport.merge([], [incoming[0], old.trades[0], incoming[1]], insertBeforeSameDay: true)
        NativeTests.check(mixed.map(\.id) == [old.trades[0].id, incoming[0].id, incoming[1].id], "跨日期插前：日期升序、同日原顺序")
        NativeTests.check(before.trades.map(\.sequence) == Array(0..<4), "插前：sequence 唯一连续")
        let rows = incoming.map { HSBCStatement.Row(id: $0.id.uuidString, trade: $0, currency: "USD") }
        let pdf = try HSBCStatement.candidate(rows: rows, ledger: old, insertBefore: true)
        NativeTests.check(pdf.orderedTrades.map(\.id) == before.orderedTrades.map(\.id), "PDF：共用合并路径保留买卖顺序")
    }

    // MARK: - 错误文案可翻译（Phase 3 的契约）

    private static func messages() throws {
        let saved = L10n.current
        defer { L10n.current = saved }

        L10n.current = .en
        NativeTests.check(CsvImportError.message(L10n.tr("缺少代码")).errorDescription == "Missing symbol",
                          "错误文案：英文模式下可翻译")
        NativeTests.check(CsvImportError.message(L10n.tr("{}无效", "Quantity")).errorDescription == "Quantity is invalid.",
                          "错误文案：带占位符的整句在英文模式下不再是中文")

        L10n.current = .zhHans
        NativeTests.check(CsvImportError.message(L10n.tr("缺少代码")).errorDescription == "缺少代码",
                          "错误文案：中文模式下原样返回")
    }
}
