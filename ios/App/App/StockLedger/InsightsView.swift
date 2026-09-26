import SwiftUI
import UIKit

struct InsightsView: View {
    @EnvironmentObject private var state: AppState

    @State private var cashForm: CashFormMode?
    @State private var editingRecord: CashRecord?

    private var summary: LedgerSummary { state.summary }
    private var cash: CashTotals { state.cashTotals }

    var body: some View {
        let days = state.dayReturns
        return List {
            Section(L10n.tr("累计投资收益")) {
                AmountText(value: summary.totalProfit)
                    .font(.largeTitle.weight(.bold))
                Text(L10n.tr("已实现收益 + 当前持仓浮动收益（证券口径）"))
                    .font(.footnote).foregroundStyle(.secondary)
                ProfitRow(label: L10n.tr("已实现收益"), value: summary.realized)
                ProfitRow(label: L10n.tr("浮动收益"), value: summary.unrealized)
                ProfitRow(label: L10n.tr("分红净额（扣税）"), value: cash.dividend - cash.tax)
                ProfitRow(label: L10n.tr("账户费用"), value: -cash.fee)
                ProfitRow(label: L10n.tr("账户总收益"), value: summary.totalProfit.map { $0 + cash.investNetAll })
                    .font(.headline)
                Text(L10n.tr("入金出金不计入收益；今日盈亏与收益日历只统计证券。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.tr("现金账本")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("当前现金余额")).font(.footnote).foregroundStyle(.secondary)
                    Text(cash.balance == nil ? L10n.tr("待设置期初") : Fmt.money(cash.balance))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    if let opening = state.ledger.opening {
                        Text(L10n.tr("期初 {} 开始前 · {}", opening.date, opening.note.isEmpty ? "—" : opening.note))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    cashForm = .opening
                } label: {
                    HStack {
                        Text(state.ledger.opening == nil ? L10n.tr("设置期初余额") : L10n.tr("修改期初余额"))
                        Spacer()
                        Text(state.ledger.opening.map { Fmt.money($0.amount) } ?? L10n.tr("未设置"))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                if state.ledger.opening != nil {
                    Text(L10n.tr("期初余额是「期初日期当天开始前」的现金；录错可点上方一行修改，或清除后重新设置。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent(L10n.tr("累计入金"), value: Fmt.money(cash.deposit))
                LabeledContent(L10n.tr("累计出金"), value: Fmt.money(-cash.withdraw))
                ProfitRow(label: L10n.tr("分红到账（扣税）"), value: cash.dividend - cash.tax)
                ProfitRow(label: L10n.tr("已知预扣税费"), value: -cash.tax)
                if state.derived.unknownDividendTax > 0 {
                    Text("\(state.derived.unknownDividendTax) \(L10n.tr("笔分红按实际到账记账，预扣税未披露；不代表免税。"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProfitRow(label: L10n.tr("账户费用"), value: -cash.fee)
                // 未设置期初余额时 Engine.cashTotals 不计算买卖现金流（见其注释），buyOut/sellIn/tradeNet 恒为 0。
                // 直接渲染 $0.00 会被读成「真实的零」；改为显示未配置 + 提示，不动任何计算。
                let tracksCashFlow = state.ledger.opening != nil
                let buyOut: Decimal? = tracksCashFlow ? -cash.buyOut : nil
                let sellIn: Decimal? = tracksCashFlow ? cash.sellIn : nil
                let tradeNet: Decimal? = tracksCashFlow ? cash.tradeNet : nil
                LabeledContent(L10n.tr("买入支出（含费）"), value: Fmt.money(buyOut))
                LabeledContent(L10n.tr("卖出收入（扣费）"), value: Fmt.money(sellIn))
                LabeledContent(L10n.tr("买卖净现金流"), value: Fmt.signedMoney(tradeNet))
                if !tracksCashFlow {
                    Text(L10n.tr("设置期初余额后可跟踪买卖现金流。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if cash.excludedTrades > 0 || cash.excludedRecords > 0 {
                    Text(L10n.tr("期初前有 {} 笔交易、{} 笔资金记录，已含在期初余额中，仅保留备查。", "\(cash.excludedTrades)", "\(cash.excludedRecords)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L10n.tr("入金")) { cashForm = .new(.deposit) }
                    Button(L10n.tr("出金")) { cashForm = .new(.withdraw) }
                    Button(L10n.tr("分红")) { cashForm = .new(.dividend) }
                    Button(L10n.tr("费用")) { cashForm = .new(.fee) }
                }
                .font(.footnote)
            }

            if !state.orderedCash.isEmpty {
                Section(L10n.tr("现金记录")) {
                    ForEach(state.orderedCash.reversed()) { record in
                        Button { editingRecord = record } label: { cashRow(record) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(L10n.tr("删除"), role: .destructive) { state.deleteCash(record.id) }
                            }
                    }
                }
            }

            Section {
                ReturnCalendar(data: state.insights).equatable()
            } header: {
                HStack {
                    Text(L10n.tr("收益日历"))
                    Spacer()
                    if state.syncingHistory {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L10n.tr("同步历史")) { Task { await state.syncHistory() } }
                            .font(.footnote)
                            .disabled(state.ledger.trades.isEmpty)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("按上一交易日收盘与当日收盘计算每日收益，重放当前账本；缺少收盘价的交易日标记为待补全，不以零代替。历史行情优先使用 Tiingo，并由 Yahoo、Nasdaq 和手工录入兜底。"))
                    if let synced = state.historySyncedAt {
                        Text(L10n.tr("上次同步：{}", Fmt.clock(synced)))
                    }
                    ForEach(state.historyErrors.sorted { $0.key < $1.key }, id: \.key) { entry in
                        Text(L10n.tr("{}：{}", entry.key, entry.value))
                    }
                }
            }

            if !days.isEmpty {
                Section(L10n.tr("累计收益曲线")) {
                    CumulativeProfitChart(data: state.insights).equatable()
                }
            }

            if !summary.positions.isEmpty {
                Section(L10n.tr("各股票已实现收益")) {
                    ForEach(summary.positions) { position in
                        ProfitRow(label: "\(position.symbol) \(position.quantity == 0 ? L10n.tr("（已平仓）") : "")",
                                  value: position.realized)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("收益分析"))
        .safeAreaInset(edge: .top) {
            if state.rebuilding { ProgressView(L10n.tr("正在更新账本统计…")).padding(8).frame(maxWidth: .infinity).background(.regularMaterial) }
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
                Text("\(record.date)\(record.symbol.map { " · \($0)" } ?? "")\(Fmt.cashNote(record).isEmpty ? "" : " · \(Fmt.cashNote(record))")")
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
                        Text(L10n.tr("期初余额是“期初日期当天开始前”的现金。该日期当天及之后的入金、出金、分红、费用和股票买卖会联动余额；之前的记录视为已包含在期初余额中，保留备查、不重复计入。允许为零，不支持负数。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if state.ledger.opening != nil {
                        Section {
                            Button(L10n.tr("清除期初余额"), role: .destructive) {
                                state.clearOpening()
                                dismiss()
                            }
                        } footer: {
                            Text(L10n.tr("清除后现金余额显示为待设置期初；已记录的入金、出金、分红和费用不受影响，可重新填写期初。"))
                        }
                    }
                } else {
                    Section {
                        Picker(L10n.tr("类型"), selection: $kind) {
                            ForEach(CashKind.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }
                Section {
                    DatePicker(L10n.tr("日期（美东）"), selection: Binding(
                        get: { DateFormatter.ledgerDate.date(from: date) ?? Date() },
                        set: { date = DateFormatter.ledgerDate.string(from: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                    TextField(L10n.tr("金额（美元）"), text: $amount).keyboardType(.decimalPad)
                    if kind == .dividend && !isOpening {
                        TextField(L10n.tr("预扣税费（选填）"), text: $tax).keyboardType(.decimalPad)
                    }
                    if (kind == .dividend || kind == .fee) && !isOpening {
                        TextField(L10n.tr("股票代码（选填）"), text: $symbol)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    TextField(L10n.tr("备注（选填）"), text: $note, axis: .vertical).lineLimit(1...3)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private var title: String {
        switch mode {
        case .opening: return state.ledger.opening == nil ? L10n.tr("设置期初余额") : L10n.tr("修改期初余额")
        case .new: return L10n.tr("记录资金")
        case .edit: return L10n.tr("编辑资金记录")
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
            let parsedAmount = try LedgerValidation.positive(Decimal(string: amount, locale: Locale(identifier: "en_US")) ?? -1, isOpening ? L10n.tr("期初余额") : L10n.tr("金额"), allowZero: isOpening)
            let parsedDate = try LedgerValidation.date(date)
            if isOpening {
                state.setOpening(CashOpening(amount: parsedAmount, date: parsedDate, note: try LedgerValidation.note(note)))
                dismiss()
                return
            }
            var parsedTax: Decimal?
            if kind == .dividend, !tax.isEmpty {
                let value = try LedgerValidation.positive(Decimal(string: tax, locale: Locale(identifier: "en_US")) ?? -1, L10n.tr("税费"), allowZero: true)
                if value > parsedAmount { throw LedgerError.message(L10n.tr("税费不能超过分红金额。")) }
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
    @EnvironmentObject private var state: AppState
    @AppStorage("appearance.colors") private var colorPreference = "green-up"

    let data: InsightsPresentation

    @State private var month = ""
    @State private var selected: Engine.DayReturn?

    private var colors: ThemeColors { ThemeColors(redUp: colorPreference == "red-up") }
    private var months: [String] { data.months }
    private var stats: Engine.MonthStats { data.calendar[month]?.stats ?? Engine.MonthStats() }
    private typealias Cell = InsightsPresentation.Cell
    private var cells: [Cell] { data.calendar[month]?.cells ?? [] }

    private struct Week: Identifiable {
        let id: String
        let cells: [Cell]
    }

    private var weeks: [Week] {
        guard !cells.isEmpty else { return [] }
        var padded = cells
        while padded.count % 7 != 0 {
            padded.append(Cell(key: "trailing-\(padded.count)", day: nil, row: nil))
        }
        return stride(from: 0, to: padded.count, by: 7).map {
            Week(id: padded[$0].key, cells: Array(padded[$0..<($0 + 7)]))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if months.isEmpty {
                Text(L10n.tr("尚未同步历史行情。同步后可查看每日与月度收益。"))
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
                    .accessibilityLabel(L10n.tr("上一个月"))

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
                    .accessibilityLabel(L10n.tr("下一个月"))
                }
                ProfitRow(label: L10n.tr("本月收益"), value: stats.profit)
                    .font(.headline)
                LabeledContent(L10n.tr("已计算"), value: "\(stats.complete) \(L10n.tr("天"))")
                if stats.missing > 0 {
                    Text("\(stats.missing) \(L10n.tr("天收盘价不完整，未计入月度合计。"))")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // A non-lazy Grid is measured as one complete List row. Use actual
                // weeks and date identities rather than six nested range containers.
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    GridRow {
                        ForEach(L10n.weekdays, id: \.self) { label in
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(weeks) { week in
                        GridRow {
                            ForEach(week.cells) { cell in
                                dayCell(cell)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    legend(color: colors.gain(scheme), text: L10n.tr("盈利"))
                    legend(color: colors.loss(scheme), text: L10n.tr("亏损"))
                    Label(L10n.tr("待补全"), systemImage: "circle.dotted").font(.caption2).foregroundStyle(.secondary)
                }
                Text(L10n.tr("每天格子里显示当日收益金额，点按查看按股票的明细。"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { if month.isEmpty { month = months.last ?? "" } }
        .onChange(of: months) { value in if !value.contains(month) { month = value.last ?? "" } }
        .sheet(item: $selected) { row in
            DayReturnDetail(row: row)
                .environmentObject(state)
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
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(background(for: cell.row), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(cell.row == nil)
            .accessibilityLabel(accessibilityLabel(cell))
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 44)
        }
    }

    private func amountText(_ row: Engine.DayReturn?) -> String {
        guard let row else { return "" }
        guard let profit = row.profit else { return L10n.tr("待补") }
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
        guard let row = cell.row else { return "\(month)-\(day) " + L10n.tr("非交易日") }
        return "\(row.date) \(row.profit == nil ? L10n.tr("待补全") : Fmt.signedMoney(row.profit))"
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
    @EnvironmentObject private var state: AppState
    @State private var enteringClose = false
    let row: Engine.DayReturn

    var body: some View {
        let detail = DailyDetailPresentation(row: row, ledger: state.ledger)
        NavigationStack {
            List {
                Section {
                    LabeledContent(L10n.tr("日期"), value: row.date)
                    LabeledContent(L10n.tr("上一交易日"), value: row.previous ?? "—")
                    ProfitRow(label: L10n.tr("当日收益"), value: row.profit)
                    LabeledContent(L10n.tr("累计资产"), value: Fmt.money(row.cumulative))
                }
                contributionSection("当日持仓", rows: detail.held, subtotal: detail.heldSubtotal)
                contributionSection("当日已清仓", rows: detail.closed, subtotal: detail.closedSubtotal)
                Section {
                    ProfitRow(label: L10n.tr("当日合计"), value: row.profit)
                } footer: {
                    Text(L10n.tr("当日收益包含仍持仓及当日已清仓股票的贡献，不等同于已实现收益。分类按所选日期结束时的持仓判断。"))
                }
                if !row.missing.isEmpty {
                    Section(L10n.tr("缺失行情")) {
                        ForEach(row.missing, id: \.self) { text in
                            Text(text).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(L10n.tr("手动补录收盘价")) { enteringClose = true }
                            .disabled(state.demo)
                    }
                }
            }
            .navigationTitle(row.date)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
            .sheet(isPresented: $enteringClose) {
                HistoricalCloseForm(symbol: row.contributions.first(where: { $0.profit == nil })?.symbol ?? "", date: row.date)
                    .environmentObject(state)
            }
        }
    }
    @ViewBuilder
    private func contributionSection(_ title: String, rows: [Engine.Contribution], subtotal: Decimal?) -> some View {
        if !rows.isEmpty {
            Section(L10n.tr(title)) {
                ForEach(rows) { item in
                    if let profit = item.profit {
                        ProfitRow(label: item.symbol, value: profit)
                    } else {
                        LabeledContent(item.symbol, value: item.reason ?? L10n.tr("待补全"))
                    }
                }
                ProfitRow(label: L10n.tr("小计"), value: subtotal)
            }
        }
    }
}

struct HistoricalCloseForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State var symbol: String
    @State var date: String
    @State private var price = ""
    @State private var failure: String?

    init(symbol: String, date: String) {
        _symbol = State(initialValue: symbol)
        _date = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.tr("股票代码"), text: $symbol)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField(L10n.tr("日期（YYYY-MM-DD）"), text: $date)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(L10n.tr("收盘价"), text: $price).keyboardType(.decimalPad)
                } footer: {
                    Text(L10n.tr("请按券商结单或可靠行情核对。手工值会保留，并优先于之后的自动同步。若缺少的是上一交易日，请把日期改为详情中的“上一交易日”。"))
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(L10n.tr("补录收盘价"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) { save() } }
            }
        }
    }

    private func save() {
        do {
            let cleanSymbol = try LedgerValidation.symbol(symbol)
            let cleanDate = try LedgerValidation.date(date)
            guard let value = Decimal(string: price, locale: Locale(identifier: "en_US")) else {
                throw LedgerError.message("价格格式无效。")
            }
            let cleanPrice = try LedgerValidation.positive(value, L10n.tr("价格"))
            guard cleanPrice < Decimal(1_000_000_000_000) else { throw LedgerError.message("价格格式无效。") }
            if state.setHistoricalClose(symbol: cleanSymbol, price: cleanPrice, date: cleanDate) { dismiss() }
            else { failure = state.errorMessage ?? L10n.tr("保存失败。") }
        } catch {
            failure = error.localizedDescription
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
            Text(L10n.tr("同步两个以上交易日后可查看曲线。"))
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.tr("累计收益")).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    AmountText(value: points.last?.value).font(.headline)
                }
                // 与纵轴参考值、卡片大数保持同一种金额格式：都带 $，只有大数带分。
                Text(L10n.tr("最高 {} · 最低 {} · {} 个交易日", Fmt.compactMoney(highest), Fmt.compactMoney(lowest), "\(points.count)"))
                    .font(.caption2).foregroundStyle(.secondary)
                if missingDays > 0 {
                    Text(L10n.tr("其中 {} 天缺少收盘价，按无变化延续，未计入收益。", "\(missingDays)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                ProfitPlot(data: data, color: UIColor(lineColor), labelColor: (scheme == .dark ? UIColor.lightGray : UIColor.darkGray))
                .frame(height: 168)
                .accessibilityElement()
                .accessibilityLabel(L10n.tr("累计收益曲线，当前 {}，最高 {}，最低 {}，共 {} 个交易日", Fmt.signedMoney(points.last?.value), Fmt.signedMoney(highest), Fmt.signedMoney(lowest), "\(points.count)"))
            }
        }
    }
}

/// Retained Core Animation layers: scrolling translates an existing chart, never redraws it.
private struct ProfitPlot: UIViewRepresentable {
    let data: InsightsPresentation
    let color: UIColor
    let labelColor: UIColor
    func makeUIView(context: Context) -> ProfitPlotView { ProfitPlotView() }
    func updateUIView(_ view: ProfitPlotView, context: Context) {
        view.update(data: data, color: color, labelColor: labelColor)
    }
}
private final class ProfitPlotView: UIView {
    private let curve = CAShapeLayer()
    private let axis = CAShapeLayer()
    private var labels: [UILabel] = []
    private var scales: [UILabel] = []
    private var data = InsightsPresentation()
    private var previousBounds = CGRect.null
    private var renderedRevision: UUID?
    override init(frame: CGRect) {
        super.init(frame: frame)
        // ponytail: 曲线是 CAShapeLayer，不做长按拖动读数——那要先跟外层 Form 的滚动手势做仲裁，
        // 而本机没有 Swift 工具链验证不了真机行为。这里只补参考值把量级说清楚（审计书 P2-1 方案 A）；
        // 升级路径：真机可验证时再加 UILongPressGestureRecognizer（0.15s）画竖线 + 气泡读数。
        isUserInteractionEnabled = false
        curve.fillColor = nil; curve.lineWidth = 2; curve.lineJoin = .round
        axis.fillColor = nil; axis.lineWidth = 1; axis.lineDashPattern = [3, 3]
        layer.addSublayer(axis); layer.addSublayer(curve)
        for _ in 0..<6 {
            let label = UILabel()
            label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            label.textAlignment = .center
            addSubview(label); labels.append(label)
        }
        // 参考值靠右对齐，占曲线右侧那条窄栏。
        // `−$40.00` 是 7 个等宽字符，正好压着 38pt 的栏宽，所以允许缩字而不是截成省略号。
        for _ in 0..<3 {
            let label = UILabel()
            label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            label.textAlignment = .right
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.75
            addSubview(label); scales.append(label)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(data: InsightsPresentation, color: UIColor, labelColor: UIColor) {
        self.data = data
        CATransaction.begin(); CATransaction.setDisableActions(true)
        curve.strokeColor = color.cgColor; axis.strokeColor = labelColor.withAlphaComponent(0.35).cgColor
        for label in labels { label.textColor = labelColor }
        for label in scales { label.textColor = labelColor }
        CATransaction.commit()
        if renderedRevision != data.revision { setNeedsLayout() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != previousBounds || renderedRevision != data.revision else { return }
        previousBounds = bounds; renderedRevision = data.revision
        let height = max(bounds.height - 16, 1)
        // 曲线让出右侧一条窄栏给参考值：数字贴在边上，不会压在曲线上。
        let gutter = min(40, bounds.width * 0.2)
        let plot = max(bounds.width - gutter, 1)
        var transform = CGAffineTransform(scaleX: plot, y: height)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        curve.frame = bounds; axis.frame = bounds
        curve.path = data.curve.copy(using: &transform)
        let y = height * CGFloat(data.maximum / max(data.maximum - data.minimum, 0.0001))
        let zero = CGMutablePath(); zero.move(to: CGPoint(x: 0, y: y)); zero.addLine(to: CGPoint(x: plot, y: y))
        axis.path = zero
        for i in labels.indices {
            guard data.ticks.indices.contains(i) else { labels[i].isHidden = true; continue }
            let index = data.ticks[i]
            labels[i].isHidden = false
            labels[i].text = String(data.points[index].date.suffix(5))
            let x = plot * CGFloat(index) / CGFloat(max(data.values.count - 1, 1))
            labels[i].frame = CGRect(x: min(max(x - 20, 0), max(plot - 40, 0)), y: height + 2, width: 40, height: 14)
        }
        let references = data.axisReferences()
        for i in scales.indices {
            guard references.indices.contains(i) else { scales[i].isHidden = true; continue }
            scales[i].isHidden = false
            scales[i].text = references[i].text
            let center = height * references[i].position
            scales[i].frame = CGRect(x: plot + 2, y: min(max(center - 6, 0), max(height - 12, 0)),
                                     width: max(bounds.width - plot - 2, 1), height: 12)
        }
        CATransaction.commit()
    }
}
