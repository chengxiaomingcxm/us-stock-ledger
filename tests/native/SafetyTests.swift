import Foundation

/// Phase 0.5 护栏：两个真实数据安全 P0 的回归测试。
///
/// - P0-1：账本存在但读不出来时，不得静默返回空账本，也不得让后续保存覆盖原文件。
/// - P0-2：手动录入路径不得把「卖出超过当时持仓」写进账本（负持仓 / 错误成本）。
///
/// 所有账本文件操作都被重定向到临时目录（`LedgerStore.fileURLOverride`），不碰真实 Documents。
@MainActor
enum SafetyTests {
    // MARK: - 夹具

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US"))!
    }

    private static func trade(_ sequence: Int, _ side: TradeSide, _ quantity: String, _ date: String,
                              symbol: String = "AAA") -> Trade {
        Trade(sequence: sequence, symbol: symbol, side: side, date: date,
              quantity: decimal(quantity), price: decimal("10"), fee: decimal("0"))
    }

    private static func ledger(_ trades: [Trade]) -> Ledger {
        var value = Ledger()
        value.trades = trades
        return value
    }

    /// 注入内存账本 + 空持久化：不读写磁盘、不访问钥匙串。
    private static func state(_ trades: [Trade]) -> AppState {
        AppState(ledger: ledger(trades), settings: QuoteSettings(), persist: { _ in })
    }

    private static func isMissing(_ result: LedgerStore.LoadResult) -> Bool {
        if case .missing = result { return true }
        return false
    }

    private static func isFailed(_ result: LedgerStore.LoadResult) -> Bool {
        if case .failed = result { return true }
        return false
    }

    private static func isLoaded(_ result: LedgerStore.LoadResult) -> Bool {
        if case .loaded = result { return true }
        return false
    }

    // MARK: - P0-1

    private static func unreadableLedgerIsNotAnEmptyLedger(_ file: URL) throws {
        // 没有文件：合法的首次启动，可以正常写入。
        try? FileManager.default.removeItem(at: file)
        NativeTests.check(isMissing(LedgerStore.loadResult()), "P0-1/无文件 — loadResult 为 missing")
        let fresh = AppState(settings: QuoteSettings())
        NativeTests.check(fresh.ledger.trades.isEmpty && fresh.loadFailure == nil, "P0-1/无文件 — 按空账本启动且无读取失败")
        fresh.setQuote(symbol: "AAA", price: 10, date: "2026-01-05")
        NativeTests.check(FileManager.default.fileExists(atPath: file.path), "P0-1/无文件 — 首次写入正常落盘")

        // 有效文件：正常读取。
        var good = Ledger()
        good.trades = [trade(0, .buy, "10", "2026-01-05")]
        try LedgerStore.save(good)
        NativeTests.check(isLoaded(LedgerStore.loadResult()), "P0-1/有效文件 — loadResult 为 loaded")
        let reopened = AppState(settings: QuoteSettings())
        NativeTests.check(reopened.ledger.trades.count == 1 && reopened.loadFailure == nil, "P0-1/有效文件 — 正常读取且无读取失败")

        // 损坏文件：必须明确失败，且原文件一字不动。
        let truncated = Data(#"{"format":2,"trades":[{"symbol":"AAA""#.utf8)
        try truncated.write(to: file)
        NativeTests.check(isFailed(LedgerStore.loadResult()), "P0-1/损坏文件 — loadResult 为 failed")
        let broken = AppState(settings: QuoteSettings())
        NativeTests.check(broken.loadFailure != nil, "P0-1/损坏文件 — 暴露读取失败状态")
        NativeTests.check(broken.ledger.trades.isEmpty, "P0-1/损坏文件 — 界面回退为空账本（只读）")

        let before = try Data(contentsOf: file)
        let candidate = trade(0, .buy, "1", "2026-01-05")
        NativeTests.check(!broken.saveTrade(candidate), "P0-1/损坏文件 — 手动交易保存被拒绝")
        broken.setQuote(symbol: "AAA", price: 10, date: "2026-01-05")
        NativeTests.check(!broken.commit(ledger([candidate])), "P0-1/损坏文件 — commit 被拒绝")
        let after = try Data(contentsOf: file)
        NativeTests.check(after == before, "P0-1/损坏文件 — 原文件字节未改变")

        // 用户明确选择用备份恢复：唯一被放行的写入路径。
        var backup = Ledger()
        backup.trades = [trade(0, .buy, "3", "2026-01-05"), trade(1, .sell, "1", "2026-01-06")]
        NativeTests.check(broken.replaceFromBackup(backup), "P0-1/恢复 — 备份恢复被放行")
        NativeTests.check(broken.loadFailure == nil, "P0-1/恢复 — 解除写入保护")
        let recovered = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        NativeTests.check(recovered.trades.count == 2, "P0-1/恢复 — 备份内容已落盘")
    }

    // MARK: - P0-2

    private static func manualTradesRespectThePositionInvariant() {
        // 合法的部分卖出。
        let partial = state([trade(0, .buy, "100", "2026-01-05")])
        NativeTests.check(partial.saveTrade(trade(1, .sell, "50", "2026-01-06")), "P0-2/部分卖出 — 允许")
        NativeTests.check(partial.ledger.trades.count == 2, "P0-2/部分卖出 — 已写入账本")

        // 恰好卖完。
        let exact = state([trade(0, .buy, "100", "2026-01-05")])
        NativeTests.check(exact.saveTrade(trade(1, .sell, "100", "2026-01-06")), "P0-2/全部卖出 — 允许")

        // 超卖 1 股必须被拒绝，且账本一字不动。
        let oversell = state([trade(0, .buy, "100", "2026-01-05")])
        NativeTests.check(!oversell.saveTrade(trade(1, .sell, "101", "2026-01-06")), "P0-2/超卖 — 被拒绝")
        NativeTests.check(oversell.ledger.trades.count == 1, "P0-2/超卖 — 账本未改变")
        NativeTests.check(oversell.errorMessage != nil, "P0-2/超卖 — 给出可读失败原因")

        // 没有任何持仓时卖出。
        let naked = state([])
        NativeTests.check(!naked.saveTrade(trade(0, .sell, "1", "2026-01-06")), "P0-2/无持仓卖出 — 被拒绝")
        NativeTests.check(naked.ledger.trades.isEmpty, "P0-2/无持仓卖出 — 账本未改变")

        // 删除被后续卖出依赖的买入。
        let buyID = UUID()
        var buy = trade(0, .buy, "100", "2026-01-05"); buy.id = buyID
        let deletion = state([buy, trade(1, .sell, "80", "2026-01-06")])
        NativeTests.check(!deletion.deleteTrade(buyID), "P0-2/删除关键买入 — 被拒绝")
        NativeTests.check(deletion.ledger.trades.count == 2, "P0-2/删除关键买入 — 账本未改变")

        // 时序陷阱：最终数量看起来合法，但中间时点会变成负持仓。
        let firstID = UUID()
        var jan1 = trade(0, .buy, "100", "2026-01-01"); jan1.id = firstID
        let chronological = state([jan1, trade(1, .sell, "100", "2026-01-02"), trade(2, .buy, "100", "2026-01-03")])
        NativeTests.check(!chronological.deleteTrade(firstID),
                          "P0-2/时序删除 — 最终 100 股仍合法，但 01-02 会超卖，必须拒绝")
        NativeTests.check(chronological.ledger.trades.count == 3, "P0-2/时序删除 — 账本未改变")
        // 同一账本里删掉不影响任何时点的买入仍然允许，证明守卫不是「一律拒绝」。
        NativeTests.check(chronological.deleteTrade(chronological.ledger.trades[2].id),
                          "P0-2/时序删除 — 不影响任何时点的删除仍然允许")

        // 把已被卖出的买入改小，同样会让历史时点悬空。
        let shrinkID = UUID()
        var shrink = trade(0, .buy, "100", "2026-01-05"); shrink.id = shrinkID
        let edit = state([shrink, trade(1, .sell, "80", "2026-01-06")])
        var reduced = edit.ledger.trades[0]
        reduced.quantity = decimal("50")
        NativeTests.check(!edit.saveTrade(reduced), "P0-2/改小买入 — 已卖出部分悬空，被拒绝")
        NativeTests.check(edit.ledger.trades[0].quantity == decimal("100"), "P0-2/改小买入 — 账本未改变")

        // 修复前可能已经写入过超卖账本：不能因此把用户永久锁死，后续修正仍要放行。
        let legacy = state([trade(0, .sell, "5", "2026-01-02")])
        NativeTests.check(legacy.saveTrade(trade(1, .buy, "10", "2026-01-01")),
                          "P0-2/历史脏数据 — 不阻塞用户修正账本")
    }

    // MARK: - 入口

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stock-ledger-safety-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ledger-v2.json")
        LedgerStore.fileURLOverride = file
        defer {
            LedgerStore.fileURLOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try unreadableLedgerIsNotAnEmptyLedger(file)
        manualTradesRespectThePositionInvariant()
    }
}
