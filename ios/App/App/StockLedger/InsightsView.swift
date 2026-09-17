import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var state: AppState

    @State private var cashForm: CashFormMode?
    @State private var editingRecord: CashRecord?

    private var summary: LedgerSummary { state.summary }
    private var cash: CashTotals { state.cashTotals }

    var body: some View {
        List {
            Section("累计投资收益") {
                AmountText(value: summary.totalProfit)
                    .font(.largeTitle.weight(.bold))
                Text("已实现收益 + 当前持仓浮动收益（证券口径）")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("已实现收益", value: Fmt.signedMoney(summary.realized))
                LabeledContent("浮动收益", value: Fmt.signedMoney(summary.unrealized))
                LabeledContent("分红净额（扣税）", value: Fmt.signedMoney(cash.dividend - cash.tax))
                LabeledContent("账户费用", value: Fmt.signedMoney(-cash.fee))
                LabeledContent("账户总收益", value: Fmt.signedMoney(summary.totalProfit.map { $0 + cash.investNetAll }))
                    .font(.headline)
                Text("入金出金不计入收益；今日盈亏与收益日历只统计证券。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("现金账本") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前现金余额").font(.footnote).foregroundStyle(.secondary)
                    Text(cash.balance == nil ? "待设置期初" : Fmt.money(cash.balance))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    if let opening = state.ledger.opening {
                        Text("期初 \(opening.date) 开始前 · \(opening.note.isEmpty ? "—" : opening.note)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("设置期初余额") { cashForm = .opening }
                    }
                }
                LabeledContent("期初余额", value: state.ledger.opening.map { Fmt.money($0.amount) } ?? "未设置")
                LabeledContent("累计入金", value: Fmt.money(cash.deposit))
                LabeledContent("累计出金", value: Fmt.money(-cash.withdraw))
                LabeledContent("分红到账（扣税）", value: Fmt.money(cash.dividend - cash.tax))
                LabeledContent("预扣税费", value: Fmt.money(-cash.tax))
                LabeledContent("账户费用", value: Fmt.money(-cash.fee))
                LabeledContent("买入支出（含费）", value: Fmt.money(-cash.buyOut))
                LabeledContent("卖出收入（扣费）", value: Fmt.money(cash.sellIn))
                LabeledContent("买卖净现金流", value: Fmt.signedMoney(cash.tradeNet))
                if cash.excludedTrades > 0 || cash.excludedRecords > 0 {
                    Text("期初前有 \(cash.excludedTrades) 笔交易、\(cash.excludedRecords) 笔资金记录，已含在期初余额中，仅保留备查。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("期初") { cashForm = .opening }
                    Spacer()
                    Button("入金") { cashForm = .new(.deposit) }
                    Button("出金") { cashForm = .new(.withdraw) }
                    Button("分红") { cashForm = .new(.dividend) }
                    Button("费用") { cashForm = .new(.fee) }
                }
                .font(.footnote)
            }

            if !state.ledger.cash.isEmpty {
                Section("现金记录") {
                    ForEach(state.ledger.orderedCash.reversed()) { record in
                        Button { editingRecord = record } label: { cashRow(record) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("删除", role: .destructive) { state.deleteCash(record.id) }
                            }
                    }
                }
            }

            if !summary.positions.isEmpty {
                Section("各股票已实现收益") {
                    ForEach(summary.positions) { position in
                        LabeledContent("\(position.symbol) \(position.quantity == 0 ? "（已平仓）" : "")",
                                       value: Fmt.signedMoney(position.realized))
                    }
                }
            }
        }
        .navigationTitle("收益分析")
        .sheet(item: $cashForm) { mode in
            CashFormView(mode: mode).environmentObject(state)
        }
        .sheet(item: $editingRecord) { record in
            CashFormView(mode: .edit(record)).environmentObject(state)
        }
    }

    private func cashRow(_ record: CashRecord) -> some View {
        HStack {
            Text(record.kind.label).font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.signedMoney(record.net)).monospacedDigit()
                Text("\(record.date)\(record.symbol.map { " · \($0)" } ?? "")\(record.note.isEmpty ? "" : " · \(record.note)")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.kind.label) \(Fmt.signedMoney(record.net)) \(record.date)")
    }
}

enum CashFormMode: Identifiable {
    case opening
    case new(CashKind)
    case edit(CashRecord)

    var id: String {
        switch self {
        case .opening: return "opening"
        case .new(let kind): return "new-\(kind.rawValue)"
        case .edit(let record): return "edit-\(record.id.uuidString)"
        }
    }
}

struct CashFormView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: CashFormMode

    @State private var kind: CashKind = .deposit
    @State private var date = Fmt.today
    @State private var amount = ""
    @State private var tax = ""
    @State private var symbol = ""
    @State private var note = ""
    @State private var error: String?

    private var isOpening: Bool { if case .opening = mode { return true }; return false }

    var body: some View {
        NavigationStack {
            Form {
                if isOpening {
                    Section {
                        Text("期初余额是“期初日期当天开始前”的现金。该日期当天及之后的入金、出金、分红、费用和股票买卖会联动余额；之前的记录视为已包含在期初余额中，保留备查、不重复计入。允许为零，不支持负数。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("类型", selection: $kind) {
                            ForEach(CashKind.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }
                Section {
                    DatePicker("日期（美东）", selection: Binding(
                        get: { DateFormatter.ledgerDate.date(from: date) ?? Date() },
                        set: { date = DateFormatter.ledgerDate.string(from: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                    TextField("金额（美元）", text: $amount).keyboardType(.decimalPad)
                    if kind == .dividend && !isOpening {
                        TextField("预扣税费（选填）", text: $tax).keyboardType(.decimalPad)
                    }
                    if (kind == .dividend || kind == .fee) && !isOpening {
                        TextField("股票代码（选填）", text: $symbol)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    TextField("备注（选填）", text: $note, axis: .vertical).lineLimit(1...3)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private var title: String {
        switch mode {
        case .opening: return state.ledger.opening == nil ? "设置期初余额" : "修改期初余额"
        case .new: return "记录资金"
        case .edit: return "编辑资金记录"
        }
    }

    private func load() {
        switch mode {
        case .opening:
            if let opening = state.ledger.opening {
                date = opening.date
                amount = Fmt.moneyPlain(opening.amount)
                note = opening.note
            }
        case .new(let value):
            kind = value
        case .edit(let record):
            kind = record.kind
            date = record.date
            amount = Fmt.moneyPlain(record.amount)
            tax = record.tax.map(Fmt.moneyPlain) ?? ""
            symbol = record.symbol ?? ""
            note = record.note
        }
    }

    private func save() {
        do {
            let parsedAmount = try LedgerValidation.positive(Decimal(string: amount, locale: Locale(identifier: "en_US")) ?? -1, isOpening ? "期初余额" : "金额", allowZero: isOpening)
            let parsedDate = try LedgerValidation.date(date)
            if isOpening {
                state.setOpening(CashOpening(amount: parsedAmount, date: parsedDate, note: try LedgerValidation.note(note)))
                dismiss()
                return
            }
            var parsedTax: Decimal?
            if kind == .dividend, !tax.isEmpty {
                let value = try LedgerValidation.positive(Decimal(string: tax, locale: Locale(identifier: "en_US")) ?? -1, "税费", allowZero: true)
                if value > parsedAmount { throw LedgerError.message("税费不能超过分红金额。") }
                parsedTax = value
            }
            var parsedSymbol: String?
            if kind == .dividend || kind == .fee, !symbol.trimmingCharacters(in: .whitespaces).isEmpty {
                parsedSymbol = try LedgerValidation.symbol(symbol)
            }
            let existing = if case .edit(let record) = mode { record } else { nil }
            state.saveCash(CashRecord(
                id: existing?.id ?? UUID(),
                sequence: existing?.sequence ?? 0,
                date: parsedDate,
                kind: kind,
                amount: parsedAmount,
                tax: parsedTax,
                symbol: parsedSymbol,
                note: try LedgerValidation.note(note),
                source: existing?.source ?? "manual",
                externalId: existing?.externalId
            ))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
