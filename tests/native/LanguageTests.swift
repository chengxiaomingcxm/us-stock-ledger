import Foundation

/// P0（英文界面 / UX 审计）回归测试，对应 `docs/ENGLISH_UI_AUDIT.md` 的三条根因：
///
/// 1. 派生缓存固化了「求值当时」的本地化字符串（`Engine.displayedReturn` → `LedgerDerived.displayReturn`），
///    而缓存的失效键只有账本与历史、**不含语言** → 切语言必须让缓存重算，只重绘视图修不好。
/// 2. 产品文案被写进**数据**（结单导入的 note），或用插值把值拼进查表键（`"成交 \(date)"` 永远匹配不上词典）
///    → 展示层按结构化字段重建，**不改动已持久化的值**。
/// 3. 界面日期跟随设备区域 → 由 `RootView` 注入 `.environment(\.locale, …)` 修正（视图层，原生测试覆盖不到）。
///
/// 本机（Windows）没有 Swift 工具链，这些断言由 CI 的 `scripts/test-native.sh` 执行。
/// 注意：本文件不在 Xcode 工程里（测试不进 App），只需登记 `NativeTests.main()` 的调用
/// 与 `scripts/test-native.sh` 的 swiftc 文件列表；漏登记任一处都会得到假绿或 `cannot find 'X' in scope`。
@MainActor
enum LanguageTests {
    static func run() async throws {
        let savedLanguage = L10n.current
        let savedDefaults = UserDefaults.standard.string(forKey: "app.language")
        defer {
            L10n.current = savedLanguage
            UserDefaults.standard.set(savedDefaults, forKey: "app.language")
        }
        dictionary()
        placeholders()
        formatting()
        generatedNotes()
        try await languageSwitchRebuildsCache()
    }

    // MARK: - 词典本身

    /// 根因 2 的前置条件：词典必须完整。缺键时 `tr` 会**静默回退中文**（不空白、不崩溃），
    /// 所以只有逐条断言才能发现漏译 —— 这正是审计里「看起来都翻译了」的假象来源。
    private static func dictionary() {
        let en = L10n.en
        NativeTests.check(en.count >= 500, "英文词典条目数应 >= 500，实际 \(en.count)")

        var blank: [String] = []
        var untranslated: [String] = []
        var residual: [String] = []
        for (key, value) in en {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blank.append(key) }
            // "CSV" 这类缩写在两种语言下本来就一样，是唯一允许键值相同的例外。
            if value == key, key != "CSV" { untranslated.append(key) }
            if hasCJK(value) { residual.append(key) }
        }
        NativeTests.check(blank.isEmpty, "英文值不能为空：\(blank.prefix(5))")
        NativeTests.check(untranslated.isEmpty, "英文值不能与中文键相同（漏译）：\(untranslated.prefix(5))")
        NativeTests.check(residual.isEmpty, "英文值不得残留中日韩字符或全角标点：\(residual.prefix(5))")
    }

    // MARK: - 占位符

    /// 整句带占位符的翻译：把值拼进键里（`"成交 \(date)"`）永远匹配不上词典，
    /// 必须走 `{}` 占位符；未收录时回退中文原文，不空白、不崩溃。
    private static func placeholders() {
        L10n.current = .zhHans
        let chinese = L10n.tr("{}：{}", "AAPL", "缺少当日报价")
        NativeTests.check(chinese == "AAPL：缺少当日报价", "中文模式按顺序替换占位符：\(chinese)")

        L10n.current = .en
        let english = L10n.tr("{}：{}", "AAPL", "缺少当日报价")
        NativeTests.check(english.hasPrefix("AAPL"), "英文模式保留参数内容：\(english)")
        NativeTests.check(!english.contains("{}"), "英文模式不得留下未替换的占位符：\(english)")
        NativeTests.check(L10n.tr("这条文案没有收录") == "这条文案没有收录", "漏译时回退中文原文而不是空串")
    }

    // MARK: - 空值占位符

    /// 缺失一律显示 "—"：英文界面里 `$0.00` 与「没有数据」是两种含义，混在一起会读成真值。
    private static func formatting() {
        NativeTests.check(Fmt.money(nil) == "—", "空金额显示占位符而不是 $0.00")
        NativeTests.check(Fmt.signedMoney(nil) == "—", "空带符号金额显示占位符")
        NativeTests.check(Fmt.percent(nil) == "—", "空百分比显示占位符")
        NativeTests.check(Fmt.signedMoney(Decimal(string: "1234.5")!) == "+$1,234.50", "正数带 + 号")
        NativeTests.check(Fmt.signedMoney(Decimal(string: "-1234.5")!) == "−$1,234.50", "负数用减号（U+2212）")
        NativeTests.check(Fmt.signedMoney(0) == "$0.00", "零不带符号")
        NativeTests.check(Fmt.percent(Decimal(string: "0.0125")!) == "+1.25%", "正百分比带 + 号")
        NativeTests.check(Fmt.percent(Decimal(string: "-0.0125")!) == "−1.25%", "负百分比只有一个减号")
    }

    // MARK: - 结单导入写进 note 的系统文案

    /// 根因 2：结单导入把系统说明写进了 `note`（会被持久化）。
    /// 展示层按结构化字段（`source` + `settlementDate` / `tax`）重建为当前语言，
    /// **不改动已持久化的值**，也不做数据迁移；用户自己改过的 note 必须原样显示。
    private static func generatedNotes() {
        let settlement = "2026-01-05"
        var imported = Trade(sequence: 1, symbol: "AAPL", side: .buy, date: "2026-01-02",
                             quantity: 1, price: 10, fee: 0)
        imported.source = "hsbc-statement"
        imported.settlementDate = settlement
        imported.note = "汇丰月结单；交收日 \(settlement)"

        L10n.current = .en
        let shown = Fmt.tradeNote(imported)
        NativeTests.check(!hasCJK(shown), "结单导入的交易说明按当前语言重建：\(shown)")
        NativeTests.check(shown.contains(settlement), "重建时保留交收日：\(shown)")

        // 新版导入不再把系统文案写进 note（写入侧由 SafetyTests.systemTextNeverEntersNote 守）：
        // note 为空时仍必须生成同一句。
        var noNote = imported
        noNote.note = ""
        NativeTests.check(Fmt.tradeNote(noNote) == shown, "note 为空时同样生成说明（新版导入的形状）")

        L10n.current = .zhHans
        NativeTests.check(Fmt.tradeNote(imported) == imported.note, "中文下重建结果与原说明一致")

        // 用户改过的备注：模板对不上，原样显示，绝不能被系统文案覆盖。
        var edited = imported
        edited.note = "我自己的备注"
        NativeTests.check(Fmt.tradeNote(edited) == "我自己的备注", "用户改过的 note 原样显示")
        // 非结单导入的行不动。
        var manual = imported
        manual.source = "manual"
        NativeTests.check(Fmt.tradeNote(manual) == imported.note, "手动录入的行不重建")
        // 有交收日但说明不是系统模板（老版本格式）→ 同样原样显示。
        var oldFormat = imported
        oldFormat.note = "别的说明"
        NativeTests.check(Fmt.tradeNote(oldFormat) == "别的说明", "说明与模板不一致时不重建")

        let net = CashRecord(sequence: 1, date: "2026-01-08", kind: .dividend, amount: Decimal(string: "0.88")!,
                             tax: nil, symbol: "AAPL", note: "汇丰 PAID BENEFITS 净额；税前金额与预扣税未披露",
                             source: "hsbc-statement-net")
        L10n.current = .en
        let cashShown = Fmt.cashNote(net)
        NativeTests.check(!hasCJK(cashShown), "净额分红的说明按当前语言重建：\(cashShown)")

        // 披露了预扣税的记录不是「净额且税额未知」，保留原说明。
        var reported = net
        reported.tax = Decimal(string: "0.12")!
        NativeTests.check(Fmt.cashNote(reported) == reported.note, "披露了预扣税的记录不重建")
        // 新版导入的净额分红 note 是空的，同样必须生成说明。
        var noNoteCash = net
        noNoteCash.note = ""
        NativeTests.check(Fmt.cashNote(noNoteCash) == Fmt.cashNote(net), "note 为空时同样生成净额说明")
        // 人工录入的分红不动。
        var manualCash = net
        manualCash.source = "manual"
        NativeTests.check(Fmt.cashNote(manualCash) == manualCash.note, "手动录入的现金记录不重建")
    }

    // MARK: - 根因 1：切语言必须让派生缓存失效

    /// `LedgerDerived` 里存着**求值当时**就本地化好的标题与说明；缓存的失效键只有账本与历史，
    /// 不含语言。只重绘视图修不好，必须让缓存重算，否则界面停在旧语言。
    private static func languageSwitchRebuildsCache() async throws {
        // 锚点取美东正午：`MarketClock.date` 按美东取日期，用 UTC 零点会退到前一天。
        let anchor = MarketClock.day("2026-09-18")!.addingTimeInterval(12 * 3600)
        // 显式传账本与 persist 空实现：全程不碰磁盘，也不读钥匙串。
        let state = AppState(ledger: DemoData.ledger(now: anchor), settings: QuoteSettings(), persist: { _ in })

        state.setLanguage(.zhHans)
        try await settle(state)
        let chineseTitle = state.displayReturn.title

        state.setLanguage(.en)
        try await settle(state)
        let englishTitle = state.displayReturn.title

        NativeTests.check(hasCJK(chineseTitle), "中文下派生标题是中文：\(chineseTitle)")
        NativeTests.check(!hasCJK(englishTitle), "切到英文后派生标题必须重建为英文（根因 1）：\(englishTitle)")
        NativeTests.check(chineseTitle != englishTitle, "语言切换必须让派生缓存失效")
    }

    /// 派生计算在后台任务里跑；`rebuilding` 由同一次计算在结束时置回 false，
    /// 且过期的计算会被 generation 守卫丢弃，所以轮询它就能等到结果落定。
    private static func settle(_ state: AppState) async throws {
        for _ in 0 ..< 200 {
            if !state.rebuilding { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        NativeTests.check(false, "派生计算未在 4 秒内结束")
    }

    /// 汉字、中文标点区、全角/半角形式区：英文界面里出现任何一类都算漏译。
    private static func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00 ... 0x9FFF).contains(scalar.value)
                || (0x3000 ... 0x303F).contains(scalar.value)
                || (0xFF00 ... 0xFFEF).contains(scalar.value)
        }
    }
}
