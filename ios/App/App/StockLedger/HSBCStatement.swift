import Foundation
import CryptoKit
import PDFKit

/// Only the HSBC investment composite layout is accepted. No sign/keyword guessing.
enum HSBCStatement {
    struct Row: Identifiable {
        var id: String
        var trade: Trade?
        var cash: CashRecord?
        var currency: String
        var detail: String
        var issue: String?
        var duplicate = false
        var selected = true
        var date: String { trade?.date ?? cash?.date ?? "" }
        var symbol: String { trade?.symbol ?? cash?.symbol ?? "" }
        var label: String { trade?.side.label ?? cash?.kind.label ?? "记录" }
        var amount: Decimal { trade?.netCash ?? cash?.net ?? 0 }
    }
    struct Report {
        var rows: [Row] = []
        var warnings: [String] = []
    }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
    static func date(_ text: String) throws -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "ddMMMyyyy"
        f.isLenient = false
        guard let d = f.date(from: text), f.string(from: d).uppercased() == text.uppercased() else {
            throw LedgerError.message("月结单日期无效：\(text)")
        }
        f.dateFormat = "yyyy-MM-dd"
        return try LedgerValidation.date(f.string(from: d))
    }
    static func amount(_ text: String) throws -> Decimal {
        try CsvImport.number(text, "金额或数量", allowZero: true)
    }
    static func parse(pages: [String], ledger: Ledger) throws -> Report {
        guard !pages.isEmpty, pages.count <= 100 else { throw LedgerError.message("PDF 页数必须在 1–100 页之间。") }
        let whole = pages.joined(separator: "\n")
        guard whole.count <= 2_000_000, whole.uppercased().contains("HSBC"),
              whole.contains("INVSTM0011") else {
            throw LedgerError.message("仅支持汇丰投资服务综合结单；银行往来账户结单请勿使用此入口。")
        }
        let accounts = matches(#"A/C\s*no[^\d\r\n]{0,40}(\d{3}-\d{6}-\d{3})"#, whole).map { $0[1] }
        guard let account = accounts.first, Set(accounts).count == 1 else {
            throw LedgerError.message("无法确认结单账户，或文件包含不同账户，未生成导入记录。")
        }
        let accountHash = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        func identity(_ reference: String) -> String { "hsbc:" + accountHash + ":" + reference.uppercased() }
        var report = Report(warnings: ["此类结单不含银行入金、出金和现金余额，不会推算期初现金。",
                                       "分红按 PAID BENEFITS 派付净额记录；结单未披露的税前金额与预扣税保留为未知。"])
        let flat = whole.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Unknown income/fee descriptions must not silently disappear in a partial import.
        for page in pages {
            guard let section = page.components(separatedBy: "Charges and income summary").dropFirst().first else { continue }
            let text = section.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let entries = matches(#"\b[A-Z]{3}\s+[\d,]+\.\d{2}\b"#, text)
            let known = matches(#"(?:PAID\s+BENEFITS|XACT\s+CHARGE)\s+[A-Z]{3}\s+[\d,]+\.\d{2}\b"#, text)
            let totals = matches(#"Total\s+charges\s+and\s+income\s+[A-Z]{3}\s+[\d,]+\.\d{2}\s+[A-Z]{3}\s+[\d,]+\.\d{2}"#, text)
            guard entries.count == known.count + totals.count * 2 else {
                throw LedgerError.message("结单含尚不支持的费用、税费或收入行，未生成部分导入。")
            }
        }
        let charges = matches(#"OUR\s+REFERENCE\s*:\s*([A-Z0-9]+)\s+XACT\s+CHARGE\s+([A-Z]{3})\s+([\d,.]+)"#, flat)
        var feeByReference: [String: Decimal] = [:]
        for charge in charges {
            let key = charge[1].uppercased()
            guard feeByReference[key] == nil else { throw LedgerError.message("文件内有重复费用编号，需核对后再导入。") }
            guard charge[2].uppercased() == "USD" else { continue }
            feeByReference[key] = try amount(charge[3])
        }
        var consumed = Set<String>()
        var seen = Set<String>()
        // Read only transaction sections, never the portfolio valuation table.
        for page in pages {
            let sections = page.components(separatedBy: "Transaction summary")
            guard sections.count > 1 else { continue }
            for section in sections.dropFirst() {
                let body = section.components(separatedBy: "Charges and income summary")[0]
                let symbolPattern = #"(?m)^\s*([A-Z][A-Z0-9.\-]{0,14})[ \t]+[^\r\n]*?\((SHS|UNT)\)"#
                let symbols = matches(symbolPattern, body)
                var remaining = body[...]
                for symbol in symbols {
                    guard let start = remaining.range(of: symbol[0]) else { continue }
                    remaining = remaining[start.upperBound...]
                    let nextSymbol = remaining.range(of: symbolPattern, options: .regularExpression)
                    let block = String(nextSymbol.map { remaining[..<$0.lowerBound] } ?? remaining)
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    let records = matches(#"(\d{2}[A-Z]{3}\d{4})\s+(\d{2}[A-Z]{3}\d{4})\s+([A-Z]{3})\s+([\d,.]+)\s+([\d,.]+)\s*(-?)\s+([A-Z]{3})\s+([\d,.]+)\s+Reference\s*:\s*([A-Z0-9]+)\s+Type\s*:\s*(PUR|SAL)\b"#, block)
                    for r in records {
                        let ref = r[9].uppercased(), id = identity(ref)
                        guard seen.insert(id).inserted else { throw LedgerError.message("文件内交易编号重复，未导入任何记录。") }
                        let side: TradeSide = r[10].uppercased() == "PUR" ? .buy : .sell
                        guard (side == .sell) == (r[6] == "-"), r[3] == r[7] else {
                            throw LedgerError.message("\(ref)：方向、股数符号或币种不一致。")
                        }
                        let tradeDate = try date(r[1]), settlementDate = try date(r[2])
                        guard settlementDate >= tradeDate else { throw LedgerError.message("交收日早于成交日。") }
                        let price = try amount(r[4]), quantity = try amount(r[5]), settlement = try amount(r[8])
                        guard price > 0, quantity > 0, settlement > 0 else { throw LedgerError.message("交易价格、股数及交收额必须大于零。") }
                        let fee = feeByReference[ref] ?? 0
                        let expected = side == .buy ? price * quantity + fee : price * quantity - fee
                        guard abs(expected - settlement) <= Decimal(string: "0.005")! else {
                            throw LedgerError.message("\(ref)：成交价、费用与交收额不符，需核对成交确认书。")
                        }
                        consumed.insert(ref)
                        let excluded = r[3].uppercased() != "USD" || symbol[2].uppercased() != "SHS"
                        let trade = Trade(sequence: 0, symbol: symbol[1].uppercased(), side: side, date: tradeDate,
                                          quantity: quantity, price: price, fee: fee,
                                          note: "汇丰月结单；交收日 \(settlementDate)", source: "hsbc-statement", externalId: id,
                                          settlementAmount: settlement, settlementDate: settlementDate)
                        report.rows.append(Row(id: id, trade: trade, currency: r[3].uppercased(),
                                               detail: "成交 \(tradeDate) · 交收 \(settlementDate) · \(quantity) 股 × \(price) · 费用 \(fee)",
                                               issue: excluded ? "非美元股票，不写入美元账本" : nil, selected: !excluded))
                    }
                }
                let references = matches(#"Reference\s*:\s*([A-Z0-9]+)\s+Type\s*:"#, body)
                let datedRows = matches(#"\d{2}[A-Z]{3}\d{4}\s+\d{2}[A-Z]{3}\d{4}\s+[A-Z]{3}"#, body)
                guard datedRows.count == references.count,
                      references.allSatisfy({ consumed.contains($0[1].uppercased()) }) else {
                    throw LedgerError.message("存在无法完整识别的交易行。请核对结单，未生成部分导入。")
                }
            }
        }
        let dividends = matches(#"(\d{2}[A-Z]{3}\d{4})\s+CASH\s+DIVIDEND\s+([A-Z][A-Z0-9.\-]*)\s+.*?OUR\s+REFERENCE\s*:\s*([A-Z0-9]+)\s+PAID\s+BENEFITS\s+([A-Z]{3})\s+([\d,.]+)"#, flat)
        for d in dividends {
            let id = identity(d[3])
            guard seen.insert(id).inserted else { throw LedgerError.message("文件内分红编号重复。") }
            let net = try amount(d[5])
            guard net > 0 else { throw LedgerError.message("分红派付金额必须大于零。") }
            let cash = CashRecord(sequence: 0, date: try date(d[1]), kind: .dividend, amount: net, tax: nil,
                                  symbol: d[2].uppercased(), note: "汇丰 PAID BENEFITS 净额；税前金额与预扣税未披露",
                                  source: "hsbc-statement-net", externalId: id)
            let excluded = d[4].uppercased() != "USD"
            report.rows.append(Row(id: id, cash: cash, currency: d[4].uppercased(), detail: cash.note,
                                   issue: excluded ? "非美元分红，不写入美元账本" : nil, selected: !excluded))
        }
        guard matches(#"CASH\s+DIVIDEND"#, flat).count == dividends.count,
              matches(#"XACT\s+CHARGE"#, flat).count == charges.count,
              Set(feeByReference.keys).isSubset(of: consumed) else {
            throw LedgerError.message("分红或交易费用未能完整关联，未导入任何记录。")
        }
        guard !report.rows.isEmpty else { throw LedgerError.message("结单未发现可识别的交易或分红。扫描件及其他结单格式暂不支持。") }
        guard report.rows.count <= 5000 else { throw LedgerError.message("单次最多导入 5000 笔。") }
        for i in report.rows.indices {
            let row = report.rows[i]
            if containsID(row.id, ledger) {
                report.rows[i].issue = "银行编号已存在，禁止重复导入"
                report.rows[i].selected = false
            } else if similar(row, ledger) {
                report.rows[i].duplicate = true
                report.rows[i].selected = false
            }
        }
        report.rows.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        return report
    }
    static func containsID(_ id: String, _ ledger: Ledger) -> Bool {
        ledger.trades.contains { $0.externalId == id } || ledger.cash.contains { $0.externalId == id }
    }
    static func similar(_ row: Row, _ ledger: Ledger) -> Bool {
        if let t = row.trade {
            // Old manual entries may have rounded prices or different fee attribution.
            // Treat same day/symbol/side/quantity as suspicious, never silently add again.
            return ledger.trades.contains { $0.date == t.date && $0.symbol == t.symbol && $0.side == t.side && $0.quantity == t.quantity }
        }
        if let c = row.cash {
            return ledger.cash.contains { $0.date == c.date && ($0.symbol == c.symbol || $0.symbol == nil || $0.symbol == "") && $0.kind == c.kind && $0.net == c.net }
        }
        return false
    }
    /// Revalidate against the current ledger immediately before one atomic save.
    static func candidate(rows: [Row], ledger: Ledger, insertBefore: Bool) throws -> Ledger {
        let selected = rows.filter(\.selected)
        guard !selected.isEmpty else { throw LedgerError.message("请先选择记录。") }
        var ids = Set<String>()
        for row in selected {
            guard row.issue == nil, row.currency == "USD", ids.insert(row.id).inserted,
                  !containsID(row.id, ledger) else { throw LedgerError.message("记录重复或不支持；请重新读取预览。") }
            if similar(row, ledger), !row.duplicate { throw LedgerError.message("预览后账本已变化，发现新的疑似重复，请重新读取。") }
        }
        var next = ledger
        next.trades = CsvImport.merge(ledger.orderedTrades, selected.compactMap(\.trade), insertBeforeSameDay: insertBefore)
        next.cash = CsvImport.mergeCash(ledger.orderedCash, selected.compactMap(\.cash))
        if let problem = CsvImport.validate(next) { throw LedgerError.message(problem) }
        return next
    }
}

enum StatementImport {
    static func pageText(_ page: PDFPage) -> String {
        let fragments = (page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? [])
            .compactMap { selection -> (CGRect, String)? in
                guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return (selection.bounds(for: page), text)
            }.sorted { $0.0.midY > $1.0.midY }
        var lines: [[(CGRect, String)]] = []
        for fragment in fragments {
            if let last = lines.last?.first, abs(last.0.midY - fragment.0.midY) <= 3 {
                lines[lines.count - 1].append(fragment)
            } else { lines.append([fragment]) }
        }
        return lines.map { $0.sorted { $0.0.minX < $1.0.minX }.map { $0.1 }.joined(separator: " ") }.joined(separator: "\n")
    }

    static func pages(from urls: [URL], password: String) throws -> [String] {
        guard !urls.isEmpty, urls.count <= 12 else { throw LedgerError.message("一次请选择 1–12 份结单。") }
        var pages: [String] = []
        for url in urls {
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 20_000_000 else { throw LedgerError.message("每份 PDF 必须小于 20 MB，且不能为空。") }
            guard let document = PDFDocument(url: url) else { throw LedgerError.message("无法打开 PDF。") }
            if document.isLocked, !document.unlock(withPassword: password) { throw LedgerError.message("PDF 需要正确的打开密码。") }
            guard document.pageCount > 0, pages.count + document.pageCount <= 100 else {
                throw LedgerError.message("一次最多读取 100 页。")
            }
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let text = document.page(at: index).map({ pageText($0) }), text.count > 20 else {
                    throw LedgerError.message("第 \(index + 1) 页没有完整文字层，扫描件暂不支持。")
                }
                pages.append(text)
            }
        }
        return pages
    }
}
