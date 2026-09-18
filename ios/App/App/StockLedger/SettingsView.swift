import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @AppStorage("appearance.theme") private var theme = "system"
    @AppStorage("appearance.colors") private var colors = "green-up"

    @State private var exportText: String?
    @State private var showingImporter = false
    @State private var pendingImport: Ledger?
    @State private var importError: String?
    @State private var shareBox: ShareBox?
    @State private var showingDemoConfirm = false
    @State private var showingClearConfirm = false
    @AppStorage("backup.lastExport") private var lastExport = 0.0
    @AppStorage("demo.loaded") private var demoLoaded = false

    @State private var providerDraft: QuoteProvider = .yahoo
    @State private var urlDraft = ""
    @State private var keyDraft = ""
    @State private var intervalDraft = 60
    @State private var quoteNotice: String?
    @State private var quoteFailure: String?

    var body: some View {
        List {
            Section("显示") {
                Picker("外观", selection: $theme) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Picker("涨跌颜色", selection: $colors) {
                    Text("绿涨红跌").tag("green-up")
                    Text("红涨绿跌").tag("red-up")
                }
                HStack(spacing: 16) {
                    AmountText(value: 12.34)
                    AmountText(value: -12.34)
                }
                .font(.footnote)
            }

            Section {
                Picker("行情来源", selection: $providerDraft) {
                    ForEach(QuoteProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                Text(providerDraft.detail).font(.caption).foregroundStyle(.secondary)

                if providerDraft == .custom {
                    TextField("接口地址，例如 https://api.example.com/quote/{symbol}", text: $urlDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                if providerDraft != .yahoo {
                    SecureField(providerDraft == .finnhub ? "Finnhub API Key" : "Bearer Token（可留空）", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("刷新间隔", selection: $intervalDraft) {
                    Text("仅手动").tag(0)
                    Text("60 秒").tag(60)
                    Text("5 分钟").tag(300)
                }
                Button("保存行情设置") { saveQuotes() }
                if let quoteNotice {
                    Label(quoteNotice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                }
                if let quoteFailure {
                    Label(quoteFailure, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
                LabeledContent("上次同步", value: state.lastSyncedAt.map { Fmt.clock($0) } ?? "尚未同步")
                Button {
                    Task { await sync() }
                } label: {
                    if state.syncingQuotes { Label("正在同步…", systemImage: "arrow.triangle.2.circlepath") }
                    else { Label("立即同步持仓行情", systemImage: "arrow.clockwise") }
                }
                .disabled(state.syncingQuotes)
                ForEach(state.quoteErrors.sorted { $0.key < $1.key }, id: \.key) { entry in
                    Label("\(entry.key)：\(entry.value)", systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("行情来源")
            } footer: {
                Text("API Key 保存在系统钥匙串，仅在本机发起行情请求；不上传账本，也不随备份导出。Yahoo 只提供已完成交易日的收盘价。")
            }

            Section {
                NavigationLink("券商 CSV 导入") { ImportView() }
                if exportText != nil {
                    Button {
                        shareBox = ShareBox(value: exportText ?? "")
                    } label: {
                        Label("导出账本备份", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label("导出账本备份", systemImage: "square.and.arrow.up").foregroundStyle(.secondary)
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("从备份恢复", systemImage: "square.and.arrow.down")
                }
                LabeledContent("当前账本", value: "\(state.ledger.trades.count) 笔交易 · \(state.ledger.cash.count) 笔现金记录")
                LabeledContent("上次备份", value: BackupReminder.text(lastExport))
            } header: {
                Text("数据")
            } footer: {
                Text("CSV 导入先预览、再写入，重复导入不会重复记账；备份为 JSON 文本，不含任何密钥。建议每 30 天导出一次。")
            }

            Section {
                Button("载入示例账本") { showingDemoConfirm = true }
                if demoLoaded {
                    Button("退出示例并清空账本", role: .destructive) { showingClearConfirm = true }
                }
            } header: {
                Text("示例")
            } footer: {
                Text("示例账本包含几笔买卖、分红和费用，只用于体验界面与计算；载入会替换当前账本，建议先导出备份。")
            }

            Section("帮助") {
                NavigationLink("使用说明") { HelpView() }
                LabeledContent("账本格式", value: "2（不与 1.x 共用）")
            }

            Section {
                LabeledContent("版本", value: "2.0.0 (1)")
                LabeledContent("应用标识", value: "com.personal.stockledger")
            } footer: {
                Text("2.0 使用原生 SwiftUI 界面，账本保存在本机，不上传任何数据。")
            }
        }
        .navigationTitle("设置")
        .task {
            exportText = try? LedgerStore.exportText(state.ledger)
            loadQuoteDrafts()
        }
        .onChange(of: state.ledger.trades.count) { _ in exportText = try? LedgerStore.exportText(state.ledger) }
        .onChange(of: state.ledger.cash.count) { _ in exportText = try? LedgerStore.exportText(state.ledger) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    pendingImport = try JSONDecoder().decode(Ledger.self, from: data)
                } catch {
                    importError = "备份文件无法读取：\(error.localizedDescription)"
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("恢复这份备份？", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("取消", role: .cancel) { pendingImport = nil }
            Button("替换并恢复", role: .destructive) {
                if let ledger = pendingImport { state.replace(with: ledger) }
                pendingImport = nil
            }
        } message: {
            Text("将替换当前的 \(state.ledger.trades.count) 笔交易与 \(state.ledger.cash.count) 笔现金记录。建议先导出当前账本。")
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $shareBox) { box in
            ShareSheet(items: [box.value]) { completed in
                if completed { lastExport = Date().timeIntervalSince1970 }
            }
        }
        .alert("载入示例账本？", isPresented: $showingDemoConfirm) {
            Button("取消", role: .cancel) {}
            Button("载入示例", role: .destructive) {
                state.loadDemo()
                demoLoaded = true
            }
        } message: {
            Text("将替换当前的 \(state.ledger.trades.count) 笔交易与 \(state.ledger.cash.count) 笔现金记录。")
        }
        .alert("清空当前账本？", isPresented: $showingClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                state.clearAll()
                demoLoaded = false
            }
        } message: {
            Text("账本会恢复为空。请确认已导出备份，清空操作无法撤销。")
        }
    }

    private func loadQuoteDrafts() {
        let settings = state.quoteSettings
        providerDraft = settings.provider
        urlDraft = settings.url
        keyDraft = settings.key
        intervalDraft = settings.interval
    }

    private func saveQuotes() {
        quoteNotice = nil
        quoteFailure = nil
        do {
            try state.saveQuoteSettings(QuoteSettings(provider: providerDraft, url: urlDraft, key: keyDraft, interval: intervalDraft))
            loadQuoteDrafts()
            quoteNotice = keyDraft.isEmpty ? "行情设置已保存。" : "行情设置已保存到系统钥匙串。"
        } catch {
            quoteFailure = error.localizedDescription
        }
    }

    private func sync() async {
        quoteNotice = nil
        quoteFailure = nil
        await state.refreshQuotes()
        if state.quoteErrors.isEmpty {
            quoteNotice = state.openSymbols.isEmpty ? "当前没有持仓需要同步。" : "行情同步完成。"
        } else {
            quoteFailure = "有 \(state.quoteErrors.count) 只股票刷新失败，已保留原有价格。"
        }
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
        guard stamp > 0 else { return "尚未备份" }
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
            Section("持仓与今日盈亏") {
                Text("首页「今日盈亏」结合上一交易日收盘、当前价格和当天买卖及手续费计算；缺少必要行情时显示待补全，不以零代替。「持有收益」是当前持仓的浮动收益，与今日涨跌不同。")
            }
            Section("交易与成本") {
                Text("买入金额和手续费加入持仓成本；卖出按卖出前的移动平均成本扣减。已实现收益 = 卖出金额 − 手续费 − 卖出部分成本。交易页可按日期区间、买卖类型和关键字筛选并汇总。")
            }
            Section("现金账本") {
                Text("期初余额是期初日当天开始前的现金，允许为零，不支持负数。期初日及之后的入金、出金、分红、费用和买卖会联动余额；余额 = 期初 + 入金 − 出金 + 分红（扣税）− 费用 + 卖出收入 − 买入支出。买卖是资产转换，不计入盈亏。")
            }
            Section("离线与隐私") {
                Text("账本保存在本机 Documents 目录，不注册账号、不上传数据。只有在你点击「同步行情」时才会向所选行情来源发送股票代码请求；API Key 存在系统钥匙串，不会写入账本或备份。")
            }
            Section("行情与报价") {
                Text("Yahoo 只提供已完成交易日的收盘价，盘中不显示当日最新价；Finnhub 或自定义接口可提供盘中最新报价。刷新失败会保留已有价格并说明原因，不会用零价替代。手动录入的报价优先于自动同步，且不参与今日盈亏的上一收盘基准。")
            }
            Section("收益日历") {
                Text("收益日历按每个交易日重放账本：当日收益 = 当日收盘市值 − 上一交易日收盘市值 + 当日卖出净额 − 当日买入含费支出。月份用左右箭头切换，格子里直接显示当日收益金额，点按查看按股票的明细；缺少收盘价的交易日显示“待补”且不计入月度合计。累计收益曲线把每日收益逐日累加，横轴每周标出刻度，虚线是零轴。日历与曲线需要先「同步历史」获取收盘价与交易日历（来自 Yahoo 日线）。")
            }
            Section("券商 CSV 导入") {
                Text("分两种类型：成交明细用于补全持仓与已实现收益，资金流水用于补全入金、出金、分红与账户费用。支持逗号、分号或制表符分隔，自动识别中英文列名，也可手动指定列；表头缺少类型列时可指定统一类型。导入前会显示可导入、疑似重复、已导入与无法导入的行数：按编号判定为已导入的行不会重复记账；与账本中关键字段完全相同的行标记为疑似重复，默认不勾选。成交明细在同一天已有该股票交易时，需要选择追加到同日之后或插入到同日之前，因为顺序会影响已实现收益；若出现超卖会整体拒绝，账本保持不变。")
            }
        }
        .navigationTitle("使用说明")
    }
}
