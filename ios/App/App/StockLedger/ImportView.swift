import SwiftUI
import UniformTypeIdentifiers

// 券商 CSV 导入界面：选择文件与类型（成交明细 / 资金流水）→ 字段映射 → 预览确认 → 写入账本。
// 预览阶段展示错误行与疑似重复，提交时再校验一次；未确认前不改动账本。

struct ImportView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// 截图 harness 用：预置一份 CSV 文本，跳过文件选择直接进入字段映射与预览。
    /// 与 `LedgerStore.fileURLOverride` 同类的最小接缝——正常运行时恒为空串，行为不变。
    static var prefillOverride = ""

    @State private var showingPicker = false
    @State private var fileName = ""
    @State private var text = ""
    @State private var mode: ImportMode = .trade
    @State private var header: [String] = []
    @State private var tradeMapping: [TradeField: Int] = [:]
    @State private var cashMapping: [CashField: Int] = [:]
    @State private var unifiedKind: CashKind = .deposit
    @State private var rows: [ImportRow] = []
    @State private var insertBefore = false
    @State private var error: String?
    @State private var batchError: String?
    @State private var notice: String?

    private var selectedCount: Int { rows.filter(\.selected).count }
    private var errorCount: Int { rows.filter { $0.status == .error }.count }
    private var suspectedCount: Int { rows.filter { $0.status == .suspected }.count }
    private var duplicateCount: Int { rows.filter { $0.status == .duplicate }.count }
    private var readyCount: Int { rows.filter { $0.status == .ready }.count }

    private var requiredMissing: Bool {
        switch mode {
        case .trade:
            return TradeField.allCases.contains { $0.required && tradeMapping[$0] == nil }
        case .cash:
            return CashField.allCases.contains { $0.required && cashMapping[$0] == nil }
        }
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.tr("导入类型"), selection: $mode) {
                    ForEach(ImportMode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in remap(auto: false) }
                Text(mode.detail).font(.caption).foregroundStyle(.secondary)

                Button {
                    showingPicker = true
                } label: {
                    Label(L10n.tr(fileName.isEmpty ? "选择 CSV 文件" : "重新选择文件"), systemImage: "doc.badge.plus")
                }
                if !fileName.isEmpty { LabeledContent(L10n.tr("文件"), value: fileName) }
                if !header.isEmpty { LabeledContent(L10n.tr("识别到"), value: "\(header.count) \(L10n.tr("列")) · \(rows.count) \(L10n.tr("行记录"))") }
            } header: {
                Text(L10n.tr("第一步：文件与类型"))
            } footer: {
                Text(L10n.tr("支持逗号、分号或制表符分隔；UTF-8 / UTF-16 / GBK 编码。文件只在本机读取，不上传。"))
            }

            if !header.isEmpty {
                Section {
                    if mode == .trade {
                        ForEach(TradeField.allCases) { field in
                            Picker(field.label + (field.required ? L10n.tr("（必需）") : ""), selection: tradeBinding(for: field)) {
                                Text(L10n.tr("未映射")).tag(Int?.none)
                                ForEach(header.indices, id: \.self) { index in
                                    Text("\(L10n.tr("第")) \(index + 1) \(L10n.tr("列")) · \(header[index])").tag(Int?.some(index))
                                }
                            }
                        }
                    } else {
                        ForEach(CashField.allCases) { field in
                            Picker(field.label + (field.required ? L10n.tr("（必需）") : ""), selection: cashBinding(for: field)) {
                                Text(L10n.tr("未映射")).tag(Int?.none)
                                ForEach(header.indices, id: \.self) { index in
                                    Text("\(L10n.tr("第")) \(index + 1) \(L10n.tr("列")) · \(header[index])").tag(Int?.some(index))
                                }
                            }
                        }
                        if cashMapping[.type] == nil {
                            Picker(L10n.tr("统一类型（缺少类型列时必选）"), selection: $unifiedKind) {
                                ForEach(CashKind.allCases) { Text($0.label).tag($0) }
                            }
                            .onChange(of: unifiedKind) { _ in remap(auto: false) }
                        }
                    }
                    Button(L10n.tr("按表头重新识别")) { remap(auto: true) }
                    Button(L10n.tr("重新校验")) { remap(auto: false) }
                } header: {
                    Text(L10n.tr("第二步：字段映射"))
                } footer: {
                    Text(L10n.tr(requiredMissing ? "必需列尚未全部指定。" : "修改映射并重新校验后，预览与统计会同步更新。"))
                }

                Section {
                    LabeledContent(L10n.tr("可导入"), value: "\(readyCount) \(L10n.tr("行"))")
                    LabeledContent(L10n.tr("疑似重复"), value: L10n.tr("{} 行（{}）", "\(suspectedCount)", L10n.tr("默认不勾选")))
                    LabeledContent(L10n.tr("已导入"), value: L10n.tr("{} 行（{}）", "\(duplicateCount)", L10n.tr("按编号跳过")))
                    LabeledContent(L10n.tr("无法导入"), value: "\(errorCount) \(L10n.tr("行"))")
                    if mode == .trade {
                        Toggle(L10n.tr("插入到同日已有交易之前"), isOn: $insertBefore)
                            .onChange(of: insertBefore) { _ in revalidate() }
                    }
                } header: {
                    Text(L10n.tr("第三步：确认"))
                } footer: {
                    Text(L10n.tr(mode == .trade
                         ? "同日买卖的相对顺序会影响已实现收益。账本同一天已有该股票交易时，请先确认顺序再导入。"
                         : "资金记录按日期顺序写入；重复导入不会重复记账，期初余额仍需按券商账单手动设置。"))
                }

                Section(L10n.tr("预览")) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }

            if let error {
                Section { Label(error, systemImage: "exclamationmark.octagon").foregroundStyle(.red) }
            }
            if let notice {
                Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(L10n.tr("券商 CSV 导入"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if notice != nil { Button(L10n.tr("完成")) { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("\(L10n.tr("导入")) \(selectedCount) \(L10n.tr("行"))") { commit() }
                    .disabled(selectedCount == 0 || batchError != nil)
            }
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .data]) { result in
            load(result)
        }
        // 走与选文件同一条路径（识别表头 → 自动映射 → 校验），只是数据不是从 URL 读的。
        .task {
            guard !Self.prefillOverride.isEmpty, text.isEmpty else { return }
            text = Self.prefillOverride
            fileName = "demo-trades.csv"
            if let head = CsvImport.parse(text).first { mode = CsvImport.detectMode(head) }
            remap(auto: true)
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func rowView(_ row: ImportRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if row.status == .ready || row.status == .suspected {
                Button {
                    toggle(row)
                } label: {
                    Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.selected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr(row.selected ? "取消选择第 {} 行" : "选择第 {} 行", "\(row.line)"))
            } else {
                Image(systemName: row.status == .error ? "xmark.circle" : "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title(row)).font(.subheadline)
                Text(L10n.tr("第 {} 行 · {}{}", "\(row.line)", row.status.label, row.message.map { " · \(L10n.tr($0))" } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func title(_ row: ImportRow) -> String {
        if let trade = row.trade {
            let fee = trade.fee > 0 ? L10n.tr(" 费 {}", Fmt.moneyPlain(trade.fee)) : ""
            return L10n.tr("{} {} {} {} 股 × {}{}", trade.date, trade.symbol, trade.side.label,
                           Fmt.quantity(trade.quantity), Fmt.moneyPlain(trade.price), fee)
        }
        if let cash = row.cash {
            let tax = cash.tax.map { L10n.tr(" 税 {}", Fmt.moneyPlain($0)) } ?? ""
            let symbol = cash.symbol.map { " · \($0)" } ?? ""
            return "\(cash.date) \(cash.kind.label) \(Fmt.moneyPlain(cash.amount))\(tax)\(symbol)"
        }
        return L10n.tr("该行无法解析")
    }

    private func toggle(_ row: ImportRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].selected.toggle()
        revalidate()
    }

    private func tradeBinding(for field: TradeField) -> Binding<Int?> {
        Binding(
            get: { tradeMapping[field] },
            set: { value in
                if let value { tradeMapping[field] = value } else { tradeMapping.removeValue(forKey: field) }
                remap(auto: false)
            }
        )
    }

    private func cashBinding(for field: CashField) -> Binding<Int?> {
        Binding(
            get: { cashMapping[field] },
            set: { value in
                if let value { cashMapping[field] = value } else { cashMapping.removeValue(forKey: field) }
                remap(auto: false)
            }
        )
    }

    // MARK: - 流程

    private func load(_ result: Result<URL, Error>) {
        error = nil
        notice = nil
        switch result {
        case .failure(let failure):
            Diagnostics.record("IMPORT", error: failure)
            error = L10n.tr("无法读取所选文件，未导入任何记录。")
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                text = try CsvImport.decode(data)
                fileName = url.lastPathComponent
                if let head = CsvImport.parse(text).first {
                    mode = CsvImport.detectMode(head)
                }
                remap(auto: true)
            } catch {
                self.error = readable(error)
            }
        }
    }

    /// 本模块自己抛的错误是写给用户看的；系统错误（文件不可读、内容不是文本等）
    /// 只在日志里留原文，界面上给一句可读的话。
    private func readable(_ error: Error) -> String {
        if let csv = error as? CsvImportError, let text = csv.errorDescription { return text }
        Diagnostics.record("IMPORT", error: error)
        return L10n.tr("无法读取所选文件，未导入任何记录。")
    }

    private func remap(auto: Bool) {
        guard !text.isEmpty else { return }
        do {
            if auto || header.isEmpty {
                guard let head = CsvImport.parse(text).first else { throw CsvImportError.message("文件没有可识别的表头。") }
                header = head
                tradeMapping = CsvImport.autoMap(head)
                cashMapping = CsvImport.autoMap(head, fields: CashField.allCases)
            }
            guard !header.isEmpty else { return }
            if requiredMissing {
                rows = []
                batchError = nil
                return
            }
            switch mode {
            case .trade:
                let report = try CsvImport.analyze(text: text, ledger: state.ledger, mapping: tradeMapping)
                header = report.header
                tradeMapping = report.mapping
                rows = report.rows
            case .cash:
                let report = try CsvImport.analyzeCash(text: text, ledger: state.ledger,
                                                       mapping: cashMapping,
                                                       unifiedKind: cashMapping[.type] == nil ? unifiedKind : nil)
                header = report.header
                cashMapping = report.cashMapping
                rows = report.rows
            }
            revalidate()
            if auto, !rows.isEmpty {
                let skipped = errorCount + duplicateCount
                notice = skipped > 0
                    ? L10n.tr("已识别 {} 行，其中 {} 行需要留意。", "\(rows.count)", "\(skipped)")
                    : L10n.tr("已识别 {} 行，可直接导入。", "\(rows.count)")
            }
        } catch {
            rows = []
            self.error = readable(error)
        }
    }

    private func revalidate() {
        guard mode == .trade else {
            batchError = nil
            return
        }
        batchError = CsvImport.batchProblem(ledger: state.ledger, rows: rows, insertBeforeSameDay: insertBefore)
    }

    private func commit() {
        guard batchError == nil else { return }
        let count = selectedCount
        switch mode {
        case .trade:
            let candidate = CsvImport.candidate(ledger: state.ledger, rows: rows, insertBeforeSameDay: insertBefore)
            if let problem = CsvImport.validate(candidate) {
                batchError = problem
                return
            }
            guard state.replace(with: candidate) else { importFailed(); return }
        case .cash:
            guard state.replace(with: CsvImport.candidateCash(ledger: state.ledger, rows: rows)) else { importFailed(); return }
        }
        text = ""
        header = []
        rows = []
        error = nil
        notice = L10n.tr("已导入 {} 行，可在{}页核对。", "\(count)", L10n.tr(mode == .trade ? "交易" : "收益"))
    }

    /// 写盘失败时保留预览（行、映射、勾选状态都不动），只显示原因，绝不谎报「已导入」。
    private func importFailed() {
        error = state.errorMessage ?? L10n.tr("操作失败，账本未改变。")
    }
}
