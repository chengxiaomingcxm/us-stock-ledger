import SwiftUI
import UniformTypeIdentifiers

// 2.0 券商 CSV 导入界面：选择文件 → 字段映射 → 预览与确认 → 写入账本。
// 预览阶段展示错误行与疑似重复，提交时再校验一次；未确认前不改动账本。

struct ImportView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingPicker = false
    @State private var fileName = ""
    @State private var text = ""
    @State private var header: [String] = []
    @State private var mapping: [TradeField: Int] = [:]
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
    private var requiredMissing: Bool { TradeField.allCases.contains { $0.required && mapping[$0] == nil } }

    var body: some View {
        List {
            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label(fileName.isEmpty ? "选择 CSV 文件" : "重新选择文件", systemImage: "doc.badge.plus")
                }
                if !fileName.isEmpty { LabeledContent("文件", value: fileName) }
                if !header.isEmpty { LabeledContent("识别到", value: "\(header.count) 列 · \(rows.count) 行记录") }
            } header: {
                Text("第一步：选择文件")
            } footer: {
                Text("支持逗号、分号或制表符分隔；UTF-8 / UTF-16 / GBK 编码。文件只在本机读取，不上传。可参考：\(CsvImport.template.split(separator: "\n").first.map(String.init) ?? "")")
            }

            if !header.isEmpty {
                Section {
                    ForEach(TradeField.allCases) { field in
                        Picker(field.label + (field.required ? "（必需）" : ""), selection: binding(for: field)) {
                            Text("未映射").tag(Int?.none)
                            ForEach(header.indices, id: \.self) { index in
                                Text("第 \(index + 1) 列 · \(header[index])").tag(Int?.some(index))
                            }
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
                    LabeledContent("已导入", value: "\(duplicateCount) 行（按成交编号跳过）")
                    LabeledContent("无法导入", value: "\(errorCount) 行")
                    Toggle("插入到同日已有交易之前", isOn: $insertBefore)
                        .onChange(of: insertBefore) { _ in revalidate() }
                    if let batchError {
                        Label(batchError, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("第三步：确认")
                } footer: {
                    Text("同日买卖的相对顺序会影响已实现收益。账本同一天已有该股票交易时，请先确认顺序再导入。")
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
        guard let trade = row.trade else { return "该行无法解析" }
        return "\(trade.date) \(trade.symbol) \(trade.side.label) \(Fmt.quantity(trade.quantity)) 股 × \(Fmt.moneyPlain(trade.price))\(trade.fee > 0 ? " 费 \(Fmt.moneyPlain(trade.fee))" : "")"
    }

    private func toggle(_ row: ImportRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].selected.toggle()
        revalidate()
    }

    private func binding(for field: TradeField) -> Binding<Int?> {
        Binding(
            get: { mapping[field] },
            set: { value in
                if let value { mapping[field] = value } else { mapping.removeValue(forKey: field) }
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
                remap(auto: true)
            } catch {
                self.error = (error as? CsvImportError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func remap(auto: Bool) {
        guard !text.isEmpty else { return }
        do {
            if auto {
                let table = CsvImport.parse(text)
                guard let head = table.first else { throw CsvImportError.message("文件没有可识别的表头。") }
                header = head
                mapping = CsvImport.autoMap(head)
            }
            guard !header.isEmpty else { return }
            if requiredMissing {
                rows = []
                batchError = nil
                return
            }
            let report = try CsvImport.analyze(text: text, ledger: state.ledger, mapping: mapping)
            header = report.header
            mapping = report.mapping
            rows = report.rows
            revalidate()
            if auto, !report.rows.isEmpty {
                let skipped = report.errorCount + report.duplicateCount
                notice = skipped > 0 ? "已识别 \(report.rows.count) 行，其中 \(skipped) 行需要留意。" : "已识别 \(report.rows.count) 行，可直接导入。"
            }
        } catch {
            rows = []
            self.error = (error as? CsvImportError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func revalidate() {
        batchError = CsvImport.batchProblem(ledger: state.ledger, rows: rows, insertBeforeSameDay: insertBefore)
    }

    private func commit() {
        guard batchError == nil else { return }
        let candidate = CsvImport.candidate(ledger: state.ledger, rows: rows, insertBeforeSameDay: insertBefore)
        if let problem = CsvImport.validate(candidate) {
            batchError = problem
            return
        }
        let count = selectedCount
        state.replace(with: candidate)
        text = ""
        header = []
        rows = []
        error = nil
        notice = "已导入 \(count) 行，可在交易页核对。"
    }
}
