import SwiftUI
import UIKit

// Simulator-only harness: render the production calendar in the same List row
// container as InsightsView. All amounts and dates are synthetic.
@main
final class CalendarRenderApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        let month = args.dropFirst().first ?? "2026-09"
        let count = month == "2026-02" ? 28 : month == "2026-09" ? 30 : 31
        var days: [Engine.DayReturn] = []
        for day in 1...count {
            let amount: Decimal = Decimal(day % 2 == 0 ? day : -day)
            let profit: Decimal? = day == 10 ? nil : amount
            let date = String(format: "%@-%02d", month, day)
            let missing: [String] = day == 10 ? ["TEST: missing close"] : []
            days.append(Engine.DayReturn(date: date, previous: nil, profit: profit,
                                        cumulative: Decimal(day), contributions: [], missing: missing))
        }
        let presentation = InsightsPresentation(days: month == "empty" ? [] : days)
        let content = NavigationStack {
            List {
                Section("收益日历 · 合成测试数据") {
                    ReturnCalendar(data: presentation).equatable()
                }
                Section("累计收益曲线") {
                    CumulativeProfitChart(data: presentation).equatable()
                }
            }.navigationTitle("收益分析")
        }
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
