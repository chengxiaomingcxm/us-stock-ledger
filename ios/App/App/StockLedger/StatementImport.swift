import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// 2.0 银行月结单 PDF 导入：读取 PDF 的文字层，抽出候选的入金 / 出金 / 分红 / 费用行，
// 由用户核对日期、金额和类型后再写入现金账本。
// 说明：只能读取带文字层的 PDF；扫描件（图片）没有文字层，会明确提示改用 CSV。

struct StatementLine: Identifiable {
    var id = UUID()
    var raw: String
    var date: String          // yyyy-MM-dd
    var amount: Decimal
    var kind: CashKind
    var selected: Bool
    var duplicate: Bool = false
}

enum StatementImportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum StatementImport {
    // MARK: - 读取

    /// 返回 PDF 的文字内容；若是加密文件且密码不对，抛出可提示的错误。
    static func text(from url: URL, password: String? = nil) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw StatementImportError.message("无法打开这个 PDF 文件。")
        }
        if document.isLocked {
            guard let password, !password.isEmpty else {
                throw StatementImportError.message("这个 PDF 已加密，请输入打开密码。")
            }
            guard document.unlock(withPassword: password) else {
                throw StatementImportError.message("密码不正确，无法打开这个 PDF。")
            }
        }
        var pages: [String] = []
        for index in 0 ..< document.pageCount {
            if let text = document.page(at: index)?.string { pages.append(text) }
        }
        let text = pages.joined(separator: "\n")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else {
            throw StatementImportError.message("这个 PDF 没有可读取的文字层（可能是扫描件或截图）。请改用银行导出的 CSV 文件。")
        }
        return text
    }

    // MARK: - 解析

    private static let fullDate = try! NSRegularExpression(pattern: "\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}")
    private static let midDate = try! NSRegularExpression(pattern: "\\d{1,2}[-/.]\\d{1,2}[-/.]\\d{4}")
    private static let shortDate = try! NSRegularExpression(pattern: "\\b\\d{1,2}[-/.]\\d{1,2}\\b")
    private static let amountPattern = try! NSRegularExpression(pattern: "\\(?-?\\$?\\d{1,3}(?:,\\d{3})*\\.\\d{2}\\)?")

    private static let kindKeywords: [(CashKind, [String])] = [
        (.dividend, ["dividend", "interest", "股息", "分红", "利息", "派息"]),
        (.fee, ["fee", "service charge", "commission", "手续费", "费用", "服务费", "管理费", "账户费"]),
        (.deposit, ["deposit", "credit", "ach credit", "transfer in", "入金", "存入", "转入", "存款", "贷"]),
        (.withdraw, ["withdrawal", "debit", "transfer out", "出金", "转出", "取出", "提款", "支取", "借"]),
    ]

    /// 从文字里抽取候选记录；无法识别的行会直接跳过。
    static func lines(from text: String, existing: [CashRecord]) -> [StatementLine] {
        let rawLines = text.split(whereSeparator: \.isNewline).map { String($0) }
        let fallbackYear = dominantYear(in: rawLines) ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        let existingKeys = Set(existing.map { key($0.date, $0.kind, $0.amount) })
        var seen = Set<String>()
        var output: [StatementLine] = []

        for raw in rawLines {
            let line = raw.replacingOccurrences(of: "\t", with: " ")
            guard let date = date(in: line, fallbackYear: fallbackYear) else { continue }
            let found = matches(amountPattern, in: line)
            guard !found.isEmpty else { continue }
            let amounts = found.map { Amount(text: $0, negative: $0.hasPrefix("(") || $0.contains("-")) }
            let lowered = line.lowercased()
            let isBalanceLine = lowered.contains("balance") || line.contains("余额")
            // 带“余额”的行通常最后一个是余额、倒数第二个才是发生额。
            let chosen = isBalanceLine && amounts.count >= 2 ? amounts[amounts.count - 2] : amounts[amounts.count - 1]
            guard let amount = decimal(chosen.text), amount > 0 else { continue }

            let kind = kindOf(lowered, negative: chosen.negative)
            let key = key(date, kind, amount)
            guard seen.insert(key).inserted else { continue }
            let duplicate = existingKeys.contains(key)
            output.append(StatementLine(raw: line.trimmingCharacters(in: .whitespaces),
                                        date: date,
                                        amount: amount,
                                        kind: kind,
                                        selected: !duplicate,
                                        duplicate: duplicate))
            if output.count >= 500 { break }
        }
        return output
    }

    private static func key(_ date: String, _ kind: CashKind, _ amount: Decimal) -> String {
        "\(date)|\(kind.rawValue)|\(amount)"
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private struct Amount {
        var text: String
        var negative: Bool
    }

    private static func decimal(_ text: String) -> Decimal? {
        let clean = text
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard clean.range(of: "^\\d+(\\.\\d+)?$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: clean, locale: Locale(identifier: "en_US"))
    }

    private static func date(in line: String, fallbackYear: Int) -> String? {
        func cleaned(_ value: String) -> String {
            value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        }
        if let value = matches(fullDate, in: line).first, let text = valid(cleaned(value), format: "ymd") {
            return text
        }
        if let value = matches(midDate, in: line).first, let text = valid(cleaned(value), format: "mdy") {
            return text
        }
        if let value = matches(shortDate, in: line).first, let text = valid(cleaned(value), format: "md", fallbackYear: fallbackYear) {
            return text
        }
        return nil
    }

    private static func valid(_ value: String, format: String, fallbackYear: Int? = nil) -> String? {
        let parts = value.split(separator: "-").map(String.init)
        var year: Int
        var month: Int
        var day: Int
        switch format {
        case "ymd":
            guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
            year = y; month = m; day = d
        case "mdy":
            guard parts.count == 3, let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]) else { return nil }
            year = y; month = m; day = d
        default:
            guard parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]), let y = fallbackYear else { return nil }
            year = y; month = m; day = d
        }
        guard (1 ... 12).contains(month), (1 ... 31).contains(day), year >= 1990, year <= 2100 else { return nil }
        let text = String(format: "%04d-%02d-%02d", year, month, day)
        guard let parsed = MarketClock.utcDay(text), MarketClock.utcDate(parsed) == text else { return nil }
        return text
    }

    /// 文件里出现最多的年份，用于补全没有年份的日期。
    private static func dominantYear(in lines: [String]) -> Int? {
        var counts: [Int: Int] = [:]
        for line in lines {
            for value in matches(fullDate, in: line) + matches(midDate, in: line) {
                let parts = value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-").split(separator: "-")
                let candidate = parts.first?.count == 4 ? parts.first : parts.last
                if let text = candidate, let year = Int(text), year >= 1990, year <= 2100 {
                    counts[year, default: 0] += 1
                }
            }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private static func kindOf(_ lowered: String, negative: Bool) -> CashKind {
        for (kind, keywords) in kindKeywords where keywords.contains(where: { lowered.contains($0) }) {
            return kind
        }
        return negative ? .withdraw : .deposit
    }
}

// MARK: - 界面

struct StatementImportView: View {
    @EnvironmentObject private var state: AppState

    @State private var showingPicker = false
    @State private var fileName = ""
    @State private var password = ""
    @State private var needsPassword = false
    @State private var sourceURL: URL?
    @State private var rows: [StatementLine] = []
    @State private var error: String?
    @State private var notice: String?

    private var selectedCount: Int { rows.filter(\.selected).count }
    private var duplicateCount: Int { rows.filter(\.duplicate).count }

    var body: some View {
        List {
            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label(fileName.isEmpty ? "选择银行月结单 PDF" : "重新选择 PDF", systemImage: "doc.text.magnifyingglass")
                }
                if !fileName.isEmpty { LabeledContent("文件", value: fileName) }
                if needsPassword {
                    SecureField("PDF 打开密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("用这个密码重新读取") { if let url = sourceURL { load(url) } }
                }
            } header: {
                Text("第一步：选择月结单")
            } footer: {
                Text("只读取本机文件、不上传。仅支持带文字层的 PDF；扫描件或截图没有文字层，请改用银行导出的 CSV。")
            }

            if !rows.isEmpty {
                Section {
                    LabeledContent("识别到", value: "\(rows.count) 笔")
                    LabeledContent("已勾选", value: "\(selectedCount) 笔")
                    if duplicateCount > 0 {
                        Text("其中 \(duplicateCount) 笔与账本已有记录（日期、类型、金额相同），默认不勾选。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("全部勾选") { setAll(true) }
                    Button("全部取消") { setAll(false) }
                } header: {
                    Text("第二步：核对")
                } footer: {
                    Text("日期、金额和类型都可以直接修改；下方显示的是账单原文，便于逐条对照。")
                }

                Section("候选记录") {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Button {
                                    row.selected.toggle()
                                } label: {
                                    Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(row.selected ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(row.selected ? "取消选择" : "选择")
                                Picker("类型", selection: $row.kind) {
                                    ForEach(CashKind.allCases) { Text($0.label).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                Spacer()
                                TextField("金额", value: $row.amount, format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 110)
                                    .monospacedDigit()
                            }
                            DatePicker("日期（美东）", selection: Binding(
                                get: { DateFormatter.ledgerDate.date(from: row.date) ?? Date() },
                                set: { row.date = DateFormatter.ledgerDate.string(from: $0) }
                            ), in: ...Date(), displayedComponents: .date)
                            .font(.footnote)
                            Text(row.raw)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
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
        .navigationTitle("月结单 PDF 导入")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("导入 \(selectedCount) 笔") { commit() }
                    .disabled(selectedCount == 0)
            }
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .failure(let failure):
                error = failure.localizedDescription
            case .success(let url):
                load(url)
            }
        }
    }

    private func setAll(_ value: Bool) {
        for index in rows.indices { rows[index].selected = value }
    }

    private func load(_ url: URL) {
        error = nil
        notice = nil
        sourceURL = url
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try StatementImport.text(from: url, password: password.isEmpty ? nil : password)
            needsPassword = false
            fileName = url.lastPathComponent
            let parsed = StatementImport.lines(from: text, existing: state.ledger.cash)
            guard !parsed.isEmpty else {
                rows = []
                throw StatementImportError.message("没有识别到可用的资金记录。请在候选为空时改用 CSV，或手动记账。")
            }
            rows = parsed
            notice = "已识别 \(parsed.count) 笔候选记录，请核对后导入。"
        } catch {
            rows = []
            if let message = (error as? StatementImportError)?.errorDescription {
                needsPassword = message.contains("密码")
                self.error = message
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func commit() {
        error = nil
        let records = rows.filter(\.selected).map { row in
            CashRecord(id: UUID(), sequence: 0, date: row.date, kind: row.kind, amount: row.amount,
                       tax: nil, symbol: nil, note: "月结单导入", source: "statement", externalId: nil)
        }
        guard !records.isEmpty else { return }
        var next = state.ledger
        next.cash = CsvImport.mergeCash(state.orderedCash, records)
        state.replace(with: next)
        let count = records.count
        rows = []
        fileName = ""
        notice = "已导入 \(count) 笔资金记录，可在收益页现金账本核对。"
    }
}
