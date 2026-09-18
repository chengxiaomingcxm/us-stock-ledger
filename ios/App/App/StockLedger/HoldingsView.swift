import SwiftUI

struct HoldingsView: View {
    @EnvironmentObject private var state: AppState
    let onAdd: () -> Void
    var onOpenSettings: () -> Void = {}

    @State private var detailSymbol: String?
    @State private var quoteSymbol: String?
    @AppStorage("backup.lastExport") private var lastExport = 0.0

    private var summary: LedgerSummary { state.summary }

    var body: some View {
        List {
            if !state.ledger.trades.isEmpty, BackupReminder.overdue(lastExport) {
                Section {
                    HStack(spacing: 10) {
                        Label(lastExport > 0 ? "距上次备份已超过 30 天" : "还没有导出过账本备份", systemImage: "clock.badge.exclamationmark")
                            .font(.footnote)
                        Spacer()
                        Button("去备份", action: onOpenSettings).font(.footnote)
                    }
                }
            }
            Section {
                TodayCard()
            }
            Section("持有收益") {
                ProfitRow(label: "浮动收益", value: summary.unrealized)
                LabeledContent("持仓成本", value: Fmt.money(summary.cost))
                ProfitRow(label: "已实现收益", value: summary.realized)
                ProfitRow(label: "累计投资收益", value: summary.totalProfit)
                if !summary.missing.isEmpty {
                    Label("\(summary.missing.count) 只持仓待报价", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Section("我的持仓") {
                if summary.open.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("从第一笔投资开始").font(.headline)
                        Text(state.ledger.trades.isEmpty ? "记录第一笔买入，自动计算成本与收益。" : "当前没有持仓。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("记录第一笔交易", action: onAdd)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(summary.open) { position in
                        Button { detailSymbol = position.symbol } label: { row(position) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("持仓账本")
        .sheet(item: Binding(get: { detailSymbol.map(SymbolBox.init) }, set: { detailSymbol = $0?.value })) { box in
            PositionDetailView(symbol: box.value, onEditQuote: { quoteSymbol = box.value })
                .environmentObject(state)
        }
        .sheet(item: Binding(get: { quoteSymbol.map(SymbolBox.init) }, set: { quoteSymbol = $0?.value })) { box in
            QuoteFormView(symbol: box.value)
                .environmentObject(state)
        }
    }

    private func row(_ position: Position) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(position.symbol).font(.headline)
                Text("\(Fmt.quantity(position.quantity)) 股 · 市值 \(Fmt.money(position.value))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(quoteLabel(position))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(position.unrealized.map { Fmt.percent($0 / max(position.cost, 1)) } ?? "—")
                    .font(.subheadline)
                AmountText(value: position.unrealized)
                    .font(.subheadline.weight(.semibold))
            }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(position.symbol)，\(Fmt.quantity(position.quantity)) 股，浮动收益 \(Fmt.signedMoney(position.unrealized))")
    }

    private func quoteLabel(_ position: Position) -> String {
        guard let quote = position.quote else { return "待报价" }
        let stale = Engine.isStaleQuote(quote) ? " · 较早" : ""
        return "\(quote.date)\(stale)"
    }
}

struct SymbolBox: Identifiable {
    let value: String
    var id: String { value }
}

struct TodayCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance.colors") private var colorPreference = "green-up"

    var body: some View {
        let result = state.displayReturn
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await state.refreshQuotes() }
                } label: {
                    if state.syncingQuotes {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("同步行情", systemImage: "arrow.clockwise")
                    }
                }
                .font(.footnote)
                .disabled(state.syncingQuotes || state.ledger.trades.isEmpty)
            }
            Text(result.pnl == nil ? "待补全" : Fmt.signedMoney(result.pnl))
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(profitColor(result.pnl))
            Text(result.caption).font(.footnote).foregroundStyle(.secondary)
            if let percent = result.percent {
                Text("较上一收盘 \(Fmt.percent(percent))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("持仓市值", value: Fmt.money(state.summary.value))
                .font(.footnote)
            ForEach(result.rows.filter { $0.reason != nil }) { row in
                Label("\(row.symbol)：\(row.reason ?? "")", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(state.quoteErrors.sorted { $0.key < $1.key }, id: \.key) { entry in
                Label("\(entry.key) 刷新失败：\(entry.value)", systemImage: "wifi.exclamationmark")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// 今日盈亏同样跟随涨跌配色设置，不用系统默认颜色。
    private func profitColor(_ value: Decimal?) -> Color {
        guard let value else { return .secondary }
        let colors = ThemeColors(redUp: colorPreference == "red-up")
        if value > 0 { return colors.gain(scheme) }
        if value < 0 { return colors.loss(scheme) }
        return .primary
    }
}

struct PositionDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let symbol: String
    var onEditQuote: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                if let position = state.summary.open.first(where: { $0.symbol == symbol }) {
                    Section {
                        ProfitRow(label: "浮动收益", value: position.unrealized)
                        LabeledContent("持有股数", value: Fmt.quantity(position.quantity))
                        LabeledContent("持仓市值", value: Fmt.money(position.value))
                        LabeledContent("平均成本", value: Fmt.money(position.average))
                        LabeledContent("持仓成本", value: Fmt.money(position.cost))
                    }
                    Section("参考股价") {
                        LabeledContent("报价", value: position.quote.map { Fmt.money($0.price) } ?? "待报价")
                        LabeledContent("报价日期", value: position.quote?.date ?? "—")
                        LabeledContent("报价来源", value: position.quote?.sourceLabel ?? "—")
                        if let quote = position.quote, Engine.isStaleQuote(quote) {
                            Label("报价较早（\(quote.date)），可用下方按钮同步最新行情。", systemImage: "clock")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let previous = state.previousClose[position.symbol] {
                            LabeledContent("上一收盘", value: "\(Fmt.money(previous))\(state.previousCloseDates[position.symbol].map { "（\($0)）" } ?? "")")
                        }
                        Button("更新股价", action: onEditQuote)
                        Button("同步行情") { Task { await state.refreshQuotes() } }
                            .disabled(state.syncingQuotes)
                    }
                    Section("相关交易") {
                        let related = state.ledger.trades.filter { $0.symbol == symbol }
                            .sorted { $0.date == $1.date ? $0.sequence > $1.sequence : $0.date > $1.date }
                        if related.isEmpty {
                            Text("暂无该股票的交易记录。").foregroundStyle(.secondary)
                        } else {
                            ForEach(related) { trade in
                                LabeledContent("\(trade.date) · \(trade.side.label) \(Fmt.quantity(trade.quantity)) 股",
                                               value: Fmt.money(trade.gross))
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已无持仓").font(.headline)
                        Text("该股票已全部卖出。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(symbol)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct QuoteFormView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let symbol: String

    @State private var price = ""
    @State private var date = Fmt.today
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("股价（美元）", text: $price).keyboardType(.decimalPad)
                    DatePicker("报价日期（美东）", selection: Binding(
                        get: { DateFormatter.ledgerDate.date(from: date) ?? Date() },
                        set: { date = DateFormatter.ledgerDate.string(from: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("更新 \(symbol) 股价")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }

    private func save() {
        guard let value = Decimal(string: price.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US")), value > 0 else {
            error = "请填写大于 0 的股价。"
            return
        }
        state.setQuote(symbol: symbol, price: value, date: date)
        dismiss()
    }
}

extension DateFormatter {
    static let ledgerDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
