import SwiftUI

// 2.0 根界面：四个主要页面（持仓 / 交易 / 收益 / 设置）+ 全屏“记一笔”入口。
// 全部使用系统导航、列表、表单和日期选择器，跟随系统文字大小、深浅色与辅助功能。

enum Appearance {
    static let themes = ["system", "light", "dark"]
    static func scheme(_ value: String) -> ColorScheme? {
        switch value {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct ThemeColors {
    let redUp: Bool
    func gain(_ scheme: ColorScheme) -> Color {
        redUp ? Color(red: 0.84, green: 0.16, blue: 0.24) : Color(red: 0.09, green: 0.51, blue: 0.27)
    }
    func loss(_ scheme: ColorScheme) -> Color {
        redUp ? Color(red: 0.09, green: 0.51, blue: 0.27) : Color(red: 0.84, green: 0.16, blue: 0.24)
    }
    func tone(_ value: Decimal?) -> String {
        guard let value else { return "secondary" }
        if value > 0 { return "gain" }
        if value < 0 { return "loss" }
        return "secondary"
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("appearance.theme") private var theme = "system"
    @AppStorage("appearance.colors") private var colorSchemePreference = "green-up"

    @State private var tab: Int = 0
    @State private var showingTradeForm = false
    @State private var editingTrade: Trade?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HoldingsView(onAdd: presentNewTrade)
            }
            .tabItem { Label("持仓", systemImage: "wallet.bifold") }
            .tag(0)

            NavigationStack {
                TradesView(onAdd: presentNewTrade)
            }
            .tabItem { Label("交易", systemImage: "list.bullet.rectangle") }
            .tag(1)

            NavigationStack {
                InsightsView()
            }
            .tabItem { Label("收益", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(3)
        }
        .overlay(alignment: .bottom) {
            Button(action: presentNewTrade) {
                Label("记一笔", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 68)
            .accessibilityLabel("记一笔")
        }
        .sheet(isPresented: $showingTradeForm) {
            TradeFormView(trade: editingTrade)
                .environmentObject(state)
        }
        .preferredColorScheme(Appearance.scheme(theme))
    }

    private func presentNewTrade() {
        editingTrade = nil
        showingTradeForm = true
    }
}

/// 统一的金额着色：正负号之外还有颜色与语义标签，不只靠颜色传达盈亏。
struct AmountText: View {
    let value: Decimal?
    var signed = true
    @AppStorage("appearance.colors") private var colorSchemePreference = "green-up"
    @Environment(\.colorScheme) private var scheme

    private var colors: ThemeColors { ThemeColors(redUp: colorSchemePreference == "red-up") }

    var body: some View {
        let text = signed ? Fmt.signedMoney(value) : Fmt.money(value)
        Text(text)
            .monospacedDigit()
            .foregroundStyle(color(for: value))
            .accessibilityLabel(value == nil ? "待补全" : (value! > 0 ? "盈利 \(text)" : value! < 0 ? "亏损 \(text)" : "持平 \(text)"))
    }

    private func color(for value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return colors.gain(scheme) }
        if value < 0 { return colors.loss(scheme) }
        return .primary
    }
}
