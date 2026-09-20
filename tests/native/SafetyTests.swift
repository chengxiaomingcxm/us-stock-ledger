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
        // 解码用 try? + 断言：测试失败要报 FAIL，不应该把测试进程抛崩。
        let recovered = try? JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        NativeTests.check(recovered?.trades.count == 2, "P0-1/恢复 — 备份内容已落盘")
    }

    /// P0-1 回归（续）：备份写盘失败时，写保护、内存账本与原文件都必须保持不变；
    /// 之后所有普通写入路径（交易、现金、报价、CSV 导入、清空、示例）仍必须被阻止。
    private static func restoreFailureKeepsTheProtection(_ file: URL) throws {
        try Data(#"{"format":2,"trades":[{"symbol":"AAA""#.utf8).write(to: file)
        // 注入的 persist 只在「磁盘故障」时抛错；正常分支必须真的写盘，
        // 否则恢复后的落盘断言就失去意义（测试自己制造的假阳性/假阴性）。
        var failWrites = false
        let broken = AppState(settings: QuoteSettings(), persist: { next in
            if failWrites { throw LedgerError.message("disk full") }
            try LedgerStore.save(next)
        })
        NativeTests.check(broken.loadFailure != nil, "P0-1/恢复失败 — 先确认处于读取失败状态")
        let before = try Data(contentsOf: file)

        var backup = Ledger()
        backup.trades = [trade(0, .buy, "3", "2026-01-05")]
        backup.cash = [CashRecord(sequence: 0, date: "2026-01-06", kind: .deposit, amount: decimal("100"),
                                  tax: nil, symbol: nil, note: "")]

        failWrites = true
        NativeTests.check(!broken.replaceFromBackup(backup), "P0-1/恢复失败 — replaceFromBackup 返回 false")
        NativeTests.check(broken.loadFailure != nil, "P0-1/恢复失败 — 写保护仍然存在")
        NativeTests.check(broken.errorMessage != nil, "P0-1/恢复失败 — 给出可读错误信息")
        NativeTests.check(broken.ledger.trades.isEmpty && broken.ledger.cash.isEmpty, "P0-1/恢复失败 — 内存账本未改变")
        let after = try Data(contentsOf: file)
        NativeTests.check(after == before, "P0-1/恢复失败 — 原文件字节未改变")

        // 之后所有普通写入必须仍然被阻止。
        NativeTests.check(!broken.commit(backup), "P0-1/恢复失败 — commit 仍被拒绝")
        NativeTests.check(!broken.saveTrade(trade(0, .buy, "1", "2026-01-07")), "P0-1/恢复失败 — saveTrade 仍被拒绝")
        broken.setQuote(symbol: "AAA", price: 10, date: "2026-01-08")
        broken.saveCash(CashRecord(sequence: 0, date: "2026-01-08", kind: .deposit, amount: decimal("5"),
                                   tax: nil, symbol: nil, note: ""))
        broken.setOpening(CashOpening(amount: decimal("1"), date: "2026-01-01", note: ""))
        NativeTests.check(!broken.replace(with: backup), "P0-1/恢复失败 — CSV 导入路径仍被拒绝")
        NativeTests.check(broken.errorMessage != nil, "P0-1/恢复失败 — 导入失败也留下可展示的原因")
        broken.clearAll()
        // 示例模式必须自己就不落盘：它绕过了 loadFailure 保护（commit 的守卫为 demo || loadFailure == nil），
        // 所以这里只靠「写入不落盘」这一条来保住原文件。
        broken.enterDemo()
        broken.exitDemo()
        let stillIntact = try Data(contentsOf: file)
        NativeTests.check(stillIntact == before, "P0-1/恢复失败 — 交易/现金/报价/导入/清空/示例均未写入")

        // 只有真正写盘成功后才解除保护并恢复普通保存。
        failWrites = false
        NativeTests.check(broken.replaceFromBackup(backup), "P0-1/恢复失败 — 写盘成功后允许恢复")
        NativeTests.check(broken.loadFailure == nil, "P0-1/恢复失败 — 写盘成功后解除保护")
        NativeTests.check(broken.ledger.trades.count == 1, "P0-1/恢复失败 — 内存账本已更新")
        let recovered = try? JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        NativeTests.check(recovered?.trades.count == 1, "P0-1/恢复失败 — 备份内容已落盘")
        NativeTests.check(broken.saveTrade(trade(1, .buy, "1", "2026-01-09")), "P0-1/恢复失败 — 普通保存已恢复")
    }

    /// 修复前可能已经写入超卖账本；守卫必须继续阻止「新增伤害」，同时允许「修复」。
    /// 脏账本：AAPL 在 2026-01-02 先卖 10 股（当时持仓 0 → 超卖 10），2026-01-03 才买入 10 股。
    /// 违规键 = AAPL|2026-01-02|0，超额 10 股。
    private static func legacyOversellStillGuardsNewDamage() {
        let sellID = UUID()
        func dirty() -> Ledger {
            var sell = trade(0, .sell, "10", "2026-01-02", symbol: "AAPL")
            sell.id = sellID
            return ledger([sell, trade(1, .buy, "10", "2026-01-03", symbol: "AAPL")])
        }
        func state(_ value: Ledger) -> AppState {
            AppState(ledger: value, settings: QuoteSettings(), persist: { _ in })
        }

        // Scenario 1：删掉违规卖出完全修复 → 允许。
        let repairing = state(dirty())
        NativeTests.check(repairing.deleteTrade(sellID), "已有超卖/S1 — 删除违规卖出被允许（修复）")
        NativeTests.check(repairing.ledger.trades.count == 1, "已有超卖/S1 — 修复已写入")

        // Scenario 4：新增与违规无关的合法买入 → 允许（AAPL 与 MSFT 互不串联）。
        let unrelated = state(dirty())
        NativeTests.check(unrelated.saveTrade(trade(2, .buy, "10", "2026-01-04", symbol: "MSFT")),
                          "已有超卖/S4 — 无关股票的合法买入被允许")
        NativeTests.check(Engine.oversells(unrelated.ledger).count == 1, "已有超卖/S4 — MSFT 没引入新违规")

        // Scenario 2：新增另一只股票的超卖 → 拒绝。
        let another = state(dirty())
        NativeTests.check(another.saveTrade(trade(2, .buy, "10", "2026-01-04", symbol: "NVDA")),
                          "已有超卖/S2 — 新股票的合法买入被允许")
        let beforeS2 = another.ledger.trades.count
        NativeTests.check(!another.saveTrade(trade(3, .sell, "20", "2026-01-05", symbol: "NVDA")),
                          "已有超卖/S2 — 新增另一只股票的超卖被拒绝")
        NativeTests.check(another.errorMessage != nil, "已有超卖/S2 — 留下可展示的失败原因")
        NativeTests.check(another.ledger.trades.count == beforeS2, "已有超卖/S2 — 账本未改变")

        // Scenario 3：把已有超卖从 10 股扩大到 50 股 → 拒绝。
        let growing = state(dirty())
        var worse = dirty().trades[0]
        worse.quantity = decimal("50")
        NativeTests.check(!growing.saveTrade(worse), "已有超卖/S3 — 扩大已有超卖被拒绝")
        NativeTests.check(growing.errorMessage != nil, "已有超卖/S3 — 留下可展示的失败原因")
        NativeTests.check(growing.ledger.trades[0].quantity == decimal("10"), "已有超卖/S3 — 账本未改变")

        // 把违规提前到更早的历史时点 → 拒绝。
        let earlier = state(dirty())
        var moved = dirty().trades[0]
        moved.date = "2026-01-01"
        NativeTests.check(!earlier.saveTrade(moved), "已有超卖 — 把违规提前到更早时点被拒绝")

        // 补一笔更早的买入，把同一时点的超额从 10 股降到 6 股 → 允许（这是在修复）。
        let shrinking = state(dirty())
        NativeTests.check(shrinking.saveTrade(trade(2, .buy, "4", "2026-01-01", symbol: "AAPL")),
                          "已有超卖 — 补更早买入缩小超额被允许")
        NativeTests.check(Engine.oversells(shrinking.ledger).first?.quantity == decimal("6"),
                          "已有超卖 — 缩小后同一时点超额为 6 股")
    }

    /// 同日 case：买后卖合法；卖后买在同一时点已经超卖。
    private static func sameDayOrderIsEnforced() {
        let buyFirst = state([])
        NativeTests.check(buyFirst.saveTrade(trade(0, .buy, "10", "2026-02-02", symbol: "TSLA")), "同日/买后卖 — 买入")
        NativeTests.check(buyFirst.saveTrade(trade(1, .sell, "10", "2026-02-02", symbol: "TSLA")), "同日/买后卖 — 同日卖出合法")

        let sellFirst = state([])
        NativeTests.check(!sellFirst.saveTrade(trade(0, .sell, "10", "2026-02-02", symbol: "TSLA")),
                          "同日/卖后买 — 同日先卖被识别为历史超卖")
        NativeTests.check(sellFirst.ledger.trades.isEmpty, "同日/卖后买 — 账本未改变")
    }

    /// 排序：同日 sequence 重复的备份不能靠不稳定的 sort 决定 Buy/Sell 顺序。
    private static func duplicateSameDaySequenceIsDeterministic() {
        var duplicated = Ledger()
        var buy = Trade(sequence: 0, symbol: "TSLA", side: .buy, date: "2026-03-02",
                        quantity: decimal("10"), price: 1, fee: 0, note: "buy")
        var sell = Trade(sequence: 0, symbol: "TSLA", side: .sell, date: "2026-03-02",
                         quantity: decimal("10"), price: 1, fee: 0, note: "sell")
        buy.id = UUID(); sell.id = UUID()

        duplicated.trades = [sell, buy]
        NativeTests.check(duplicated.orderedTrades.map(\.note) == ["sell", "buy"],
                          "排序/同日重复 sequence — 平手时保持数组顺序")
        NativeTests.check(Engine.oversells(duplicated).count == 1, "排序/同日重复 sequence — 先卖必为超卖")

        duplicated.trades = [buy, sell]
        NativeTests.check(duplicated.orderedTrades.map(\.note) == ["buy", "sell"],
                          "排序/同日重复 sequence — 交换数组顺序后语义也跟着确定")
        NativeTests.check(Engine.oversells(duplicated).isEmpty, "排序/同日重复 sequence — 买后卖无违规")

        // 30 笔完全平手：旧实现（直接 sort）在大数组上会走非稳定分支，顺序会脱离数组顺序。
        var ties = Ledger()
        ties.trades = (0..<30).map { index in
            Trade(sequence: 0, symbol: "AAA", side: .buy, date: "2026-04-01",
                  quantity: Decimal(index + 1), price: 1, fee: 0, note: "row\(index)")
        }
        NativeTests.check(ties.orderedTrades.map(\.note) == (0..<30).map { "row\($0)" },
                          "排序/同日重复 sequence — 30 笔平手时仍严格保持数组顺序")

        // sequence 不同时由 sequence 决定，与数组顺序无关。
        var bySequence = Ledger()
        var first = Trade(sequence: 0, symbol: "TSLA", side: .buy, date: "2026-03-03", quantity: 1, price: 1, fee: 0, note: "first")
        var second = Trade(sequence: 1, symbol: "TSLA", side: .sell, date: "2026-03-03", quantity: 1, price: 1, fee: 0, note: "second")
        first.id = UUID(); second.id = UUID()
        bySequence.trades = [second, first]
        NativeTests.check(bySequence.orderedTrades.map(\.note) == ["first", "second"],
                          "排序/sequence 不同 — 由 sequence 决定，与数组顺序无关")
    }

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
        // 原生界面没有自动化视图测试，因此把「失败必须留下可展示的原因」当成状态层契约来固定：
        // 界面只能靠 errorMessage 告知用户，它一旦为空就是静默失败。
        NativeTests.check(deletion.errorMessage != nil, "P0-2/删除关键买入 — 留下可展示的失败原因")

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

    // MARK: - 写入侧（note 归属）

    /// note 只装用户/来源数据；系统说明一律由结构化字段在展示层生成。
    /// 这里守的是「系统文案绝不得覆盖用户写的东西」，所以它属于数据安全。
    private static func systemTextNeverEntersNote() {
        var imported = Trade(sequence: 1, symbol: "AAA", side: .buy, date: "2026-01-05",
                             quantity: 1, price: 10, fee: 0)
        imported.source = "hsbc-statement"
        imported.settlementDate = "2026-01-07"

        L10n.current = .en
        let shown = Fmt.tradeNote(imported)
        NativeTests.check(imported.note.isEmpty, "写入侧 — 导入不把系统说明写进 note")
        NativeTests.check(!hasCJKText(shown), "写入侧 — 说明按当前语言生成：\(shown)")
        NativeTests.check(shown.contains("2026-01-07"), "写入侧 — 生成时保留交收日：\(shown)")

        L10n.current = .zhHans
        NativeTests.check(Fmt.tradeNote(imported) == "汇丰月结单；交收日 2026-01-07", "写入侧 — 中文下生成同样的说明")

        // 1.0 之前把同一句系统说明写进了 note：那不是兼容目标，原样显示、不重写，
        // 但「系统文案不得覆盖已持久化的值」这条底线依旧成立。
        var legacy = imported
        legacy.note = "汇丰月结单；交收日 2026-01-07"
        L10n.current = .en
        NativeTests.check(Fmt.tradeNote(legacy) == "汇丰月结单；交收日 2026-01-07", "写入侧 — 1.0 前写进 note 的说明原样显示")
        L10n.current = .zhHans

        // 用户/来源数据绝不能被系统文案盖掉。
        var edited = imported
        edited.note = "我自己的备注"
        NativeTests.check(Fmt.tradeNote(edited) == "我自己的备注", "写入侧 — 用户写的 note 原样显示")
        var manual = imported
        manual.source = "manual"
        NativeTests.check(Fmt.tradeNote(manual) == "", "写入侧 — 手动录入的行不重建")
        var oldFormat = imported
        oldFormat.note = "别的说明"
        NativeTests.check(Fmt.tradeNote(oldFormat) == "别的说明", "写入侧 — 说明与模板不一致时不重建")

        let net = CashRecord(sequence: 1, date: "2026-01-08", kind: .dividend, amount: decimal("0.88"),
                             tax: nil, symbol: "AAA", source: "hsbc-statement-net")
        L10n.current = .en
        let cashShown = Fmt.cashNote(net)
        NativeTests.check(net.note.isEmpty, "写入侧 — 净额分红的说明也不写进 note")
        NativeTests.check(!hasCJKText(cashShown), "写入侧 — 净额说明按当前语言生成：\(cashShown)")

        var legacyCash = net
        legacyCash.note = "汇丰 PAID BENEFITS 净额；税前金额与预扣税未披露"
        NativeTests.check(Fmt.cashNote(legacyCash) == legacyCash.note, "写入侧 — 1.0 前写进 note 的净额说明原样显示")
        var userCash = net
        userCash.note = "自己的说明"
        NativeTests.check(Fmt.cashNote(userCash) == "自己的说明", "写入侧 — 用户写的说明不被覆盖")
        var reported = net
        reported.tax = decimal("0.12")
        reported.note = "税额已披露"
        NativeTests.check(Fmt.cashNote(reported) == "税额已披露", "写入侧 — 披露了预扣税就不生成净额说明")
        L10n.current = .zhHans
    }

    /// 英文界面里不应该出现中日韩字符或全角标点。
    private static func hasCJKText(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x4E00 ... 0x9FFF).contains($0.value) || (0x3000 ... 0x303F).contains($0.value)
                || (0xFF00 ... 0xFFEF).contains($0.value)
        }
    }

    // MARK: - 格式边界

    /// 比本版本更新的格式必须被**拒绝**，而不是被「成功解码」成丢字段的账本。
    /// 旧行为会把它读成字段缺失的账本，而下一次原子写入就覆盖了原文件 = 静默数据丢失
    /// （`docs/PHASE_0_5_REVIEW.md` P2-1 记的欠账）。
    private static func newerFormatIsRefusedNotSilentlyDowngraded(_ file: URL) throws {
        // 1) 本版本的正常文件照常读取。
        try LedgerStore.save(ledger([trade(0, .buy, "1", "2026-01-05")]))
        NativeTests.check(isLoaded(LedgerStore.loadResult()), "格式边界 — 当前格式正常读取")

        // 2) 声明更高的格式：必须读不出来，且原文件一字不动。
        let future = #"{"format":\#(Ledger.currentFormat + 1),"trades":[],"quotes":[],"cash":[],"history":{}}"#
        try Data(future.utf8).write(to: file)
        NativeTests.check(isFailed(LedgerStore.loadResult()), "格式边界 — 更高格式被拒绝")
        let protected = AppState(settings: QuoteSettings())
        NativeTests.check(protected.loadFailure != nil, "格式边界 — 进入写保护")
        let before = try Data(contentsOf: file)
        NativeTests.check(!protected.saveTrade(trade(0, .buy, "1", "2026-01-05")), "格式边界 — 写保护阻止保存")
        let after = try Data(contentsOf: file)
        NativeTests.check(after == before, "格式边界 — 原文件未被覆盖")

        // 3) 横幅给出「更新 App」而不是「从备份恢复」——后者会用旧备份盖掉更新的账本。
        NativeTests.check(LedgerStore.bannerText(for: protected.loadFailure ?? "") != L10n.tr(LedgerStore.unreadableMessage),
                          "格式边界 — 横幅给的是正确处置")

        // 4) 恢复通道同样受约束：更高格式的备份不得被读进来。
        NativeTests.check((try? LedgerStore.decode(Data(future.utf8))) == nil, "格式边界 — 备份解码也被拒绝")

        // 5) 更低代际的文件仍按本版本读取——守卫只拒绝**更新**的格式，不拒绝更老的。
        //    JSON 必须写全所有非 Optional 键：`Ledger` 用合成 Decodable，
        //    属性有默认值也**不会**被用来容忍缺键（只有 Optional 才算可选），
        //    所以缺键的文件根本解不出来 —— 这是既有行为，也正是下面第 6 条要断言的。
        let older = #"{"format":1,"trades":[],"quotes":[],"cash":[],"history":{"sessions":[],"closes":[],"splits":[]}}"#
        try Data(older.utf8).write(to: file)
        NativeTests.check(isLoaded(LedgerStore.loadResult()), "格式边界 — 更低代际的文件仍可读")

        // 6) 缺 format 键的文件读不出来 → 进入写保护（保护原文件）。这不是守卫要覆盖的情形，
        //    而是「文件被改坏/截断」的既有处置，一并钉住以免将来误以为它能当旧文件读。
        let partial = #"{"trades":[],"quotes":[],"cash":[],"history":{"sessions":[],"closes":[],"splits":[]}}"#
        try Data(partial.utf8).write(to: file)
        NativeTests.check(isFailed(LedgerStore.loadResult()), "格式边界 — 缺 format 键的文件进入写保护")
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
        try restoreFailureKeepsTheProtection(file)
        try newerFormatIsRefusedNotSilentlyDowngraded(file)
        systemTextNeverEntersNote()
        manualTradesRespectThePositionInvariant()
        legacyOversellStillGuardsNewDamage()
        sameDayOrderIsEnforced()
        duplicateSameDaySequenceIsDeterministic()
    }
}
