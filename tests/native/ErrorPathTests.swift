import Foundation

/// Phase 3（任务书 §8）的契约回归：**用户看到的是可读文案，系统异常原文只进诊断日志**，
/// 并且失败时内存账本与磁盘都不被改动。这几条正是 Phase 3 改动的直接守卫。
///
/// 注意：本文件不在 Xcode 工程里，但**必须**加进 `scripts/test-native.sh` 的编译列表。
@MainActor
enum ErrorPathTests {
    /// 一个没有本地化描述的普通错误，用来模拟文件系统 / 编码器抛出的系统异常。
    private struct Boom: Error {}

    private static func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US"))!
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stock-ledger-error-path-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent(Diagnostics.fileName)
        let outerLog = Diagnostics.fileURLOverride
        Diagnostics.fileURLOverride = log
        defer {
            Diagnostics.fileURLOverride = outerLog
            try? FileManager.default.removeItem(at: directory)
        }
        try? FileManager.default.removeItem(at: log)

        var ledger = Ledger()
        ledger.trades = [Trade(sequence: 0, symbol: "AAA", side: .buy, date: "2026-01-02",
                               quantity: 1, price: dec("10"), fee: 0)]
        let state = AppState(ledger: ledger, settings: QuoteSettings(), persist: { _ in throw Boom() })

        let added = Trade(sequence: 1, symbol: "BBB", side: .buy, date: "2026-01-03",
                          quantity: 1, price: dec("10"), fee: 0)
        NativeTests.check(!state.saveTrade(added), "写盘失败：保存返回 false")
        NativeTests.check(state.ledger.trades.count == 1, "写盘失败：内存账本不变")
        NativeTests.check(state.errorMessage == L10n.tr("账本保存失败，磁盘上的原文件没有被改动；请重试。"),
                          "写盘失败：给的是可读文案，而不是系统异常原文")

        let text = Diagnostics.text()
        NativeTests.check(text.contains("SAVE"), "写盘失败：技术原文进了诊断日志（SAVE）")
        NativeTests.check(text.contains("Boom"), "写盘失败：日志里带异常类型，便于定位")

        // 示例模式与读取失败保护的文案契约由 SafetyTests / DemoModeTests 覆盖，这里不重复。
    }
}
