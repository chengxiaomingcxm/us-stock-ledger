import SwiftUI
import UniformTypeIdentifiers

// 2.0 券商 CSV 导入界面：选择文件与类型（成交明细 / 资金流水）→ 字段映射 → 预览确认 → 写入账本。
// 预览阶段展示错误行与疑似重复，提交时再校验一次；未确认前不改动账本。

struct ImportView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

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
                Picker("导入类型", selection: $mode) {
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
                    Label(fileName.isEmpty ? "选择 CSV 文件" : "重新选择文件", systemImage: "doc.badge.plus")
                }
                if !fileName.isEmpty { LabeledContent("文件", value: fileName) }
                if !header.isEmpty { LabeledContent("识别到", value: "\(header.count) 列 · \(rows.count) 行记录") }
            } header: {
                Text("第一步：文件与类型")
            } footer: {
                Text("支持逗号、分号或制表符分隔；UTF-8 / UTF-16 / GBK 编码。文件只在本机读取，不上传。")
            }

            if !header.isEmpty {
                Section {
                    if mode == .trade {
                        ForEach(TradeField.allCases) { field in
                            Picker(field.label + (field.required ? "（必需）" : ""), selection: tradeBinding(for: field)) {
                                Text("未映射").tag(Int?.none)
                                ForEach(header.indices, id: \.self) { index in
                                    Text("第 \(index + 1) 列 · \(header[index])").tag(Int?.some(index))
                                }
                            }
                        }
                    } else {
                        ForEach(CashField.allCases) { field in
                            Picker(field.label + (field.required ? "（必需）" : ""), selection: cashBinding(for: field)) {
                                Text("未映射").tag(Int?.none)
                                ForEach(header.indices, id: \.self) { index in
                                    Text("第 \(index + 1) 列 · \(header[index])").tag(Int?.some(index))
                                }
                            }
                        }
                        if cashMapping[.type] == nil {
                            Picker("统一类型（缺少类型列时必选）", selection: $unifiedKind) {
                                ForEach(CashKind.allCases) { Text($0.label).tag($0) }
                            }
                            .onChange(of: unifiedKind) { _ in remap(auto: false) }
                        }
                    }
                    Button("按表头重新识别") { remap(auto: true) }
                    Button("重新校验") { remap(auto: false) }
                } header: {
                    Text("第二步：字段映射")
                } footer: {
                    Text(requiredMissing ? "必需列尚未全部指定。" : "修改映射并重新校验后，预览与统计会同步更新。")
                }

                Section {
                    LabeledContent("可导入", value: "\(readyCount) 行")
                    LabeledContent("疑似重复", value: "\(suspectedCount) 行（默认不勾选）")
                    LabeledContent("已导入", value: "\(duplicateCount) 行（按编号跳过）")
                    LabeledContent("无法导入", value: "\(errorCount) 行")
                    if mode == .trade {
                        Toggle("插入到同日已有交易之前", isOn: $insertBefore)
                            .onChange(of: insertBefore) { _ in revalidate() }
                    }
                } header: {
                    Text("第三步：确认")
                } footer: {
                    Text(mode == .trade
                         ? "同日买卖的相对顺序会影响已实现收益。账本同一天已有该股票交易时，请先确认顺序再导入。"
                         : "资金记录按日期顺序写入；重复导入不会重复记账，期初余额仍需按券商账单手动设置。")
                }

                Section("预览") {
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
        .navigationTitle("券商 CSV 导入")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if notice != nil { Button("完成") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("导入 \(selectedCount) 行") { commit() }
                    .disabled(selectedCount == 0 || batchError != nil)
            }
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .data]) { result in
            load(result)
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
                .accessibilityLabel(row.selected ? "取消选择第 \(row.line) 行" : "选择第 \(row.line) 行")
            } else {
                Image(systemName: row.status == .error ? "xmark.circle" : "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title(row)).font(.subheadline)
                Text("第 \(row.line) 行 · \(row.status.label)\(row.message.map { " · \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func title(_ row: ImportRow) -> String {
        if let trade = row.trade {
            let fee = trade.fee > 0 ? " 费 \(Fmt.moneyPlain(trade.fee))" : ""
            return "\(trade.date) \(trade.symbol) \(trade.side.label) \(Fmt.quantity(trade.quantity)) 股 × \(Fmt.moneyPlain(trade.price))\(fee)"
        }
        if let cash = row.cash {
            let tax = cash.tax.map { " 税 \(Fmt.moneyPlain($0))" } ?? ""
            let symbol = cash.symbol.map { " · \($0)" } ?? ""
            return "\(cash.date) \(cash.kind.label) \(Fmt.moneyPlain(cash.amount))\(tax)\(symbol)"
        }
        return "该行无法解析"
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
            error = failure.localizedDescription
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
                self.error = (error as? CsvImportError)?.errorDescription ?? error.localizedDescription
            }
        }
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
                notice = skipped > 0 ? "已识别 \(rows.count) 行，其中 \(skipped) 行需要留意。" : "已识别 \(rows.count) 行，可直接导入。"
            }
        } catch {
            rows = []
            self.error = (error as? CsvImportError)?.errorDescription ?? error.localizedDescription
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
            state.replace(with: candidate)
        case .cash:
            state.replace(with: CsvImport.candidateCash(ledger: state.ledger, rows: rows))
        }
        text = ""
        header = []
        rows = []
        error = nil
        notice = "已导入 \(count) 行，可在\(mode == .trade ? "交易" : "收益")页核对。"
    }
}
