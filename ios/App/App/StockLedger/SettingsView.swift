import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @AppStorage("appearance.theme") private var theme = "system"
    @AppStorage("appearance.colors") private var colors = "green-up"

    @State private var exportText: String?
    @State private var showingImporter = false
    @State private var pendingImport: Ledger?
    @State private var importError: String?

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
                if let exportText {
                    ShareLink(item: exportText, preview: SharePreview("持仓账本备份")) {
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
            } header: {
                Text("备份与恢复")
            } footer: {
                Text("备份为 JSON 文本，不含任何密钥；恢复前会先确认。")
            }

            Section("帮助") {
                NavigationLink("使用说明") { HelpView() }
                LabeledContent("Web 版本", value: "1.26（继续维护）")
            }

            Section {
                LabeledContent("版本", value: "2.0.0 (1)")
                LabeledContent("应用标识", value: "com.personal.stockledger")
            } footer: {
                Text("2.0 使用原生 SwiftUI 界面，账本保存在本机，不上传任何数据。")
            }
        }
        .navigationTitle("设置")
        .task { exportText = try? LedgerStore.exportText(state.ledger) }
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
                Text("账本保存在本机 Documents 目录，不注册账号、不上传数据，也不发送行情请求。备份导出为 JSON 文本，可自行保存到文件或云盘。")
            }
        }
        .navigationTitle("使用说明")
    }
}
