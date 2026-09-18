import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var state: AppState

    @State private var cashForm: CashFormMode?
    @State private var editingRecord: CashRecord?

    private var summary: LedgerSummary { state.summary }
    private var cash: CashTotals { state.cashTotals }

    var body: some View {
        let days = state.dayReturns
        return List {
            Section("累计投资收益") {
                AmountText(value: summary.totalProfit)
                    .font(.largeTitle.weight(.bold))
                Text("已实现收益 + 当前持仓浮动收益（证券口径）")
                    .font(.footnote).foregroundStyle(.secondary)
                ProfitRow(label: "已实现收益", value: summary.realized)
                ProfitRow(label: "浮动收益", value: summary.unrealized)
                ProfitRow(label: "分红净额（扣税）", value: cash.dividend - cash.tax)
                ProfitRow(label: "账户费用", value: -cash.fee)
                ProfitRow(label: "账户总收益", value: summary.totalProfit.map { $0 + cash.investNetAll })
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
                    }
                }
                Button {
                    cashForm = .opening
                } label: {
                    HStack {
                        Text(state.ledger.opening == nil ? "设置期初余额" : "修改期初余额")
                        Spacer()
                        Text(state.ledger.opening.map { Fmt.money($0.amount) } ?? "未设置")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                if state.ledger.opening != nil {
                    Text("期初余额是「期初日期当天开始前」的现金；录错可点上方一行修改，或清除后重新设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("累计入金", value: Fmt.money(cash.deposit))
                LabeledContent("累计出金", value: Fmt.money(-cash.withdraw))
                ProfitRow(label: "分红到账（扣税）", value: cash.dividend - cash.tax)
                ProfitRow(label: "已知预扣税费", value: -cash.tax)
                if state.derived.unknownDividendTax > 0 {
                    Text("\(state.derived.unknownDividendTax) 笔分红按实际到账记账，预扣税未披露；不代表免税。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProfitRow(label: "账户费用", value: -cash.fee)
                LabeledContent("买入支出（含费）", value: Fmt.money(-cash.buyOut))
                LabeledContent("卖出收入（扣费）", value: Fmt.money(cash.sellIn))
                LabeledContent("买卖净现金流", value: Fmt.signedMoney(cash.tradeNet))
                if cash.excludedTrades > 0 || cash.excludedRecords > 0 {
                    Text("期初前有 \(cash.excludedTrades) 笔交易、\(cash.excludedRecords) 笔资金记录，已含在期初余额中，仅保留备查。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("入金") { cashForm = .new(.deposit) }
                    Button("出金") { cashForm = .new(.withdraw) }
                    Button("分红") { cashForm = .new(.dividend) }
                    Button("费用") { cashForm = .new(.fee) }
                }
                .font(.footnote)
            }

            if !state.orderedCash.isEmpty {
                Section("现金记录") {
                    ForEach(state.orderedCash.reversed()) { record in
                        Button { editingRecord = record } label: { cashRow(record) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("删除", role: .destructive) { state.deleteCash(record.id) }
                            }
                    }
                }
            }

            Section {
                ReturnCalendar(data: state.insights).equatable()
            } header: {
                HStack {
                    Text("收益日历")
                    Spacer()
                    if state.syncingHistory {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("同步历史") { Task { await state.syncHistory() } }
                            .font(.footnote)
                            .disabled(state.ledger.trades.isEmpty)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("按上一交易日收盘与当日收盘计算每日收益，重放当前账本；缺少收盘价的交易日标记为待补全，不以零代替。历史行情来自 Yahoo 日线，与最新报价来源设置独立。")
                    if let synced = state.historySyncedAt {
                        Text("上次同步：\(Fmt.clock(synced))")
                    }
                    ForEach(state.historyErrors.sorted { $0.key < $1.key }, id: \.key) { entry in
                        Text("\(entry.key)：\(entry.value)")
                    }
                }
            }

            if !days.isEmpty {
                Section("累计收益曲线") {
                    CumulativeProfitChart(data: state.insights).equatable()
                }
            }

            if !summary.positions.isEmpty {
                Section("各股票已实现收益") {
                    ForEach(summary.positions) { position in
                        ProfitRow(label: "\(position.symbol) \(position.quantity == 0 ? "（已平仓）" : "")",
                                  value: position.realized)
                    }
                }
            }
        }
        .navigationTitle("收益分析")
        .safeAreaInset(edge: .top) {
            if state.rebuilding { ProgressView("正在更新账本统计…").padding(8).frame(maxWidth: .infinity).background(.regularMaterial) }
        }
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
                    if state.ledger.opening != nil {
                        Section {
                            Button("清除期初余额", role: .destructive) {
                                state.clearOpening()
                                dismiss()
                            }
                        } footer: {
                            Text("清除后现金余额显示为待设置期初；已记录的入金、出金、分红和费用不受影响，可重新填写期初。")
                        }
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
            var existing: CashRecord?
            if case .edit(let record) = mode { existing = record }
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

// MARK: - 收益日历

struct ReturnCalendar: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.data.revision == rhs.data.revision }
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance.colors") private var colorPreference = "green-up"

    let data: InsightsPresentation

    @State private var month = ""
    @State private var selected: Engine.DayReturn?

    private var colors: ThemeColors { ThemeColors(redUp: colorPreference == "red-up") }
    private var months: [String] { data.months }
    private var stats: Engine.MonthStats { data.calendar[month]?.stats ?? Engine.MonthStats() }
    private typealias Cell = InsightsPresentation.Cell
    private var cells: [Cell] { data.calendar[month]?.cells ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if months.isEmpty {
                Text("尚未同步历史行情。同步后可查看每日与月度收益。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button {
                        step(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(monthIndex <= 0)
                    .accessibilityLabel("上一个月")

                    Spacer()
                    Text(month.isEmpty ? "—" : month)
                        .font(.headline).monospacedDigit()
                    Spacer()

                    Button {
                        step(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(monthIndex >= months.count - 1)
                    .accessibilityLabel("下一个月")
                }
                ProfitRow(label: "本月收益", value: stats.profit)
                    .font(.headline)
                LabeledContent("交易日", value: "\(stats.rows.count) 天")
                if stats.missing > 0 {
                    Text("\(stats.missing) 天收盘价不完整，未计入月度合计。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                    ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { label in
                        Text(label).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(cells) { cell in
                        dayCell(cell)
                    }
                }

                HStack(spacing: 12) {
                    legend(color: colors.gain(scheme), text: "盈利")
                    legend(color: colors.loss(scheme), text: "亏损")
                    Label("待补全", systemImage: "circle.dotted").font(.caption2).foregroundStyle(.secondary)
                }
                Text("每天格子里显示当日收益金额，点按查看按股票的明细。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { if month.isEmpty { month = months.last ?? "" } }
        .onChange(of: months) { value in if !value.contains(month) { month = value.last ?? "" } }
        .sheet(item: $selected) { row in
            DayReturnDetail(row: row)
        }
    }

    private var monthIndex: Int { months.firstIndex(of: month) ?? months.count - 1 }

    private func step(_ delta: Int) {
        let next = monthIndex + delta
        guard months.indices.contains(next) else { return }
        month = months[next]
    }

    @ViewBuilder
    private func dayCell(_ cell: Cell) -> some View {
        if let day = cell.day {
            Button {
                if let row = cell.row { selected = row }
            } label: {
                VStack(spacing: 1) {
                    Text("\(day)").font(.caption2).monospacedDigit()
                    Text(amountText(cell.row))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(amountColor(cell.row))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(background(for: cell.row), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(cell.row == nil)
            .accessibilityLabel(accessibilityLabel(cell))
        } else {
            Color.clear.frame(height: 40)
        }
    }

    private func amountText(_ row: Engine.DayReturn?) -> String {
        guard let row else { return "" }
        guard let profit = row.profit else { return "待补" }
        return Fmt.compactSigned(profit)
    }

    private func amountColor(_ row: Engine.DayReturn?) -> Color {
        guard let profit = row?.profit else { return .secondary }
        if profit > 0 { return colors.gain(scheme) }
        if profit < 0 { return colors.loss(scheme) }
        return .secondary
    }

    private func background(for row: Engine.DayReturn?) -> Color {
        guard let profit = row?.profit, profit != 0 else { return .clear }
        return (profit > 0 ? colors.gain(scheme) : colors.loss(scheme)).opacity(0.15)
    }

    private func accessibilityLabel(_ cell: Cell) -> String {
        guard let day = cell.day else { return "" }
        guard let row = cell.row else { return "\(month)-\(day) 非交易日" }
        return "\(row.date) \(row.profit == nil ? "待补全" : Fmt.signedMoney(row.profit))"
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct DayReturnDetail: View {
    @Environment(\.dismiss) private var dismiss
    let row: Engine.DayReturn

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("日期", value: row.date)
                    LabeledContent("上一交易日", value: row.previous ?? "—")
                    ProfitRow(label: "当日收益", value: row.profit)
                    LabeledContent("累计资产", value: Fmt.money(row.cumulative))
                }
                if !row.contributions.isEmpty {
                    Section("按股票") {
                        ForEach(row.contributions) { item in
                            if let profit = item.profit {
                                ProfitRow(label: item.symbol, value: profit)
                            } else {
                                LabeledContent(item.symbol, value: item.reason ?? "待补全")
                            }
                        }
                    }
                }
                if !row.missing.isEmpty {
                    Section("缺失行情") {
                        ForEach(row.missing, id: \.self) { text in
                            Text(text).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(row.date)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

// MARK: - 累计收益曲线

/// 按累计收益画曲线，使用预计算的有限刻度与零轴。
struct CumulativeProfitChart: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.data.revision == rhs.data.revision }
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance.colors") private var colorPreference = "green-up"

    let data: InsightsPresentation
    private var points: [(date: String, value: Decimal)] { data.points }
    private var missingDays: Int { data.missingDays }
    private var highest: Decimal { data.highest }
    private var lowest: Decimal { data.lowest }
    private var colors: ThemeColors { ThemeColors(redUp: colorPreference == "red-up") }
    private var lineColor: Color { (points.last?.value ?? 0) >= 0 ? colors.gain(scheme) : colors.loss(scheme) }

    var body: some View {
        if points.count < 2 {
            Text("同步两个以上交易日后可查看曲线。")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("累计收益").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    AmountText(value: points.last?.value).font(.headline)
                }
                Text("最高 \(Fmt.compactSigned(highest)) · 最低 \(Fmt.compactSigned(lowest)) · \(points.count) 个交易日")
                    .font(.caption2).foregroundStyle(.secondary)
                if missingDays > 0 {
                    Text("其中 \(missingDays) 天缺少收盘价，按无变化延续，未计入收益。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Canvas(rendersAsynchronously: true) { context, size in
                    let labelArea: CGFloat = 16
                    let plotHeight = max(size.height - labelArea, 1)
                    let values = data.values
                    let maximum = data.maximum
                    let minimum = data.minimum
                    let span = max(maximum - minimum, 0.0001)
                    let step = size.width / CGFloat(max(values.count - 1, 1))
                    let zeroY = plotHeight * CGFloat((maximum - 0) / span)

                    var axis = Path()
                    axis.move(to: CGPoint(x: 0, y: zeroY))
                    axis.addLine(to: CGPoint(x: size.width, y: zeroY))
                    context.stroke(axis, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    var curve = Path()
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * step
                        let y = plotHeight * CGFloat((maximum - value) / span)
                        if index == 0 { curve.move(to: CGPoint(x: x, y: y)) }
                        else { curve.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(curve, with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                    for index in data.ticks {
                        let x = min(max(CGFloat(index) * step, 14), size.width - 14)
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: plotHeight))
                        tick.addLine(to: CGPoint(x: x, y: plotHeight + 4))
                        context.stroke(tick, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                        context.draw(Text(String(points[index].date.suffix(5)))
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary),
                                     at: CGPoint(x: x, y: plotHeight + 9))
                    }
                }
                .frame(height: 168)
                .accessibilityElement()
                .accessibilityLabel("累计收益曲线，当前 \(Fmt.signedMoney(points.last?.value))，最高 \(Fmt.signedMoney(highest))，最低 \(Fmt.signedMoney(lowest))，共 \(points.count) 个交易日")
            }
        }
    }
}
