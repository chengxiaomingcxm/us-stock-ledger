import Foundation

/// Phase 1 示例模式的回归测试，对应任务书 §10 的五项要求：
/// 数据集自身正确、示例加载成功、不覆盖真实数据、退出后恢复原环境、示例计算结果有效。
///
/// 所有账本文件操作都重定向到临时目录（`LedgerStore.fileURLOverride`），不碰真实 Documents。
@MainActor
enum DemoModeTests {
    /// 示例数据相对「现在」生成，测试必须钉死一个锚点日期才能复现。
    /// 锚点取美东正午：`MarketClock.date` 按美东取日期，用 UTC 零点会退到前一天。
    private static let anchor = MarketClock.day("2026-09-18")!.addingTimeInterval(12 * 3600)

    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stock-ledger-demo-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ledger-v2.json")
        let outer = LedgerStore.fileURLOverride
        LedgerStore.fileURLOverride = file
        defer {
            LedgerStore.fileURLOverride = outer
            try? FileManager.default.removeItem(at: directory)
        }

        dataset()
        await loading(file: file)
        await protectionRestored(file: file)
    }

    // MARK: - 数据集

    /// 「Demo dataset generates correctly」：规模、账本不变量、各处数据自洽、可复现。
    private static func dataset() {
        let sample = DemoData.ledger(now: anchor)
        let sessions = sample.history.sessions

        NativeTests.check(sessions.count == DemoData.sessionCount, "示例交易日数量稳定")
        NativeTests.check(sessions == sessions.sorted(), "示例交易日升序排列")
        NativeTests.check(Set(sessions).count == sessions.count, "示例交易日不重复")
        NativeTests.check(sessions.allSatisfy { !Engine.knownClosed($0) }, "示例交易日不含周末与已知休市日")
        NativeTests.check(sessions.last == "2026-09-18", "最后一天就是锚定的那一天")

        NativeTests.check((30 ... 50).contains(sample.trades.count), "示例含 30–50 笔历史交易")
        NativeTests.check(Engine.oversells(sample).isEmpty, "示例账本自身没有超卖（任一时点卖出都不超过持仓）")
        NativeTests.check(sample.trades.map(\.date) == sample.trades.map(\.date).sorted(), "示例交易按时间排列")
        NativeTests.check(Set(sample.trades.map(\.symbol)).isSuperset(of: ["AAPL", "NVDA", "MSFT", "VOO", "SGOV"]),
                          "示例包含任务书要求的 5 个标的")

        // 历史收盘价必须覆盖每个标的的每一天，否则收益日历会出现「待补全」。
        let symbols = Set(sample.history.closes.map(\.symbol))
        NativeTests.check(sample.history.closes.count == symbols.count * sessions.count,
                          "每个标的在每一个交易日都有收盘价")
        NativeTests.check(symbols.isSuperset(of: Set(sample.trades.map(\.symbol))),
                          "每一笔交易涉及过的标的都有历史收盘价")

        var held: [String: Decimal] = [:]
        for trade in sample.trades {
            held[trade.symbol, default: 0] += trade.side == .buy ? trade.quantity : -trade.quantity
        }
        NativeTests.check(held.values.contains { $0 == 0 }, "示例含一个完全卖出的标的")
        NativeTests.check(held.values.contains { $0 > 0 }, "示例含仍持有仓位的标的")
        NativeTests.check(sample.quotes.count == held.values.filter { $0 > 0 }.count, "有仓位的标的都有报价，且只有这些")

        for quote in sample.quotes {
            NativeTests.check(sample.history.closes.last { $0.symbol == quote.symbol }?.price == quote.price,
                              "报价等于最后一天收盘价（\(quote.symbol)）")
            NativeTests.check(quote.date == sessions.last && quote.previousCloseDate == sessions[sessions.count - 2],
                              "报价取最后两个交易日（\(quote.symbol)）")
            NativeTests.check(quote.previousClose != nil, "示例报价带上一收盘价，今日收益算得出来（\(quote.symbol)）")
        }

        let dividends = sample.cash.filter { $0.kind == .dividend }
        NativeTests.check((5 ... 10).contains(dividends.count), "示例含 5–10 条分红记录")
        for item in dividends {
            NativeTests.check(sample.trades.contains { $0.symbol == item.symbol && $0.side == .buy && $0.date <= item.date },
                              "分红发生时该标的已建仓（\(item.symbol ?? "?")）")
        }
        NativeTests.check(sample.cash.contains { $0.kind == .deposit }, "示例含入金")
        NativeTests.check(sample.cash.contains { $0.kind == .withdraw }, "示例含出金")
        NativeTests.check(sample.cash.contains { $0.kind == .fee }, "示例含账户费用")
        NativeTests.check(sample.opening != nil, "示例含期初余额")
        NativeTests.check(sample.cash.map(\.date) == sample.cash.map(\.date).sorted(), "示例现金流水按时间排列")

        // 现金链：只断言「每日收盘后的余额」不得为负。
        // 同一交易日内的交易与流水谁先谁后，app 从未定义（界面只按日期汇总），
        // 按某个具体顺序去断言会把一个臆想的假设写进测试。
        var byDay: [String: Decimal] = [:]
        if let opening = sample.opening { byDay[opening.date, default: 0] += opening.amount }
        for trade in sample.trades {
            byDay[trade.date, default: 0] += trade.side == .buy ? -trade.netCash : trade.netCash
        }
        for item in sample.cash { byDay[item.date, default: 0] += item.net }
        var balance = Decimal(0)
        var overdrawn: String?
        for day in byDay.keys.sorted() {
            balance += byDay[day] ?? 0
            if balance < 0, overdrawn == nil { overdrawn = day }
        }
        NativeTests.check(overdrawn == nil, "示例现金每日收盘后均不为负（最早透支 \(overdrawn ?? "—")）")

        // 确定性：同一锚点必须生成同样的日期、价格与数量（id 是随机 UUID，不参与比较）。
        let again = DemoData.ledger(now: anchor)
        let shape = { (ledger: Ledger) in ledger.trades.map { "\($0.symbol)|\($0.side)|\($0.date)|\($0.quantity)|\($0.price)|\($0.fee)" } }
        NativeTests.check(shape(sample) == shape(again), "同一锚点生成的交易完全一致")
        NativeTests.check(sample.history.sessions == again.history.sessions, "同一锚点生成的交易日完全一致")
        NativeTests.check(sample.history.closes == again.history.closes, "同一锚点生成的收盘价完全一致")
    }

    // MARK: - 加载 / 隔离 / 退出

    /// 「Demo Mode loads successfully」「does not overwrite real data」「Exit restores original state」。
    private static func loading(file: URL) async {
        var real = Ledger()
        real.trades = [Trade(sequence: 0, symbol: "REAL", side: .buy, date: "2026-01-02",
                             quantity: 3, price: decimal("7"), fee: 0)]
        try? LedgerStore.save(real)
        let before = (try? Data(contentsOf: file)) ?? Data()

        let state = AppState(settings: QuoteSettings())
        NativeTests.check(state.ledger.trades.count == 1 && !state.demo, "启动时读到的是真实账本")

        state.enterDemo()
        await settle(state)
        NativeTests.check(state.demo, "示例模式已开启")
        NativeTests.check((30 ... 50).contains(state.ledger.trades.count), "示例账本加载成功")
        NativeTests.check(state.summary.open.count == 5, "示例加载后有 5 个持仓")
        NativeTests.check(state.summary.cost > 0, "示例持仓成本为正")
        NativeTests.check(state.summary.missing.isEmpty, "示例持仓没有待报价")
        NativeTests.check(!state.dayReturns.isEmpty, "示例收益日历有数据")
        NativeTests.check(state.cashTotals.deposit > 0, "示例现金有入金")

        // 示例模式是只读沙盒：交易、报价、现金、清空四条写入路径都必须明确拒绝，
        // 既不落盘，也不留下「看起来成功了」的假象。
        let added = Trade(sequence: 999, symbol: "NEW", side: .buy, date: "2026-09-17",
                          quantity: 1, price: 1, fee: 0)
        NativeTests.check(!state.saveTrade(added), "示例模式下保存交易被拒绝")
        NativeTests.check(state.errorMessage != nil, "示例模式拒绝写入时给出可读原因")
        NativeTests.check(!state.ledger.trades.contains { $0.symbol == "NEW" }, "被拒绝的写入没有改变账本")
        state.setQuote(symbol: "AAPL", price: 999, date: "2026-09-17")
        NativeTests.check(state.ledger.quote(for: "AAPL")?.price != Decimal(999), "示例模式下改报价没有生效")
        state.saveCash(CashRecord(sequence: 999, date: "2026-09-17", kind: .deposit, amount: decimal("1"),
                                  tax: nil, symbol: nil, note: ""))
        state.clearAll()
        NativeTests.check((30 ... 50).contains(state.ledger.trades.count), "清空在示例模式下没有生效")
        NativeTests.check((try? Data(contentsOf: file)) == before, "示例模式下的写入没有落盘")

        state.exitDemo()
        await settle(state)
        NativeTests.check(!state.demo, "已退出示例模式")
        NativeTests.check(state.ledger.trades.count == 1 && state.ledger.trades[0].symbol == "REAL",
                          "退出后恢复用户自己的账本")
        NativeTests.check((try? Data(contentsOf: file)) == before, "退出示例后真实文件仍未被写入")
    }

    /// 账本读不出来时也能看示例，退出后写保护必须原样恢复。
    private static func protectionRestored(file: URL) async {
        try? Data(#"{"format":2,"trades":[{"symbol":"AAA""#.utf8).write(to: file)
        let broken = AppState(settings: QuoteSettings())
        NativeTests.check(broken.loadFailure != nil, "先确认处于读取失败状态")

        broken.enterDemo()
        await settle(broken)
        NativeTests.check(broken.ledger.trades.count > 0, "账本读不出来时仍可查看示例")

        broken.exitDemo()
        await settle(broken)
        NativeTests.check(broken.loadFailure != nil, "退出示例后写保护被恢复")
        NativeTests.check(broken.ledger.trades.isEmpty, "退出示例后内存账本回到空账本")
    }

    // MARK: - 夹具

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US"))!
    }

    /// 派生结果是异步重算的，读 `summary` 之类之前必须等它结束。
    private static func settle(_ state: AppState) async {
        var waited = 0
        while state.rebuilding && waited < 20_000 {
            try? await Task.sleep(nanoseconds: 1_000_000)
            waited += 1
        }
        NativeTests.check(!state.rebuilding, "后台重算在 20 秒内完成")
    }
}
