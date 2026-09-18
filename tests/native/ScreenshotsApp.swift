import SwiftUI
import UIKit

// Simulator-only harness: render each main screen in English (L10n.current = .en)
// with the demo ledger, one screen per launch, so the CI can capture app screenshots.
@main
final class ScreenshotsApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        L10n.current = .en
        let screen = ProcessInfo.processInfo.arguments.dropFirst().first ?? "holdings"
        let state = AppState(ledger: LedgerStore.demo())
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
