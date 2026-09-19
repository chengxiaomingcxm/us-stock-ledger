import SwiftUI
import UIKit

// Simulator-only harness: render each main screen in English (L10n.current = .en)
// with the demo ledger, one screen per launch, so the CI can capture app screenshots.
@main
final class ScreenshotsApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// 截图用的虚构券商导出：5 行合法 + 1 行负数数量。表头沿用仓库自带的
    /// `CsvImport`/`csvTemplate` 口径；全部为买入，因为它是与示例账本叠加后
    /// 做整批校验的，卖出会在演示账本上引入超卖风险。
    /// 只用于展示映射与校验界面，永远不会真的写进账本。
    private static let importCSV = """
    Date,Symbol,Side,Quantity,Price,Fee,TradeID,Note
    2026-09-14,MSFT,BUY,4,498.20,1.00,D-1041,Weekly top-up
    2026-09-15,AAPL,BUY,3,226.40,1.00,D-1042,Add to position
    2026-09-15,NVDA,BUY,2,171.85,1.00,D-1043,
    2026-09-16,VOO,BUY,1,575.10,1.00,D-1044,Dividend reinvestment
    2026-09-17,SGOV,BUY,12,103.05,1.00,D-1045,Cash sweep
    2026-09-17,TSLA,BUY,-5,254.60,1.00,D-1046,Quantity column cannot be negative
    """

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // NSLog (not print) so the CI can read these from the unified log with
        // `log show`; print output is block-buffered and lost on terminate.
        NSLog("HARNESS-START")
        let screen = ProcessInfo.processInfo.arguments.dropFirst().first ?? "holdings"
        // `AppState.init` overwrites `L10n.current` from UserDefaults, so English must be
        // switched on after construction and before the demo ledger is generated —
        // the generator localises its sample notes at that moment.
        let state = AppState(settings: QuoteSettings(), persist: { _ in })
        L10n.current = .en
        // Keeps `state.language` and `L10n.current` in sync so the Settings picker is English too.
        state.setLanguage(.en)
        // Go through the real Demo Mode instead of injecting a ledger, so the screenshots
        // show what a first-time visitor sees: the Phase 1 sample ledger (history and
        // previous closes, no "Awaiting data") and no backup reminder (suppressed in demo).
        state.enterDemo()
        NSLog("HARNESS state-ready lang=\(L10n.current.rawValue) screen=\(screen)")
        // Only the import screenshot needs it: lets `ImportView` skip the file picker and
        // show the mapping/preview steps with a fictional broker export.
        ImportView.prefillOverride = Self.importCSV

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: makeScreen(screen, state: state))
        NSLog("HARNESS rootVC-set")
        window.makeKeyAndVisible()
        NSLog("HARNESS key-visible")
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSLog("HARNESS alive+3s")
            // 给截图脚本一个可断言的口径：这一屏到底有没有数据。
            // 空态截图同样有一百多 KB，体积守卫拦不住。
            NSLog("HARNESS derived screen=\(screen) days=\(state.dayReturns.count) months=\(state.insights.months.count)")
        }
        return true
    }

    @ViewBuilder
    private func makeScreen(_ screen: String, state: AppState) -> some View {
        switch screen {
        case "trades":
            NavigationStack { TradesView(onAdd: {}) }.environmentObject(state)
        case "returns":
            NavigationStack { InsightsView() }.environmentObject(state)
        case "settings":
            NavigationStack { SettingsView() }.environmentObject(state)
        case "calendar":
            NavigationStack { CalendarOnlyView() }.environmentObject(state)
        case "import":
            NavigationStack { ImportView() }.environmentObject(state)
        default:
            NavigationStack { HoldingsView(onAdd: {}, onOpenSettings: {}) }.environmentObject(state)
        }
    }

}

/// 与 `InsightsView` 里的日历同一个视图，但单独一屏以便取图。
/// 数据取示例账本自己重放出来的每日收益，不再是手写的假序列。
///
/// 必须是**带 `@EnvironmentObject` 的 View**：把 `state` 当普通参数传进来、在层级里直接读
/// `state.insights`，SwiftUI 不会订阅 `AppState`，`derived` 重算完这一屏不会刷新，
/// 截图就停在空态（已踩过：`calendar.png` 显示 “No history synced yet”）。
private struct CalendarOnlyView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section("Returns calendar") {
                ReturnCalendar(data: state.insights).equatable()
            }
        }
        .navigationTitle("Returns")
    }
}
