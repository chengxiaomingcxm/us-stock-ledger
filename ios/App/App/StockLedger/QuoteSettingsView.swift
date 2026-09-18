import SwiftUI

// 行情来源：设置里的一级页面，选择价格显示方式与盘中接口。
// API Key、接口地址和刷新间隔在二级「API 设置」里配置。

struct QuoteSourceView: View {
    @EnvironmentObject private var state: AppState

    @State private var provider: QuoteProvider = .yahoo
    @State private var mode = "auto"
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Picker("价格显示", selection: $mode) {
                    Text("自动（休市用收盘）").tag("auto")
                    Text("最近收盘价").tag("close")
                    Text("所选接口最新报价").tag("live")
                }
                Picker("盘中行情来源", selection: $provider) {
                    ForEach(QuoteProvider.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                Text(provider.detail).font(.caption).foregroundStyle(.secondary)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("显示与来源")
            } footer: {
                Text("收盘价使用 Yahoo 已完成日线；盘中报价使用所选接口。更改会立即保存。")
            }

            Section {
                NavigationLink("API 设置") { ApiSettingsView() }
                LabeledContent("上次同步", value: state.lastSyncedAt.map { Fmt.clock($0) } ?? "尚未同步")
                Button {
                    Task { await state.refreshQuotes() }
                } label: {
                    if state.syncingQuotes {
                        Label("正在同步…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("立即同步持仓行情", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(state.syncingQuotes)
                ForEach(state.quoteErrors.sorted { $0.key < $1.key }, id: \.key) { entry in
                    Label("\(entry.key)：\(entry.value)", systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("同步")
            } footer: {
                Text("API Key 保存在系统钥匙串，仅在本机发起行情请求；不上传账本，也不随备份导出。")
            }
        }
        .navigationTitle("行情来源")
        .task { load() }
        .onChange(of: provider) { _ in save() }
        .onChange(of: mode) { _ in save() }
    }

    private func load() {
        provider = state.quoteSettings.provider
        mode = state.quoteSettings.priceMode ?? "auto"
    }

    private func save() {
        failure = nil
        do {
            var settings = state.quoteSettings
            settings.provider = provider
            settings.priceMode = mode
            try state.saveQuoteSettings(settings)
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct ApiSettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var url = ""
    @State private var key = ""
    @State private var interval = 60
    @State private var failure: String?
    @State private var saved = false

    private var provider: QuoteProvider { state.quoteSettings.provider }

    var body: some View {
        List {
            Section {
                if provider == .yahoo {
                    Text("Yahoo 收盘价不需要 API Key。")
                } else {
                    if provider == .custom {
                        TextField("接口地址，例如 https://api.example.com/quote/{symbol}", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    SecureField(provider == .finnhub ? "Finnhub API Key" : "Bearer Token（可留空）", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("刷新间隔", selection: $interval) {
                    Text("仅手动").tag(0)
                    Text("60 秒").tag(60)
                    Text("5 分钟").tag(300)
                }
            } header: {
                Text("接口与密钥")
            } footer: {
                Text("密钥只保存在本机系统钥匙串，不写入账本，也不随备份导出。")
            }

            Section {
                Button("保存") { save() }
                if saved { Label("已保存", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
        }
        .navigationTitle("API 设置")
        .task { load() }
    }

    private func load() {
        let settings = state.quoteSettings
        url = settings.url
        key = settings.key
        interval = settings.interval
    }

    private func save() {
        failure = nil
        saved = false
        do {
            var settings = state.quoteSettings
            settings.url = url
            settings.key = key
            settings.interval = interval
            try state.saveQuoteSettings(settings)
            saved = true
        } catch {
            failure = error.localizedDescription
        }
    }
}
