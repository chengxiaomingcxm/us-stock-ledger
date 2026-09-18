import SwiftUI
import UIKit

// Simulator-only harness: render each main screen in English (L10n.current = .en)
// with the demo ledger, one screen per launch, so the CI can capture app screenshots.
@main
final class ScreenshotsApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let screen = ProcessInfo.processInfo.arguments.dropFirst().first ?? "holdings"
        // AppState 初始化从 UserDefaults 读取语言，因此在创建前先持久化英文。
        UserDefaults.standard.set("en", forKey: "app.language")
        // 给示例账本补上「当日报价」，让今日盈亏与持仓显示真实数字而不是待补全。
        let today = MarketClock.date()
        var demo = LedgerStore.demo()
        for index in demo.quotes.indices { demo.quotes[index].date = today }
        // 用 no-op persist 创建，避免裸 harness 向沙盒写盘（这也是上一版崩溃的原因）。
        let state = AppState(ledger: demo, persist: { _ in })
        let yesterday = MarketClock.previousWeekday(today) ?? "2026-09-17"
        state.previousClose = [
            "AAPL": Decimal(string: "216.40") ?? 0,
            "MSFT": Decimal(string: "498.75") ?? 0,
            "VOO": Decimal(string: "569.30") ?? 0,
        ]
        state.previousCloseDates = ["AAPL": yesterday, "MSFT": yesterday, "VOO": yesterday]

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: makeScreen(screen, state: state))
        window.makeKeyAndVisible()
        self.window = window
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
            NavigationStack { calendarList() }.environmentObject(state)
        default:
            NavigationStack { HoldingsView(onAdd: {}, onOpenSettings: {}) }.environmentObject(state)
        }
    }

    private func calendarList() -> some View {
        let presentation = InsightsPresentation(days: sampleDays(month: "2026-09"))
        return List {
            Section("Returns calendar") {
                ReturnCalendar(data: presentation).equatable()
            }
        }
        .navigationTitle("Returns")
    }

    private func sampleDays(month: String) -> [Engine.DayReturn] {
        let count = month == "2026-02" ? 28 : month == "2026-09" ? 30 : 31
        var days: [Engine.DayReturn] = []
        for day in 1 ... count {
            let amount = Decimal(day % 2 == 0 ? day : -day)
            let profit: Decimal? = day == 10 ? nil : amount
            let date = String(format: "%@-%02d", month, day)
            days.append(Engine.DayReturn(date: date, previous: nil, profit: profit,
                                         cumulative: Decimal(day), contributions: [], missing: []))
        }
        return days
    }
}
