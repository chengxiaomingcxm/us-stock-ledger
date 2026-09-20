import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 设置首页只做分类与入口：显示 / 行情数据 / 数据 / 支持。
/// 具体操作与说明都收在二级页里（见本文件下半部分的各个二级页 View）。
struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section(L10n.tr("显示")) {
                NavigationLink(L10n.tr("语言")) { LanguageSettingsView() }
                NavigationLink(L10n.tr("外观")) { AppearanceSettingsView() }
                NavigationLink(L10n.tr("涨跌颜色")) { GainColorSettingsView() }
            }

            // 行情数据只有一个入口；说明文字留在行情来源页里，首页不堆说明。
            Section(L10n.tr("行情数据")) {
                NavigationLink {
                    QuoteSourceView()
                } label: {
                    HStack {
                        Label(L10n.tr("行情来源"), systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(state.quoteSettings.provider.label)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.tr("数据")) {
                NavigationLink(L10n.tr("导入与导出")) { ImportExportView() }
                NavigationLink(L10n.tr("备份与恢复")) { BackupRestoreView() }
                NavigationLink(L10n.tr("账本信息")) { LedgerInfoView() }
            }

            Section(L10n.tr("支持")) {
                NavigationLink(L10n.tr("示例")) { DemoView() }
                NavigationLink(L10n.tr("帮助")) { HelpView() }
                NavigationLink(L10n.tr("关于")) { AboutView() }
            }
        }
        .navigationTitle(L10n.tr("设置"))
    }
}

// MARK: - 设置二级页
//
// 全部放在本文件内是刻意的：新增 Swift 文件要同时登记
// `App.xcodeproj/project.pbxproj` 的四处与 `scripts/test-native.sh` 的文件列表，
// 漏一处就是「本地全绿、CI 报错」。这些页面没有独立复用的价值，不值得付这个成本。

/// 语言：只改界面文字，不动账本与行情数据。
struct LanguageSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Picker(L10n.tr("语言"), selection: Binding(get: { state.language }, set: { state.setLanguage($0) })) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
        }
        .navigationTitle(L10n.tr("语言"))
    }
}

/// 外观：跟随系统 / 浅色 / 深色。
struct AppearanceSettingsView: View {
    @AppStorage("appearance.theme") private var theme = "system"

    var body: some View {
        List {
            Picker(L10n.tr("外观"), selection: $theme) {
                Text(L10n.tr("跟随系统")).tag("system")
                Text(L10n.tr("浅色")).tag("light")
                Text(L10n.tr("深色")).tag("dark")
            }
        }
        .navigationTitle(L10n.tr("外观"))
    }
}

/// 涨跌颜色：两个示例金额就地预览，选完不用退回列表对照。
struct GainColorSettingsView: View {
    @AppStorage("appearance.colors") private var colors = "green-up"

    var body: some View {
        List {
            Picker(L10n.tr("涨跌颜色"), selection: $colors) {
                Text(L10n.tr("绿涨红跌")).tag("green-up")
                Text(L10n.tr("红涨绿跌")).tag("red-up")
            }
            HStack(spacing: 16) {
                AmountText(value: 12.34)
                AmountText(value: -12.34)
            }
            .font(.footnote)
        }
        .navigationTitle(L10n.tr("涨跌颜色"))
    }
}

/// 导入与导出：券商 CSV、银行月结单 PDF、错误日志。
struct ImportExportView: View {
    @EnvironmentObject private var state: AppState

    @State private var diagnosticsText: String?
    @State private var shareBox: ShareBox?

    var body: some View {
        List {
            Section {
                NavigationLink(L10n.tr("券商 CSV 导入")) { ImportView() }
                NavigationLink(L10n.tr("银行月结单 PDF 导入")) { StatementImportView() }
            } footer: {
                Text(L10n.tr("CSV 导入先预览、再写入，重复导入不会重复记账。"))
            }

            if let diagnostics = diagnosticsText {
                Section {
                    Button {
                        shareBox = ShareBox(value: diagnostics)
                    } label: {
                        Label(L10n.tr("导出错误日志"), systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text(L10n.tr("错误日志只在本机记录，用于排查导入与同步问题。"))
                }
            }
        }
        .navigationTitle(L10n.tr("导入与导出"))
        .task { refreshDiagnostics() }
        .onChange(of: state.errorMessage) { _ in refreshDiagnostics() }
        .sheet(item: $shareBox) { box in ShareSheet(items: [box.value]) }
    }

    /// 只有真的写过日志才显示导出入口，避免让用户分享一个空文件。
    private func refreshDiagnostics() {
        let text = Diagnostics.text()
        diagnosticsText = text.isEmpty ? nil : text
    }
}

/// 备份与恢复：导出、恢复、当前账本规模与上次备份时间。
/// 这里是唯一会替换整份账本的地方，所以确认弹窗与失败提示都留在这。
struct BackupRestoreView: View {
    @EnvironmentObject private var state: AppState

    @State private var exportText: String?
    @State private var exportError: String?
    @State private var showingImporter = false
    @State private var pendingImport: Ledger?
    @State private var importError: String?
    @State private var shareBox: ShareBox?
    @AppStorage("backup.lastExport") private var lastExport = 0.0

    var body: some View {
        List {
            Section {
                if exportText != nil {
                    Button {
                        shareBox = ShareBox(value: exportText ?? "")
                    } label: {
                        Label(L10n.tr("导出账本备份"), systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label(L10n.tr("导出账本备份"), systemImage: "square.and.arrow.up").foregroundStyle(.secondary)
                }
                Button {
                    showingImporter = true
                } label: {
                    Label(L10n.tr("从备份恢复"), systemImage: "square.and.arrow.down")
                }
                LabeledContent(L10n.tr("当前账本"), value: "\(state.ledger.trades.count) \(L10n.tr("笔交易")) · \(state.ledger.cash.count) \(L10n.tr("笔现金记录"))")
                LabeledContent(L10n.tr("上次备份"), value: BackupReminder.text(lastExport))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("备份为 JSON 文本，不含任何密钥。建议每 30 天导出一次。"))
                    // 导出失败以前是静默的：按钮变灰，既没有说明也没有日志。
                    if let exportError {
                        Text(exportError).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("备份与恢复"))
        .task { refreshExport() }
        .onChange(of: state.ledger.trades.count) { _ in refreshExport() }
        .onChange(of: state.ledger.cash.count) { _ in refreshExport() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    pendingImport = try LedgerStore.decode(data)
                } catch {
                    Diagnostics.record("RESTORE", error: error)
                    importError = L10n.tr("这不是本应用的账本备份文件，未做任何改动。请选择由「导出账本备份」生成的文件。")
                }
            case .failure(let error):
                Diagnostics.record("RESTORE", error: error)
                importError = L10n.tr("无法读取所选文件，未做任何改动。")
            }
        }
        .alert(L10n.tr("恢复这份备份？"), isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button(L10n.tr("取消"), role: .cancel) { pendingImport = nil }
            Button(L10n.tr("替换并恢复"), role: .destructive) {
                if let ledger = pendingImport, !state.replaceFromBackup(ledger) {
                    importError = state.errorMessage ?? L10n.tr("操作失败，账本未改变。")
                }
                pendingImport = nil
            }
        } message: {
            Text(L10n.tr("将替换当前的") + " \(state.ledger.trades.count) \(L10n.tr("笔交易")) · \(state.ledger.cash.count) \(L10n.tr("笔现金记录"))" + L10n.tr("。"))
        }
        .alert(L10n.tr("导入失败"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(L10n.tr("好"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $shareBox) { box in
            ShareSheet(items: [box.value]) { completed in
                if completed { lastExport = Date().timeIntervalSince1970 }
            }
        }
    }

    /// 导出失败要能看见：以前 `try?` 把失败吞掉，只表现为按钮变灰。
    private func refreshExport() {
        do {
            exportText = try LedgerStore.exportText(state.ledger)
            exportError = nil
        } catch {
            exportText = nil
            Diagnostics.record("EXPORT", error: error)
            exportError = L10n.tr("导出失败，账本数据仍在本机；请稍后重试。")
        }
    }
}

/// 账本信息：只读状态。期初余额仍在「收益 → 现金账本」里维护，
/// 这里不放任何写操作，也不暴露清空账本这类危险动作。
struct LedgerInfoView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                LabeledContent(L10n.tr("当前账本"), value: "\(state.ledger.trades.count) \(L10n.tr("笔交易")) · \(state.ledger.cash.count) \(L10n.tr("笔现金记录"))")
                LabeledContent(L10n.tr("账本格式"), value: "\(Ledger.currentFormat)")
                LabeledContent(L10n.tr("期初余额"), value: openingText)
                // 期初未设置时现金余额算不出来，就不显示这一行，不用零代替。
                if let balance = Engine.cashTotals(state.ledger).balance {
                    LabeledContent(L10n.tr("当前现金余额"), value: Fmt.money(balance))
                }
            } footer: {
                Text(L10n.tr("期初余额与现金记录在「收益 → 现金账本」中维护。"))
            }
        }
        .navigationTitle(L10n.tr("账本信息"))
    }

    private var openingText: String {
        guard let opening = state.ledger.opening else { return L10n.tr("未设置") }
        return "\(opening.date) · \(Fmt.money(opening.amount))"
    }
}

/// 示例：进出只读示例账本。
struct DemoView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                if state.demo {
                    Button(L10n.tr("退出示例模式")) { state.exitDemo() }
                } else {
                    Button(L10n.tr("试用示例账本")) { state.enterDemo() }
                }
            } footer: {
                Text(L10n.tr("示例包含 5 只持仓、30 多笔历史交易、分红与出入金，全部为虚构数据；只存在于内存中，不会写入或覆盖你的账本，退出后立即回到你自己的数据。"))
            }
        }
        .navigationTitle(L10n.tr("示例"))
    }
}

/// 关于：应用名、版本、标识与数据位置。
struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent(L10n.tr("应用名称"), value: "Stock Ledger")
                LabeledContent(L10n.tr("版本"), value: version)
                LabeledContent(L10n.tr("应用标识"), value: "com.personal.stockledger")
            } footer: {
                Text(L10n.tr("账本保存在本机；开启行情刷新时只发送股票代码，不发送交易股数、金额或银行文件。"))
            }
        }
        .navigationTitle(L10n.tr("关于"))
    }
}

struct ShareBox: Identifiable {
    let id = UUID()
    let value: String
}

/// 系统分享面板；导出完成后记录时间，用于备份提醒。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum BackupReminder {
    static let interval: TimeInterval = 30 * 86_400

    static func text(_ stamp: Double) -> String {
        guard stamp > 0 else { return L10n.tr("尚未备份") }
        return Fmt.clock(Date(timeIntervalSince1970: stamp))
    }

    static func overdue(_ stamp: Double) -> Bool {
        guard stamp > 0 else { return true }
        return Date().timeIntervalSince1970 - stamp > interval
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section(L10n.tr("持仓与今日盈亏")) {
                Text(L10n.tr("首页「今日盈亏」结合上一交易日收盘、当前价格和当天买卖及手续费计算；缺少必要行情时显示待补全，不以零代替。「持有收益」是当前持仓的浮动收益，与今日涨跌不同。"))
            }
            Section(L10n.tr("交易与成本")) {
                Text(L10n.tr("买入金额和手续费加入持仓成本；卖出按卖出前的移动平均成本扣减。已实现收益 = 卖出金额 − 手续费 − 卖出部分成本。交易页可按日期区间、买卖类型和关键字筛选并汇总。"))
            }
            Section(L10n.tr("现金账本")) {
                Text(L10n.tr("期初余额是期初日当天开始前的现金，允许为零，不支持负数。期初日及之后的入金、出金、分红、费用和买卖会联动余额；余额 = 期初 + 入金 − 出金 + 分红（扣税）− 费用 + 卖出收入 − 买入支出。买卖是资产转换，不计入盈亏。"))
            }
            Section(L10n.tr("账本格式")) {
                Text(L10n.tr("账本格式 {} 是 1.0 的数据基线：从 1.0 起写入的账本和备份，后续版本继续可读；更早的账本与备份不保证能直接恢复。恢复备份会替换当前账本，请先导出当前备份。", "\(Ledger.currentFormat)"))
            }
            Section(L10n.tr("离线与隐私")) {
                Text(L10n.tr("账本和银行文件在本机处理。手动同步或开启前台自动刷新时，会向行情服务发送股票代码；不会发送交易股数、金额或银行文件。API Key 存在系统钥匙串，不包含在账本备份中。"))
            }
            Section(L10n.tr("行情与报价")) {
                Text(L10n.tr("价格模式可选自动、最近收盘或所选接口最新报价。自动模式在休市时段使用 Yahoo 已完成日线，盘中使用所选接口；固定收盘模式不使用 Finnhub Key。刷新失败保留旧价，同日手动报价优先。页面按实际美东报价日期显示收益。"))
            }
            Section(L10n.tr("收益日历")) {
                Text(L10n.tr("收益日历按每个交易日重放账本：当日收益 = 当日收盘市值 − 上一交易日收盘市值 + 当日卖出净额 − 当日买入含费支出。月份用左右箭头切换，格子里直接显示当日收益金额，点按查看按股票的明细；缺少收盘价的交易日显示“待补”且不计入月度合计。累计收益曲线把每日收益逐日累加，横轴最多显示六个日期刻度，虚线是零轴。日历与曲线需要先「同步历史」获取收盘价与交易日历（来自 Yahoo 日线）。"))
            }
            Section(L10n.tr("银行月结单 PDF")) {
                Text(L10n.tr("支持汇丰带文字层的投资服务综合结单 PDF，可多选文件并在本机解锁。在文件列表里先点一下结单让它出现勾选，再点右上角「打开」；选择器会以副本方式交付，读取完成后副本会在离开页面时删除。预览美元股票买卖、关联费用和派付分红，核对后确认；已识别银行编号重复的记录不重复添加，疑似手工重复默认不选。港币基金、扫描件及银行往来账户流水暂不支持。只有分红到账额时不猜测税费；投资结单里没有的入金、出金和期初现金需要另行填写。"))
            }
            Section(L10n.tr("券商 CSV 导入")) {
                Text(L10n.tr("分两种类型：成交明细用于补全持仓与已实现收益，资金流水用于补全入金、出金、分红与账户费用。支持逗号、分号或制表符分隔，自动识别中英文列名，也可手动指定列；表头缺少类型列时可指定统一类型。导入前会显示可导入、疑似重复、已导入与无法导入的行数：按编号判定为已导入的行不会重复记账；与账本中关键字段完全相同的行标记为疑似重复，默认不勾选。成交明细在同一天已有该股票交易时，需要选择追加到同日之后或插入到同日之前，因为顺序会影响已实现收益；若出现超卖会整体拒绝，账本保持不变。"))
            }
        }
        .navigationTitle(L10n.tr("使用说明"))
    }
}
