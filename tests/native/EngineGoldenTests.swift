import Foundation

/// Phase 0.5 护栏：`Engine` 核心计算的「金标准」测试。
///
/// 规则：
/// 1. 期望值全部由夹具输入**人工推导**后写成字面量，绝不用 `Engine.xxx(...)` 的输出当期望值。
/// 2. 口径以当前产品定义为准（注释里写明推导过程），并与 TypeScript 端口 `tests/*.test.ts` 保持一致。
///
/// 覆盖：`Engine.summary` / `Engine.cashTotals` / `Engine.dailyReturns` / `Engine.todayPnl`。
/// 用 `NativeTests.check` 计数，因此不需要改动 `NativeTests.swift` 的断言统计逻辑。
enum EngineGoldenTests {
    // MARK: - 夹具构造

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US"))!
    }

    private static func trade(_ sequence: Int, _ symbol: String, _ side: TradeSide, _ date: String,
                              _ quantity: String, _ price: String, _ fee: String = "0") -> Trade {
        Trade(sequence: sequence, symbol: symbol, side: side, date: date,
              quantity: decimal(quantity), price: decimal(price), fee: decimal(fee))
    }

    private static func quote(_ symbol: String, _ price: String, _ date: String) -> Quote {
        Quote(symbol: symbol, price: decimal(price), date: date, source: nil, fetchedAt: nil)
    }

    private static func cash(_ sequence: Int, _ date: String, _ kind: CashKind,
                             _ amount: String, _ tax: String? = nil) -> CashRecord {
        CashRecord(sequence: sequence, date: date, kind: kind, amount: decimal(amount),
                   tax: tax.map(decimal), symbol: nil, note: "")
    }

    private static func expect(_ actual: Decimal?, _ expected: String, _ label: String) {
        NativeTests.check(actual == decimal(expected),
                          "\(label) — 期望 \(expected)，实际 \(String(describing: actual))")
    }

    private static func expectNil(_ actual: Decimal?, _ label: String) {
        NativeTests.check(actual == nil, "\(label) — 期望 nil（待补全），实际 \(String(describing: actual))")
    }

    /// 百分比是除不尽的循环小数，用容差比较，避免把 Decimal 的舍入精度当成业务断言。
    private static func expectApprox(_ actual: Decimal?, _ expected: String, _ tolerance: String, _ label: String) {
        guard let actual else {
            NativeTests.check(false, "\(label) — 期望约 \(expected)，实际 nil")
            return
        }
        let difference = actual - decimal(expected)
        let bound = decimal(tolerance)
        NativeTests.check(difference <= bound && difference >= -bound,
                          "\(label) — 期望约 \(expected)，实际 \(actual)")
    }

    // MARK: - Engine.summary

    /// 多笔买入：成本含买入手续费，移动平均价 = 总成本 / 总股数。
    private static func summaryMultipleBuys() {
        var ledger = Ledger()
        ledger.trades = [
            trade(0, "AAPL", .buy, "2026-01-05", "10", "100", "1"),
            trade(1, "AAPL", .buy, "2026-01-06", "10", "120", "1"),
        ]
        ledger.quotes = [quote("AAPL", "130", "2026-01-07")]

        // 人工推导：
        //   成本 = 10×100 + 1 = 1001；再 + 10×120 + 1 = 1201 → 2202
        //   股数 = 20；移动平均价 = 2202 / 20 = 110.1
        //   市值 = 20 × 130 = 2600；浮动 = 2600 − 2202 = 398；已实现 = 0；总盈亏 = 398
        //   手续费合计 = 1 + 1 = 2
        let summary = Engine.summary(ledger)
        NativeTests.check(summary.positions.count == 1 && summary.open.count == 1, "summary/多笔买入 — 单笔未平仓")
        NativeTests.check(summary.missing.isEmpty, "summary/多笔买入 — 行情齐全")
        expect(summary.positions.first?.quantity, "20", "summary/多笔买入 — 股数")
        expect(summary.positions.first?.cost, "2202", "summary/多笔买入 — 成本（含买入费）")
        expect(summary.positions.first?.average, "110.1", "summary/多笔买入 — 移动平均价")
        expect(summary.realized, "0", "summary/多笔买入 — 已实现盈亏")
        expect(summary.value, "2600", "summary/多笔买入 — 市值")
        expect(summary.unrealized, "398", "summary/多笔买入 — 浮动盈亏")
        expect(summary.totalProfit, "398", "summary/多笔买入 — 总盈亏")
        expect(summary.fees, "2", "summary/多笔买入 — 手续费合计")
    }

    /// 部分卖出：按卖出前的移动平均成本扣减，卖出费直接冲减收益，均价不变。
    private static func summaryPartialSell() {
        var ledger = Ledger()
        ledger.trades = [
            trade(0, "AAPL", .buy, "2026-01-05", "10", "100", "1"),
            trade(1, "AAPL", .buy, "2026-01-06", "10", "120", "1"),
            trade(2, "AAPL", .sell, "2026-01-07", "5", "150", "1"),
        ]
        ledger.quotes = [quote("AAPL", "130", "2026-01-07")]

        // 人工推导：
        //   卖出毛额 = 5 × 150 = 750
        //   removed = 2202 × 5/20 = 550.5
        //   已实现 = 750 − 1（卖出费） − 550.5 = 198.5
        //   剩余成本 = 2202 − 550.5 = 1651.5；股数 = 15
        //   均价 = 1651.5 / 15 = 110.1 —— 与卖出前一致（移动平均法的关键不变量）
        //   市值 = 15 × 130 = 1950；浮动 = 1950 − 1651.5 = 298.5
        //   总盈亏 = 298.5 + 198.5 = 497；手续费合计 = 1 + 1 + 1 = 3
        let summary = Engine.summary(ledger)
        NativeTests.check(summary.positions.count == 1 && summary.open.count == 1, "summary/部分卖出 — 仍为未平仓")
        expect(summary.positions.first?.quantity, "15", "summary/部分卖出 — 剩余股数")
        expect(summary.positions.first?.cost, "1651.5", "summary/部分卖出 — 剩余成本")
        expect(summary.positions.first?.average, "110.1", "summary/部分卖出 — 均价不因卖出改变")
        expect(summary.positions.first?.realized, "198.5", "summary/部分卖出 — 该股已实现")
        expect(summary.realized, "198.5", "summary/部分卖出 — 合计已实现")
        expect(summary.value, "1950", "summary/部分卖出 — 市值")
        expect(summary.unrealized, "298.5", "summary/部分卖出 — 浮动盈亏")
        expect(summary.totalProfit, "497", "summary/部分卖出 — 总盈亏")
        expect(summary.fees, "3", "summary/部分卖出 — 手续费合计")
    }

    /// 全部卖出：removed 取剩余成本全值，之后该股不再是未平仓。
    private static func summaryFullSell() {
        var ledger = Ledger()
        ledger.trades = [
            trade(0, "AAPL", .buy, "2026-01-05", "10", "100", "1"),
            trade(1, "AAPL", .buy, "2026-01-06", "10", "120", "1"),
            trade(2, "AAPL", .sell, "2026-01-07", "5", "150", "1"),
            trade(3, "AAPL", .sell, "2026-01-08", "15", "160", "1.5"),
        ]
        ledger.quotes = [quote("AAPL", "130", "2026-01-08")]

        // 人工推导：
        //   清仓毛额 = 15 × 160 = 2400；removed = 全部剩余成本 1651.5
        //   该笔已实现 = 2400 − 1.5 − 1651.5 = 747
        //   合计已实现 = 198.5 + 747 = 945.5
        //   无未平仓 → 市值 0、浮动 0、总盈亏 0 + 945.5 = 945.5
        //   手续费合计 = 1 + 1 + 1 + 1.5 = 4.5
        let summary = Engine.summary(ledger)
        NativeTests.check(summary.open.isEmpty, "summary/全部卖出 — 无未平仓")
        NativeTests.check(summary.positions.first?.quantity == 0, "summary/全部卖出 — 股数归零")
        expect(summary.positions.first?.cost, "0", "summary/全部卖出 — 成本归零")
        expect(summary.realized, "945.5", "summary/全部卖出 — 合计已实现")
        expect(summary.value, "0", "summary/全部卖出 — 无持仓市值为 0")
        expect(summary.unrealized, "0", "summary/全部卖出 — 无持仓浮动为 0")
        expect(summary.totalProfit, "945.5", "summary/全部卖出 — 总盈亏 = 已实现")
        expect(summary.fees, "4.5", "summary/全部卖出 — 手续费合计")
        expect(summary.gains[ledger.trades[3].id], "747", "summary/全部卖出 — 清仓那笔的已实现")
    }

    /// 未平仓但缺行情：市值 / 浮动 / 总盈亏必须是 nil，绝不按零顶替。
    private static func summaryMissingQuote() {
        var ledger = Ledger()
        ledger.trades = [trade(0, "AAPL", .buy, "2026-01-05", "10", "100", "0")]
        NativeTests.check(Engine.summary(ledger).missing.count == 1, "summary/缺行情 — 计入 missing")
        expectNil(Engine.summary(ledger).value, "summary/缺行情 — 市值")
        expectNil(Engine.summary(ledger).unrealized, "summary/缺行情 — 浮动盈亏")
        expectNil(Engine.summary(ledger).totalProfit, "summary/缺行情 — 总盈亏")
        expect(Engine.summary(ledger).cost, "1000", "summary/缺行情 — 成本仍可计算")
    }

    // MARK: - Engine.cashTotals（分红 / 税费 / 出入金口径）

    /// 出入金永远不是投资收益；分红按净额（扣预扣税）计入投资现金流。
    private static func cashTotalsGolden() {
        var ledger = Ledger()
        ledger.opening = CashOpening(amount: decimal("5000"), date: "2026-01-01", note: "")
        ledger.trades = [
            trade(0, "AAPL", .buy, "2026-01-05", "10", "100", "1"),
            trade(1, "AAPL", .sell, "2026-02-02", "4", "150", "1"),
        ]
        ledger.cash = [
            cash(0, "2026-01-02", .deposit, "20000"),
            cash(1, "2026-01-03", .withdraw, "1500"),
            cash(2, "2026-01-15", .dividend, "30", "4.5"),
            cash(3, "2026-01-20", .fee, "1.25"),
        ]

        // 人工推导（全部发生在期初日 2026-01-01 当天及之后，都计入边界内）：
        //   出入金净额 externalNet = 20000 − 1500 = 18500
        //   投资净额 investNet = 30 − 4.5（预扣税） − 1.25（账户费用） = 24.25
        //   买入现金流 = −(10×100 + 1) = −1001；卖出现金流 = +(4×150 − 1) = +599
        //   余额 = 5000 + 20000 − 1500 + 30 − 4.5 − 1.25 − 1001 + 599 = 23122.25
        let totals = Engine.cashTotals(ledger)
        expect(totals.opening, "5000", "cashTotals — 期初余额")
        expect(totals.deposit, "20000", "cashTotals — 入金")
        expect(totals.withdraw, "1500", "cashTotals — 出金")
        expect(totals.dividend, "30", "cashTotals — 分红毛额")
        expect(totals.tax, "4.5", "cashTotals — 预扣税")
        expect(totals.fee, "1.25", "cashTotals — 账户费用")
        expect(totals.externalNet, "18500", "cashTotals — 出入金净额")
        expect(totals.investNet, "24.25", "cashTotals — 投资净额（分红净额 − 费用）")
        expect(totals.buyOut, "1001", "cashTotals — 买入支出（含费）")
        expect(totals.sellIn, "599", "cashTotals — 卖出收入（扣费）")
        expect(totals.balance, "23122.25", "cashTotals — 期末余额")

        // 证券口径必须完全不受现金流水影响（入金出金不进收益）。
        let summary = Engine.summary(ledger)
        // 买入 10@100 费 1 → 成本 1001；卖出 4 股：removed = 1001 × 4/10 = 400.4
        // 已实现 = 4×150 − 1 − 400.4 = 198.6；剩余成本 600.6、股数 6
        expect(summary.realized, "198.6", "cashTotals — 出入金/分红不影响已实现盈亏")
        expect(summary.positions.first?.cost, "600.6", "cashTotals — 出入金/分红不影响持仓成本")
        expectNil(summary.value, "cashTotals — 无行情时市值仍为 nil（不因现金而造假）")
    }

    // MARK: - Engine.dailyReturns

    /// 组装：3 个交易日，持仓 10 股，收盘 10 → 12 → 11。
    private static func dailyLedger() -> Ledger {
        var ledger = Ledger()
        ledger.trades = [trade(0, "AAA", .buy, "2026-01-05", "10", "10", "0")]
        ledger.history.sessions = ["2026-01-05", "2026-01-06", "2026-01-07"]
        ledger.history.closes = [
            PricePoint(symbol: "AAA", date: "2026-01-05", price: decimal("10")),
            PricePoint(symbol: "AAA", date: "2026-01-06", price: decimal("12")),
            PricePoint(symbol: "AAA", date: "2026-01-07", price: decimal("11")),
        ]
        return ledger
    }

    private static func dailyReturnsNormal() {
        let days = Engine.dailyReturns(dailyLedger())
        NativeTests.check(days.count == 3, "dailyReturns/正常 — 三个交易日")
        // 人工推导：
        //   01-05（建仓日）：期末 10×10 = 100，期初 0，当日买入现金流 −(10×10) = −100
        //                    收益 = 100 − 0 + (−100) = 0（买在当天收盘价上，不产生收益）
        //   01-06：10×12 − 10×10 = 120 − 100 = 20
        //   01-07：10×11 − 10×12 = 110 − 120 = −10
        expect(days[0].profit, "0", "dailyReturns/正常 — 建仓日不把本金当收益")
        expect(days[1].profit, "20", "dailyReturns/正常 — 第二个交易日")
        expect(days[2].profit, "-10", "dailyReturns/正常 — 第三个交易日")
        NativeTests.check(days.allSatisfy { $0.missing.isEmpty }, "dailyReturns/正常 — 无待补全")
        // 累计 = 期末市值 + 累计交易净现金流：01-05 = 100 − 100 = 0；01-06 = 120 − 100 = 20；01-07 = 110 − 100 = 10
        expect(days[0].cumulative, "0", "dailyReturns/正常 — 累计曲线首日")
        expect(days[1].cumulative, "20", "dailyReturns/正常 — 累计曲线次日")
        expect(days[2].cumulative, "10", "dailyReturns/正常 — 累计曲线末日等于收益之和")
        expect(days.reduce(Decimal(0)) { $0 + ($1.profit ?? 0) }, "10", "dailyReturns/正常 — 每日收益之和与曲线一致")
    }

    /// 出入金/分红记录不得被算成投资收益：加入现金流水后每日收益必须逐日不变。
    private static func dailyReturnsIgnoreCashFlows() {
        let base = Engine.dailyReturns(dailyLedger())
        var withCash = dailyLedger()
        withCash.opening = CashOpening(amount: decimal("5000"), date: "2026-01-01", note: "")
        withCash.cash = [
            cash(0, "2026-01-06", .deposit, "10000"),
            cash(1, "2026-01-07", .withdraw, "2500"),
            cash(2, "2026-01-06", .dividend, "50", "7.5"),
            cash(3, "2026-01-07", .fee, "3"),
        ]
        let after = Engine.dailyReturns(withCash)
        NativeTests.check(after.count == base.count, "dailyReturns/现金流 — 交易日数量不变")
        for index in base.indices {
            NativeTests.check(after[index].profit == base[index].profit,
                              "dailyReturns/现金流 — 第 \(index + 1) 日收益不因出入金/分红改变")
            NativeTests.check(after[index].cumulative == base[index].cumulative,
                              "dailyReturns/现金流 — 第 \(index + 1) 日累计曲线不因现金流水改变")
        }
        // 现金余额本身要变化，证明确实读到了这些记录（否则上面的相等是假阳性）。
        expect(Engine.cashTotals(withCash).balance, "12439.5", "dailyReturns/现金流 — 现金余额已计入流水")
    }

    /// 相邻收盘记录之间夹着未确认工作日 → 该日待补全，不按零计算。
    private static func dailyReturnsGap() {
        var ledger = Ledger()
        ledger.trades = [trade(0, "AAA", .buy, "2026-01-05", "10", "10", "0")]
        ledger.history.sessions = ["2026-01-05", "2026-01-08"]  // 01-06、01-07 是工作日但未确认
        ledger.history.closes = [
            PricePoint(symbol: "AAA", date: "2026-01-05", price: decimal("10")),
            PricePoint(symbol: "AAA", date: "2026-01-08", price: decimal("12")),
        ]
        let days = Engine.dailyReturns(ledger)
        NativeTests.check(days.count == 2, "dailyReturns/Gap — 两个交易日")
        expect(days[0].profit, "0", "dailyReturns/Gap — 首日正常")
        expectNil(days[1].profit, "dailyReturns/Gap — 中间有未确认工作日，当日待补全")
        NativeTests.check(days[1].missing.count == 1, "dailyReturns/Gap — 记录一条待补全原因")
    }

    /// 缺少当日收盘价 → 待补全。
    private static func dailyReturnsMissingClose() {
        var ledger = Ledger()
        ledger.trades = [trade(0, "AAA", .buy, "2026-01-05", "10", "10", "0")]
        ledger.history.sessions = ["2026-01-05", "2026-01-06"]
        ledger.history.closes = [PricePoint(symbol: "AAA", date: "2026-01-05", price: decimal("10"))]
        let days = Engine.dailyReturns(ledger)
        expect(days[0].profit, "0", "dailyReturns/缺收盘 — 首日正常")
        expectNil(days[1].profit, "dailyReturns/缺收盘 — 当日无收盘价时待补全")
        expectNil(days[1].cumulative, "dailyReturns/缺收盘 — 曲线同样待补全")
    }

    // MARK: - Engine.todayPnl

    private static func todayLedger() -> Ledger {
        var ledger = Ledger()
        ledger.trades = [trade(0, "AAA", .buy, "2026-01-05", "10", "100", "0")]
        ledger.quotes = [quote("AAA", "121", "2026-01-07")]
        return ledger
    }

    private static func todayPnlNormal() {
        // 人工推导：期初 10 股 × 上一收盘 110 = 1100；期末 10 股 × 当日 121 = 1210
        //           当日无买卖 → 收益 1210 − 1100 = 110；基准 1100；百分比 110/1100 = 0.1
        let result = Engine.todayPnl(todayLedger(), previousClose: ["AAA": decimal("110")],
                                     previousCloseDates: ["AAA": "2026-01-06"], today: "2026-01-07")
        expect(result.pnl, "110", "todayPnl/正常 — 当日盈亏")
        expect(result.basis, "1100", "todayPnl/正常 — 基准市值")
        expect(result.percent, "0.1", "todayPnl/正常 — 涨跌百分比")
        NativeTests.check(result.missing.isEmpty && result.tradedToday == 0, "todayPnl/正常 — 无待补全、当日无成交")
    }

    private static func todayPnlMissingPreviousClose() {
        // 有期初持仓但拿不到上一交易日收盘价 → 待补全，绝不用当日价当基准。
        let result = Engine.todayPnl(todayLedger(), previousClose: [:],
                                     previousCloseDates: [:], today: "2026-01-07")
        expectNil(result.pnl, "todayPnl/缺上一收盘 — 待补全")
        expectNil(result.percent, "todayPnl/缺上一收盘 — 百分比同样待补全")
        expectNil(result.basis, "todayPnl/缺上一收盘 — 基准不可用")
        NativeTests.check(result.missing.count == 1, "todayPnl/缺上一收盘 — 记录一条原因")
    }

    private static func todayPnlPositionChange() {
        var ledger = todayLedger()
        ledger.trades.append(trade(1, "AAA", .buy, "2026-01-07", "5", "120", "2"))
        // 人工推导：期初 10 股 × 110 = 1100；期末 15 股 × 121 = 1815
        //           当日买入成本 5×120 + 2 = 602
        //           收益 = 1815 − 1100 − 602 = 113
        //           （拆开看：老仓 10 股 110→121 = +110，新仓 5 股 120→121 = +5，手续费 −2）
        //           基准仍为 1100；百分比 113/1100 = 0.1027272727...
        let result = Engine.todayPnl(ledger, previousClose: ["AAA": decimal("110")],
                                     previousCloseDates: ["AAA": "2026-01-06"], today: "2026-01-07")
        expect(result.pnl, "113", "todayPnl/当日加仓 — 当日盈亏")
        expect(result.basis, "1100", "todayPnl/当日加仓 — 基准为当日之前的持仓市值")
        NativeTests.check(result.tradedToday == 1, "todayPnl/当日加仓 — 记录一笔当日成交")
    }

    private static func todayPnlSameDaySell() {
        var ledger = todayLedger()
        ledger.trades.append(trade(1, "AAA", .sell, "2026-01-07", "4", "130", "1"))
        ledger.quotes = [quote("AAA", "130", "2026-01-07")]
        // 人工推导：期初 10 股 × 110 = 1100；期末 6 股 × 130 = 780
        //           当日卖出净收入 = 4×130 − 1 = 519
        //           收益 = 780 − 1100 + 519 = 199
        //           （拆开看：留仓 6 股 110→130 = +120，卖出 4 股 110→130 = +80，手续费 −1）
        //           卖出所得是资产形态转换，不是收益，因此必须用 sellNet 而非 gross。
        let result = Engine.todayPnl(ledger, previousClose: ["AAA": decimal("110")],
                                     previousCloseDates: ["AAA": "2026-01-06"], today: "2026-01-07")
        expect(result.pnl, "199", "todayPnl/当日卖出 — 当日盈亏")
        expect(result.basis, "1100", "todayPnl/当日卖出 — 基准市值")
        expectApprox(result.percent, "0.1809090909090909", "0.0000000000001", "todayPnl/当日卖出 — 涨跌百分比 199/1100")
    }

    /// 上一收盘价日期不早于今天（行情错位）→ 待补全，防止把当日价当基准。
    private static func todayPnlStaleBaseline() {
        let result = Engine.todayPnl(todayLedger(), previousClose: ["AAA": decimal("110")],
                                     previousCloseDates: ["AAA": "2026-01-07"], today: "2026-01-07")
        expectNil(result.pnl, "todayPnl/基准日期异常 — 待补全")
    }

    // MARK: - 入口

    static func run() {
        summaryMultipleBuys()
        summaryPartialSell()
        summaryFullSell()
        summaryMissingQuote()
        cashTotalsGolden()
        dailyReturnsNormal()
        dailyReturnsIgnoreCashFlows()
        dailyReturnsGap()
        dailyReturnsMissingClose()
        todayPnlNormal()
        todayPnlMissingPreviousClose()
        todayPnlPositionChange()
        todayPnlSameDaySell()
        todayPnlStaleBaseline()
    }
}
