import SwiftUI
import UIKit

// Simulator-only harness: render each main screen in English (L10n.current = .en)
// with the demo ledger, one screen per launch, so the CI can capture app screenshots.
@main
final class ScreenshotsApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("HARNESS-START")
        let screen = ProcessInfo.processInfo.arguments.dropFirst().first ?? "holdings"
        print("HARNESS screen=\(screen)")
        // no-op persist：裸 harness 不写盘；语言必须在 AppState 初始化之后再切，
        // 因为初始化会把语言重置为 UserDefaults 里的持久化默认值。
        let state = AppState(ledger: LedgerStore.demo(), persist: { _ in })
        print("HARNESS state-created")
        state.setLanguage(.en)
        print("HARNESS language-en")

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: makeScreen(screen, state: state))
        print("HARNESS rootVC-set")
        window.makeKeyAndVisible()
        print("HARNESS key-visible")
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { print("HARNESS alive+2s") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { print("HARNESS alive+5s") }
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
