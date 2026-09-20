import SwiftUI

struct TradesView: View {
    @EnvironmentObject private var state: AppState
    let onAdd: () -> Void

    @State private var side: TradeSide?
    @State private var query = ""
    @State private var from = ""
    @State private var to = ""
    @State private var editing: Trade?
    @State private var failure: String?

    private var result: Engine.RangeResult {
        Engine.range(state.ledger, from: from, to: to, side: side, query: query,
                     gains: state.summary.gains, ordered: state.orderedTrades)
    }

    /// 有任何筛选条件时为真；表头计数与「清除筛选」按钮共用，避免两处条件各写一遍。
    private var hasFilter: Bool { !from.isEmpty || !to.isEmpty || side != nil || !query.isEmpty }

    var body: some View {
        let result = self.result
        return List {
            Section {
                Picker(L10n.tr("买卖类型"), selection: $side) {
                    Text(L10n.tr("全部")).tag(TradeSide?.none)
                    Text(L10n.tr("买入")).tag(TradeSide?.some(.buy))
                    Text(L10n.tr("卖出")).tag(TradeSide?.some(.sell))
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.tr("日期区间（美东）")) {
                DateField(title: L10n.tr("起始日期"), value: $from)
                DateField(title: L10n.tr("结束日期"), value: $to)
                // 区间写反时结果必然是空列表，不提示会被误读成「筛选坏了」。
                if !from.isEmpty, !to.isEmpty, from > to {
                    Text(L10n.tr("起始日期晚于结束日期，请调整。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if hasFilter {
                    Button(L10n.tr("清除筛选")) { side = nil; from = ""; to = ""; query = "" }
                }
            }

            Section {
                let summary = result
                // 口径（产品定义）：金额是 Σ(股数 × 成交价)，不含手续费；手续费单独一行，不重复计入金额。
                LabeledContent(L10n.tr("范围内"), value: "\(summary.list.count) \(L10n.tr("笔"))")
                LabeledContent(L10n.tr("买入"), value: "\(summary.buyCount) \(L10n.tr("笔"))")
                LabeledContent(L10n.tr("卖出"), value: "\(summary.sellCount) \(L10n.tr("笔"))")
                LabeledContent(L10n.tr("买入金额"), value: Fmt.money(summary.buyAmount))
                LabeledContent(L10n.tr("卖出金额"), value: Fmt.money(summary.sellAmount))
                LabeledContent(L10n.tr("手续费合计"), value: Fmt.money(summary.fees))
                ProfitRow(label: L10n.tr("已实现收益"), value: summary.hasRealized ? summary.realized : nil)
            } header: {
                Text(L10n.tr("汇总"))
            }

            // 表头必须反映「下面列的是什么」：有筛选时用过滤后的计数，
            // 否则未过滤的全量计数会让人以为筛选没生效。汇总与列表本就用同一份 result。
            Section(hasFilter
                    ? "\(L10n.tr("范围内")) \(result.list.count) \(L10n.tr("笔"))"
                    : "\(L10n.tr("全部交易")) \(state.ledger.trades.count)") {
                if result.list.isEmpty {
                    if state.ledger.trades.isEmpty {
                        Button(L10n.tr("记录第一笔交易"), action: onAdd)
                    } else {
                        Text(L10n.tr("没有找到交易，试试其他条件。")).foregroundStyle(.secondary)
                    }
                }
                ForEach(result.list) { trade in
                    Button { editing = trade } label: { row(trade) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(L10n.tr("删除"), role: .destructive) {
                                if !state.deleteTrade(trade.id) { failure = state.errorMessage ?? L10n.tr("操作失败，账本未改变。") }
                            }
                        }
                }
            }
        }
        .searchable(text: $query, prompt: L10n.tr("搜索代码或备注"))
        .navigationTitle(L10n.tr("交易记录"))
        // 示例模式只读，不摆一个按下去只会报错的入口。
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !state.demo {
                    Button(action: onAdd) { Image(systemName: "plus") }
                        .accessibilityLabel(L10n.tr("记一笔"))
                }
            }
        }
        .sheet(item: $editing) { trade in
            TradeFormView(trade: trade).environmentObject(state)
        }
        .alert(L10n.tr("操作未完成"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L10n.tr("好"), role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        // 用 safeAreaInset 而不是 overlay：它参与布局，列表会自动留出这块空间。
        // 这条撤销提示没有超时，会一直留到用户撤销或删掉那笔交易——用 overlay 会长期盖住最后一行。
        .safeAreaInset(edge: .bottom) {
            if state.undoTrade != nil {
                HStack {
                    Text(L10n.tr("交易已保存"))
                    Button(L10n.tr("撤销新增")) {
                        if !state.undoLastTrade() { failure = state.errorMessage ?? L10n.tr("操作失败，账本未改变。") }
                    }
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
                Text("\(trade.date) · \(Fmt.quantity(trade.quantity)) \(L10n.tr("股")) × \(Fmt.money(trade.price))")
                Spacer()
                Text("\(L10n.tr("手续费")) \(Fmt.money(trade.fee))")
            }
            .font(.caption).foregroundStyle(.secondary)
            // 结单导入的系统说明按结构化字段重建为当前语言；不改持久化数据。
            if !Fmt.tradeNote(trade).isEmpty {
                Text(Fmt.tradeNote(trade)).font(.caption).foregroundStyle(.secondary)
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
                    .accessibilityLabel(L10n.tr("清除 {}", title))
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
                    Picker(L10n.tr("方向"), selection: $side) {
                        Text(L10n.tr("买入")).tag(TradeSide.buy)
                        Text(L10n.tr("卖出")).tag(TradeSide.sell)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField(L10n.tr("股票代码"), text: $symbol)
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
                    DatePicker(L10n.tr("交易日期（美东）"), selection: Binding(
                        get: { DateFormatter.ledgerDate.date(from: date) ?? Date() },
                        set: { date = DateFormatter.ledgerDate.string(from: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                    TextField(L10n.tr("成交股数"), text: $quantity).keyboardType(.decimalPad)
                    TextField(L10n.tr("成交单价（美元）"), text: $price).keyboardType(.decimalPad)
                    TextField(L10n.tr("手续费（美元）"), text: $fee).keyboardType(.decimalPad)
                } footer: {
                    if side == .sell {
                        HStack {
                            Text("\(L10n.tr("当前可卖")) \(Fmt.quantity(available)) \(L10n.tr("股"))")
                            Spacer()
                            Button(L10n.tr("一半")) { fill(available / 2) }
                            Button(L10n.tr("全部")) { fill(available) }
                        }
                    }
                }
                Section(L10n.tr("备注")) {
                    TextField(L10n.tr("选填"), text: $note, axis: .vertical).lineLimit(2...4)
                }
                if let error { Text(L10n.tr(error)).foregroundStyle(.red) }
            }
            .navigationTitle(L10n.tr(isEditing ? "编辑交易" : "记录交易"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("取消")) { if dirty { showingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) { save() }.disabled(symbol.isEmpty) }
            }
            .onAppear(perform: load)
            .onChange(of: symbol) { _ in applyRecentFee() }
            .alert(L10n.tr("放弃未保存的修改？"), isPresented: $showingDiscard) {
                Button(L10n.tr("继续编辑"), role: .cancel) {}
                Button(L10n.tr("放弃"), role: .destructive) { dismiss() }
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
            let parsedQuantity = try LedgerValidation.positive(Decimal(string: quantity, locale: Locale(identifier: "en_US")) ?? -1, L10n.tr("成交股数"))
            let parsedPrice = try LedgerValidation.positive(Decimal(string: price, locale: Locale(identifier: "en_US")) ?? -1, L10n.tr("成交单价"))
            let parsedFee = try LedgerValidation.positive(Decimal(string: fee, locale: Locale(identifier: "en_US")) ?? 0, L10n.tr("手续费"), allowZero: true)
            var updated = Trade(
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
            if let original = trade,
               original.symbol == updated.symbol, original.side == updated.side,
               original.date == updated.date, original.quantity == updated.quantity,
               original.price == updated.price, original.fee == updated.fee {
                updated.settlementAmount = original.settlementAmount
                updated.settlementDate = original.settlementDate
            }
            guard state.saveTrade(updated) else { throw LedgerError.message(state.errorMessage ?? L10n.tr("保存失败")) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
