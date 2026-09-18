import SwiftUI

struct TradesView: View {
    @EnvironmentObject private var state: AppState
    let onAdd: () -> Void

    @State private var side: TradeSide?
    @State private var query = ""
    @State private var from = ""
    @State private var to = ""
    @State private var editing: Trade?

    private var result: Engine.RangeResult {
        Engine.range(state.ledger, from: from, to: to, side: side, query: query,
                     gains: state.summary.gains, ordered: state.orderedTrades)
    }

    var body: some View {
        let result = self.result
        return List {
            Section {
                Picker("买卖类型", selection: $side) {
                    Text("全部").tag(TradeSide?.none)
                    Text("买入").tag(TradeSide?.some(.buy))
                    Text("卖出").tag(TradeSide?.some(.sell))
                }
                .pickerStyle(.segmented)
            }

            Section("日期区间（美东）") {
                DateField(title: "起始日期", value: $from)
                DateField(title: "结束日期", value: $to)
                if !from.isEmpty || !to.isEmpty || side != nil || !query.isEmpty {
                    Button("清除筛选") { side = nil; from = ""; to = ""; query = "" }
                }
            }

            Section {
                let summary = result
                LabeledContent("范围内", value: "\(summary.list.count) 笔")
                LabeledContent("买入", value: "\(Fmt.quantity(summary.buyQuantity)) 股")
                LabeledContent("卖出", value: "\(Fmt.quantity(summary.sellQuantity)) 股")
                LabeledContent("手续费", value: Fmt.money(summary.fees))
                ProfitRow(label: "已实现收益", value: summary.hasRealized ? summary.realized : nil)
            } header: {
                Text("汇总")
            }

            Section("全部交易 \(state.ledger.trades.count)") {
                if result.list.isEmpty {
                    if state.ledger.trades.isEmpty {
                        Button("记录第一笔交易", action: onAdd)
                    } else {
                        Text("没有找到交易，试试其他条件。").foregroundStyle(.secondary)
                    }
                }
                ForEach(result.list) { trade in
                    Button { editing = trade } label: { row(trade) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", role: .destructive) { state.deleteTrade(trade.id) }
                        }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索代码或备注")
        .navigationTitle("交易记录")
        .sheet(item: $editing) { trade in
            TradeFormView(trade: trade).environmentObject(state)
        }
        .overlay(alignment: .bottom) {
            if state.undoTrade != nil {
                HStack {
                    Text("交易已保存")
                    Button("撤销新增") { state.undoLastTrade() }
                }
                .font(.footnote)
                .padding(10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        }
    }

    private func row(_ trade: Trade) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trade.symbol).font(.headline)
                Text(trade.side.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(trade.side == .buy ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
                if trade.source == "import" {
                    Text("CSV").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text(Fmt.money(trade.gross)).monospacedDigit()
            }
            HStack {
                Text("\(trade.date) · \(Fmt.quantity(trade.quantity)) 股 × \(Fmt.money(trade.price))")
                Spacer()
                Text("手续费 \(Fmt.money(trade.fee))")
            }
            .font(.caption).foregroundStyle(.secondary)
            if !trade.note.isEmpty {
                Text(trade.note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct DateField: View {
    let title: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            DatePicker("", selection: Binding(
                get: { DateFormatter.ledgerDate.date(from: value) ?? Date() },
                set: { value = DateFormatter.ledgerDate.string(from: $0) }
            ), in: ...Date(), displayedComponents: .date)
            .labelsHidden()
            if !value.isEmpty {
                Button { value = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .accessibilityLabel("清除\(title)")
            }
        }
    }
}

/// 记账表单的输入快照，用于判断“有未保存的修改”。
struct FormSnapshot: Equatable {
    var side: TradeSide = .buy
    var symbol = ""
    var date = Fmt.today
    var quantity = ""
    var price = ""
    var fee = "0"
    var note = ""
}

struct TradeFormView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let trade: Trade?

    @State private var side: TradeSide = .buy
    @State private var symbol = ""
    @State private var date = Fmt.today
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = "0"
    @State private var note = ""
    @State private var error: String?
    @State private var showingDiscard = false
    @State private var autoFee = ""
    @State private var snapshot = FormSnapshot()

    private var isEditing: Bool { trade != nil }
    private var available: Decimal {
        state.summary.open.first { $0.symbol == symbol.trimmingCharacters(in: .whitespaces).uppercased() }?.quantity ?? 0
    }

    /// 最近使用过的股票代码，最新的排前面。
    private var recentSymbols: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for trade in state.ledger.orderedTrades.reversed() {
            if seen.insert(trade.symbol).inserted { list.append(trade.symbol) }
            if list.count == 6 { break }
        }
        return list
    }

    private var current: FormSnapshot {
        FormSnapshot(side: side, symbol: symbol, date: date, quantity: quantity, price: price, fee: fee, note: note)
    }

    private var dirty: Bool { current != snapshot }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("方向", selection: $side) {
                        Text("买入").tag(TradeSide.buy)
                        Text("卖出").tag(TradeSide.sell)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("股票代码", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if !isEditing, !recentSymbols.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentSymbols, id: \.self) { item in
                                    Button(item) { symbol = item; applyRecentFee() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    DatePicker("交易日期（美东）", selection: Binding(
                        get: { DateFormatter.ledgerDate.date(from: date) ?? Date() },
                        set: { date = DateFormatter.ledgerDate.string(from: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                    TextField("成交股数", text: $quantity).keyboardType(.decimalPad)
                    TextField("成交单价（美元）", text: $price).keyboardType(.decimalPad)
                    TextField("手续费（美元）", text: $fee).keyboardType(.decimalPad)
                } footer: {
                    if side == .sell {
                        HStack {
                            Text("当前可卖 \(Fmt.quantity(available)) 股")
                            Spacer()
                            Button("一半") { fill(available / 2) }
                            Button("全部") { fill(available) }
                        }
                    }
                }
                Section("备注") {
                    TextField("选填", text: $note, axis: .vertical).lineLimit(2...4)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(isEditing ? "编辑交易" : "记录交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if dirty { showingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(symbol.isEmpty) }
            }
            .onAppear(perform: load)
            .onChange(of: symbol) { _ in applyRecentFee() }
            .alert("放弃未保存的修改？", isPresented: $showingDiscard) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive) { dismiss() }
            }
        }
    }

    private func load() {
        guard let trade else {
            snapshot = current
            return
        }
        side = trade.side
        symbol = trade.symbol
        date = trade.date
        quantity = Fmt.quantity(trade.quantity)
        price = Fmt.moneyPlain(trade.price)
        fee = Fmt.moneyPlain(trade.fee)
        note = trade.note
        snapshot = current
    }

    /// 沿用最近一笔手续费：优先同一股票，其次最近一笔；用户手动改过就不再覆盖。
    private func applyRecentFee() {
        guard !isEditing else { return }
        let target = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !target.isEmpty else { return }
        let history = state.ledger.orderedTrades.reversed()
        guard let match = history.first(where: { $0.symbol == target }) ?? history.first, match.fee > 0 else { return }
        let value = Fmt.moneyPlain(match.fee)
        if fee == "0" || fee == autoFee {
            fee = value
            autoFee = value
            snapshot = current
        }
    }

    private func fill(_ value: Decimal) {
        quantity = Fmt.quantity(value)
    }

    private func save() {
        do {
            let parsedQuantity = try LedgerValidation.positive(Decimal(string: quantity, locale: Locale(identifier: "en_US")) ?? -1, "成交股数")
            let parsedPrice = try LedgerValidation.positive(Decimal(string: price, locale: Locale(identifier: "en_US")) ?? -1, "成交单价")
            let parsedFee = try LedgerValidation.positive(Decimal(string: fee, locale: Locale(identifier: "en_US")) ?? 0, "手续费", allowZero: true)
            let trade = Trade(
                id: trade?.id ?? UUID(),
                sequence: trade?.sequence ?? 0,
                symbol: try LedgerValidation.symbol(symbol),
                side: side,
                date: try LedgerValidation.date(date),
                quantity: parsedQuantity,
                price: parsedPrice,
                fee: parsedFee,
                note: try LedgerValidation.note(note),
                source: trade?.source ?? "manual",
                externalId: trade?.externalId
            )
            state.saveTrade(trade)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
