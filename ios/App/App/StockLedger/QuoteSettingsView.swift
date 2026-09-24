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
                Picker(L10n.tr("价格显示"), selection: $mode) {
                    Text(L10n.tr("自动（休市用收盘）")).tag("auto")
                    Text(L10n.tr("最近收盘价")).tag("close")
                    Text(L10n.tr("所选接口最新报价")).tag("live")
                }
                Picker(L10n.tr("盘中行情来源"), selection: $provider) {
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
                Text(L10n.tr("显示与来源"))
            } footer: {
                Text(L10n.tr("收盘价使用专用日线与备用来源；盘中报价使用所选接口。更改会立即保存。"))
            }

            Section {
                NavigationLink(L10n.tr("API 设置")) { ApiSettingsView() }
                LabeledContent(L10n.tr("上次同步"), value: state.lastSyncedAt.map { Fmt.clock($0) } ?? L10n.tr("尚未同步"))
                Button {
                    Task { await state.refreshMarketData() }
                } label: {
                    if state.syncingQuotes || state.syncingHistory {
                        Label(L10n.tr("正在同步…"), systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label(L10n.tr("立即同步持仓行情"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(state.syncingQuotes || state.syncingHistory || state.demo)
                ForEach(state.quoteErrors.sorted { $0.key < $1.key }, id: \.key) { entry in
                    Label(L10n.tr("{}：{}", entry.key, entry.value), systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.tr("同步"))
            } footer: {
                Text(L10n.tr("API Key 保存在系统钥匙串，仅在本机发起行情请求；不上传账本，也不随备份导出。"))
            }
        }
        .navigationTitle(L10n.tr("行情来源"))
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
    @State private var tiingoKey = ""
    @State private var interval = 60
    @State private var failure: String?
    @State private var saved = false

    private var provider: QuoteProvider { state.quoteSettings.provider }

    var body: some View {
        List {
            Section {
                SecureField(L10n.tr("Tiingo 日线 API Key（建议填写）"), text: $tiingoKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let destination = URL(string: "https://api.tiingo.com/account/token") {
                    Link(L10n.tr("获取 Tiingo API Key"), destination: destination)
                }
            } header: {
                Text(L10n.tr("历史收盘价"))
            } footer: {
                Text(L10n.tr("填写后优先使用 Tiingo 日线；失败时自动改用 Yahoo，再用 Nasdaq 补明确缺口。未填写也可继续使用免费备用来源。"))
            }

            Section {
                if provider == .yahoo {
                    Text(L10n.tr("Yahoo 收盘价不需要 API Key。"))
                } else {
                    if provider == .custom {
                        TextField(L10n.tr("接口地址，例如 https://api.example.com/quote/{symbol}"), text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    SecureField(L10n.tr(provider == .finnhub ? "Finnhub API Key" : "Bearer Token（可留空）"), text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker(L10n.tr("刷新间隔"), selection: $interval) {
                    Text(L10n.tr("仅手动")).tag(0)
                    Text(L10n.tr("60 秒")).tag(60)
                    Text(L10n.tr("5 分钟")).tag(300)
                }
            } header: {
                Text(L10n.tr("接口与密钥"))
            } footer: {
                Text(L10n.tr("密钥只保存在本机系统钥匙串，不写入账本，也不随备份导出。"))
            }

            Section {
                Button(L10n.tr("保存")) { save() }
                if saved { Label(L10n.tr("已保存"), systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
        }
        .navigationTitle(L10n.tr("API 设置"))
        .task { load() }
    }

    private func load() {
        let settings = state.quoteSettings
        url = settings.url
        key = settings.key
        tiingoKey = settings.tiingoKey ?? ""
        interval = settings.interval
    }

    private func save() {
        failure = nil
        saved = false
        do {
            var settings = state.quoteSettings
            settings.url = url
            settings.key = key
            settings.tiingoKey = tiingoKey
            settings.interval = interval
            try state.saveQuoteSettings(settings)
            saved = true
        } catch {
            failure = error.localizedDescription
        }
    }
}
