import SwiftUI

// 根界面：四个主要页面（持仓 / 交易 / 收益 / 设置）。
// 「记一笔」入口在持仓 / 交易页导航栏右上角的 "+"（V1.0 最后一轮 UI 从悬浮按钮改过来）。
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance.theme") private var theme = "system"
    @AppStorage("appearance.colors") private var colorSchemePreference = "green-up"

    @State private var tab: Int = 0
    @State private var showingTradeForm = false
    @State private var editingTrade: Trade?

    /// UI 日期跟随 App 语言，而不是设备 locale：DatePicker 等系统控件的显示文本取自环境 locale。
    /// 数据层不受影响，仍用 DateFormatter.ledgerDate（en_US_POSIX + yyyy-MM-dd）。
    /// 见 docs/ENGLISH_UI_AUDIT.md A1 根因 3。
    private var displayLocale: Locale {
        Locale(identifier: state.language == .en ? "en_US" : "zh_CN")
    }
    private struct RefreshTrigger: Equatable {
        var settings: QuoteSettings
        var active: Bool
        var demo: Bool
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HoldingsView(onAdd: presentNewTrade, onOpenSettings: { tab = 3 })
            }
            .tabItem { Label(L10n.tr("持仓"), systemImage: "wallet.bifold") }
            .tag(0)

            NavigationStack {
                TradesView(onAdd: presentNewTrade)
            }
            .tabItem { Label(L10n.tr("交易"), systemImage: "list.bullet.rectangle") }
            .tag(1)

            NavigationStack {
                InsightsView()
            }
            .tabItem { Label(L10n.tr("收益"), systemImage: "chart.line.uptrend.xyaxis") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(L10n.tr("设置"), systemImage: "gearshape") }
            .tag(3)
        }
        .id(state.language)
        .safeAreaInset(edge: .top) {
            if state.demo {
                HStack(spacing: 8) {
                    Text("DEMO")
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                        .foregroundStyle(.white)
                    Text(L10n.tr("示例数据，不会保存；你的账本未被修改。"))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L10n.tr("示例模式：界面显示的是虚构示例数据，你的账本未被修改。"))
                    Spacer(minLength: 0)
                    Button(L10n.tr("退出")) { state.exitDemo() }
                        .font(.footnote.weight(.semibold))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.orange.opacity(0.22))
            } else if let failure = state.loadFailure {
                Text(LedgerStore.bannerText(for: failure))
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.yellow.opacity(0.25))
            }
        }
        .sheet(isPresented: $showingTradeForm) {
            TradeFormView(trade: editingTrade)
                .environmentObject(state)
        }
        .preferredColorScheme(Appearance.scheme(theme))
        .onChange(of: scenePhase) { phase in
            // 进入后台时留一个「正常结束」标记；下次启动看到它才算干净退出。
            if phase == .background { Diagnostics.record("EXIT") }
        }
        .task(id: RefreshTrigger(settings: state.quoteSettings, active: scenePhase == .active, demo: state.demo)) {
            let interval = state.quoteSettings.interval
            // 示例模式不发行情请求：既没有意义，也可能产生费用。
            guard scenePhase == .active, interval > 0, !state.demo else { return }
            while !Task.isCancelled {
                await state.refreshQuotes()
                do { try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000) }
                catch { return }
            }
        }
        // 放在链尾，让此前提下的 sheet/alert 也继承同一个 locale。
        .environment(\.locale, displayLocale)
    }

    private func presentNewTrade() {
        editingTrade = nil
        showingTradeForm = true
    }
}

/// 收益类数值行：标签 + 金额，金额统一按涨跌配色设置显示。
/// 所有涉及盈亏的界面都应使用它，避免出现固定颜色的收益数字。
struct ProfitRow: View {
    let label: String
    let value: Decimal?
    var signed = true
    /// 同一行右侧的补充数字（例如收益率）。固定用等宽 + 次级色，与金额形成层次。
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            AmountText(value: value, signed: signed)
            if let detail {
                Text(detail).monospacedDigit().foregroundStyle(.secondary)
            }
        }
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
            .accessibilityLabel(value == nil ? L10n.tr("待补全") : (value! > 0 ? L10n.tr("盈利") + " \(text)" : value! < 0 ? L10n.tr("亏损") + " \(text)" : L10n.tr("持平") + " \(text)"))
    }

    private func color(for value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return colors.gain(scheme) }
        if value < 0 { return colors.loss(scheme) }
        return .primary
    }
}
