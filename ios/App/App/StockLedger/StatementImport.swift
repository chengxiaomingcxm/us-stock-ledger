import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct StatementImportView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingPicker = false
    @State private var confirming = false
    @State private var password = ""
    @State private var urls: [URL] = []
    @State private var rows: [HSBCStatement.Row] = []
    @State private var warnings: [String] = []
    @State private var loading = false
    @State private var insertingBefore = false
    @State private var error: String?
    @State private var notice: String?
    @State private var operation = UUID()
    @State private var readTask: Task<HSBCStatement.Report, Error>?
    private var count: Int { rows.filter(\.selected).count }

    var body: some View {
        List {
            Section("选择结单") {
                Button("选择汇丰投资结单 PDF") { showingPicker = true }.disabled(loading)
                SecureField("打开密码（未加密可留空）", text: $password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !urls.isEmpty {
                    Button("重新读取 \(urls.count) 份结单") { load(urls) }.disabled(loading)
                }
                Text("在文件列表里先点一下结单，让它出现勾选，再点右上角「打开」。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("本机读取，支持多份一起核对。仅支持汇丰投资服务综合结单，非美元记录不导入。")
                    .font(.footnote).foregroundStyle(.secondary)
                if loading { ProgressView("正在读取与核对…") }
            }
            if !rows.isEmpty {
                Section("导入前核对") {
                    LabeledContent("已选择", value: "\(count) / \(rows.count) 笔")
                    Button("取消全部选择") { for i in rows.indices { rows[i].selected = false } }
                    Toggle("同日交易插入已有记录之前", isOn: $insertingBefore)
                    Text("疑似已有记录默认不选；确认是不同交易才勾选。已导入的银行编号禁止重复添加。")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("识别结果") {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $row.selected) {
                                Text("\(row.date) · \(row.symbol) · \(row.label)")
                            }.disabled(row.issue != nil)
                            Text("\(row.currency) \(row.amount.description)").monospacedDigit()
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            if row.duplicate { Text("疑似已有记录：请核对金额、手续费和分红净额").font(.caption).foregroundStyle(.orange) }
                            if let issue = row.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let notice { Section { Text(notice) } }
        }
        .navigationTitle("汇丰月结单导入")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("导入 \(count) 笔") { confirming = true }.disabled(count == 0 || loading)
            }
        }
        .confirmationDialog("确认将所选记录写入账本？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认导入 \(count) 笔") { commit() }
            Button("取消", role: .cancel) { }
        } message: { Text("买卖联动现金，关联手续费只计一次；不会新增推算的入金、出金或期初余额。") }
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(
                onPick: { picked in
                    showingPicker = false
                    guard !picked.isEmpty else { return }
                    load(picked)
                },
                onCancel: { showingPicker = false }
            )
            .ignoresSafeArea()
        }
        .onDisappear {
            readTask?.cancel()
            operation = UUID()
            password = ""
            cleanUpCopies(urls)
        }
    }

    private func load(_ selected: [URL]) {
        readTask?.cancel()
        let token = UUID()
        operation = token
        urls = selected
        rows = []
        error = nil
        warnings = []
        notice = "已选择 \(selected.count) 份文件，正在读取…"
        loading = true
        let ledger = state.ledger, secret = password
        let worker = Task.detached(priority: .userInitiated) {
            try HSBCStatement.parse(pages: StatementImport.pages(from: selected, password: secret), ledger: ledger)
        }
        readTask = worker
        Task { @MainActor in
            do {
                let report = try await worker.value
                guard operation == token else { return }
                rows = report.rows; warnings = report.warnings; password = ""
                if report.rows.isEmpty, let first = report.warnings.first { notice = first }
            } catch {
                guard operation == token else { return }
                notice = nil
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    /// 文件选择器以副本方式交付，读取完成后在离开页面时删除，避免结单副本留在沙盒里。
    private func cleanUpCopies(_ files: [URL]) {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        for url in files where url.standardizedFileURL.path.hasPrefix(temporary) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func commit() {
        guard !loading else { return }
        do {
            let next = try HSBCStatement.candidate(rows: rows, ledger: state.ledger, insertBefore: insertingBefore)
            let imported = count
            guard state.commit(next) else { throw LedgerError.message(state.errorMessage ?? "保存失败，原账本未改变。") }
            rows = []; urls = []; password = ""; error = nil
            notice = "已导入 \(imported) 笔；可在交易和收益页面核对。"
        } catch { self.error = error.localizedDescription }
    }
}

/// 用 UIKit 的文件选择器代替 SwiftUI 的 `fileImporter`。
/// `fileImporter` 在 NavigationStack 里出现过「选了文件、点右上角打开没有任何反应」的问题：
/// 结果回调依赖 SwiftUI 的隐式呈现匹配，一旦失配就没有任何反馈。
/// 这里改为显式代理回调、并以副本方式交付（asCopy），避免安全作用域与 iCloud 占位文件造成的静默失败。
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        controller.allowsMultipleSelection = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPicker

        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
