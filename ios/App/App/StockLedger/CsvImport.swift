import Foundation

// 2.0 券商 CSV 导入：先预览、再写入。解析规则与 1.x 保持一致——
// 严格数字与日期校验、币种校验、成交编号去重、同日相对顺序由用户确认。
// 任何无法确定的记录都标记为错误或疑似重复，绝不静默改写账本。

enum TradeField: String, CaseIterable, Identifiable {
    case date, symbol, side, quantity, price, fee, note, currency, id

    var id: String { rawValue }

    var label: String {
        switch self {
        case .date: return "日期"
        case .symbol: return "代码"
        case .side: return "方向"
        case .quantity: return "数量"
        case .price: return "单价"
        case .fee: return "手续费"
        case .note: return "备注"
        case .currency: return "币种"
        case .id: return "成交编号"
        }
    }

    var required: Bool {
        switch self {
        case .date, .symbol, .side, .quantity, .price: return true
        default: return false
        }
    }

    var aliases: [String] {
        switch self {
        case .date: return ["date", "tradedate", "交易日期", "成交日期", "日期", "时间", "time", "datetime"]
        case .symbol: return ["symbol", "ticker", "code", "stockcode", "证券代码", "股票代码", "代码", "标的", "标的代码"]
        case .side: return ["side", "direction", "action", "buysell", "买卖", "方向", "交易方向", "操作", "type", "交易类型"]
        case .quantity: return ["quantity", "qty", "shares", "成交数量", "数量", "股数", "成交股数"]
        case .price: return ["price", "tradeprice", "成交价", "成交价格", "成交单价", "价格", "均价", "avgprice"]
        case .fee: return ["fee", "commission", "fees", "手续费", "佣金", "费用", "交易费用"]
        case .note: return ["note", "notes", "memo", "remark", "备注", "说明"]
        case .currency: return ["currency", "ccy", "币种", "货币", "结算币种"]
        case .id: return ["tradeid", "executionid", "transactionid", "成交编号", "成交单号", "流水号"]
        }
    }
}

enum RowStatus: String {
    case ready, suspected, duplicate, error

    var label: String {
        switch self {
        case .ready: return "可导入"
        case .suspected: return "疑似重复"
        case .duplicate: return "已导入"
        case .error: return "无法导入"
        }
    }
}

struct ImportRow: Identifiable {
    var id = UUID()
    var line: Int
    var status: RowStatus
    var trade: Trade?
    var message: String?
    var selected: Bool
}

struct ImportReport {
    var delimiter: Character = ","
    var header: [String] = []
    var mapping: [TradeField: Int] = [:]
    var rows: [ImportRow] = []
    /// 按当前勾选与顺序规则生成候选账本后发现的整体问题（例如超卖），存在时不允许导入。
    var batchError: String?
    var errorCount: Int { rows.filter { $0.status == .error }.count }
    var readyCount: Int { rows.filter { $0.status == .ready }.count }
    var suspectedCount: Int { rows.filter { $0.status == .suspected }.count }
    var duplicateCount: Int { rows.filter { $0.status == .duplicate }.count }
    var isEmpty: Bool { header.isEmpty }
}

enum CsvImportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum CsvImport {
    // MARK: - 编码

    /// UTF-8 / UTF-16 严格解码；GBK 仅在能完整往返时接受。
    static func decode(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16LittleEndian), text.contains("\n") { return text }
            if let text = String(data: data, encoding: .utf16BigEndian), text.contains("\n") { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16LittleEndian), text.contains("\n") { return text }
        if let text = String(data: data, encoding: .utf16BigEndian), text.contains("\n") { return text }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gbk), text.canBeConverted(to: gbk) { return text }
        throw CsvImportError.message("无法识别文件编码，请另存为 UTF-8 后重试。")
    }

    // MARK: - 词法

    /// 逐字符解析，正确支持引号包裹、字段内换行与双引号转义。
    static func parse(_ text: String) -> [[String]] {
        let separator = delimiter(text: text)
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?

        func finishField() {
            row.append(field)
            field = ""
        }
        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while true {
            let next: Character?
            if let pendingCharacter = pending {
                next = pendingCharacter
                pending = nil
            } else {
                next = iterator.next()
            }
            guard let character = next else {
                if !row.isEmpty || !field.isEmpty { finishRow() }
                break
            }
            if quoted {
                if character == "\"" {
                    if let peek = iterator.next() {
                        if peek == "\"" { field.append("\"") }
                        else { quoted = false; pending = peek }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                quoted = true
            case separator:
                finishField()
            case "\r":
                finishRow()
                if let peek = iterator.next(), peek != "\n" { pending = peek }
            case "\n":
                finishRow()
            default:
                field.append(character)
            }
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    private static func delimiter(text: String) -> Character {
        let head = text.prefix(4096)
        let candidates: [Character] = [",", ";", "\t"]
        let counts = candidates.map { candidate in (candidate, head.filter { $0 == candidate }.count) }
        return counts.max { $0.1 < $1.1 }?.0 ?? ","
    }

    // MARK: - 映射

    private static let normalise: (String) -> String = { value in
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func autoMap(_ header: [String]) -> [TradeField: Int] {
        var used = Set<Int>()
        var map: [TradeField: Int] = [:]
        for field in TradeField.allCases {
            let index = header.indices.first { index in
                !used.contains(index) && field.aliases.contains { normalise($0) == normalise(header[index]) }
            }
            if let index { map[field] = index; used.insert(index) }
        }
        return map
    }

    // MARK: - 值解析

    private static func field(_ cells: [String], _ mapping: [TradeField: Int], _ key: TradeField) -> String? {
        guard let index = mapping[key], index < cells.count else { return nil }
        let value = cells[index].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    static func number(_ raw: String, _ label: String, allowZero: Bool = false) throws -> Decimal {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("usd") { text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        if text.hasPrefix("$") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        let plainPattern = "^\\d+(\\.\\d+)?$"
        let groupedPattern = "^\\d{1,3}(,\\d{3})+(\\.\\d+)?$"
        guard text.range(of: plainPattern, options: .regularExpression) != nil
            || text.range(of: groupedPattern, options: .regularExpression) != nil else {
            throw CsvImportError.message("\(label)格式无效（示例：1,234.56 或 1234.56）")
        }
        let plain = text.replacingOccurrences(of: ",", with: "")
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        if parts[0].count > 12 || (parts.count == 2 && parts[1].count > 8) {
            throw CsvImportError.message("\(label)超出支持范围或精度")
        }
        guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US")) else {
            throw CsvImportError.message("\(label)无效")
        }
        if value < 0 || (!allowZero && value == 0) {
            throw CsvImportError.message("\(label)必须\(allowZero ? "不小于 0" : "大于 0")")
        }
        return value
    }

    /// 只接受美东本地日期与时间，拒绝 Z / 时区偏移后缀（与 1.x 一致）。
    static func dateTime(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.range(of: "(Z|[+-]\\d{2}:?\\d{2})$", options: [.regularExpression, .caseInsensitive]) == nil else {
            throw CsvImportError.message("成交时间不支持时区后缀，请使用美东本地时间")
        }
        let pattern = "^(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})([ T](\\d{1,2}):(\\d{2})(:(\\d{2}))?)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            throw CsvImportError.message("日期格式无法识别（示例：2026-09-17 或 2026/9/17 09:31）")
        }
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard let year = group(1), let month = group(2), let day = group(3),
              let monthValue = Int(month), let dayValue = Int(day),
              (1 ... 12).contains(monthValue), (1 ... 31).contains(dayValue) else {
            throw CsvImportError.message("日期无效")
        }
        let value = String(format: "%@-%02d-%02d", year, monthValue, dayValue)
        guard let parsed = MarketClock.day(value), MarketClock.utcDate(parsed) == value else {
            throw CsvImportError.message("日期必须是真实日期")
        }
        if let hour = group(5), let minute = group(6), let hourValue = Int(hour), let minuteValue = Int(minute),
           !(0 ... 23).contains(hourValue) || !(0 ... 59).contains(minuteValue) {
            throw CsvImportError.message("成交时间无效")
        }
        guard value <= MarketClock.date() else { throw CsvImportError.message("日期不能晚于今天") }
        return value
    }

    private static let sideValues: [String: TradeSide] = [
        "buy": .buy, "b": .buy, "买入": .buy, "买": .buy,
        "sell": .sell, "s": .sell, "卖出": .sell, "卖": .sell,
    ]

    static func side(_ raw: String) throws -> TradeSide {
        let key = normalise(raw)
        guard let value = sideValues[key] else {
            throw CsvImportError.message("买卖方向无法识别（支持 买入/卖出 或 buy/sell）")
        }
        return value
    }

    // MARK: - 解析

    /// 解析并逐行校验，返回可供预览的报告；不修改账本。
    static func analyze(text: String, ledger: Ledger, mapping overrideMapping: [TradeField: Int]? = nil) throws -> ImportReport {
        let table = parse(text)
        guard let headerRow = table.first, headerRow.count > 1 else {
            throw CsvImportError.message("文件没有可识别的表头。")
        }
        var report = ImportReport()
        report.delimiter = delimiter(text: text)
        report.header = headerRow
        report.mapping = overrideMapping ?? autoMap(headerRow)

        let missing = TradeField.allCases.filter { $0.required && report.mapping[$0] == nil }
        if !missing.isEmpty {
            throw CsvImportError.message("请先指定必需列：\(missing.map(\.label).joined(separator: "、"))。")
        }

        let existingIds = Set(ledger.trades.compactMap { $0.externalId })
        let existingValues = Set(ledger.trades.map { signature($0.date, $0.symbol, $0.side, $0.quantity, $0.price, $0.fee) })
        var seenIds = Set<String>()
        var duplicateInFile = Set<String>()

        for (offset, cells) in table.dropFirst().enumerated() {
            let line = offset + 2
            let raw = cells.map { $0.trimmingCharacters(in: .whitespaces) }
            if raw.allSatisfy({ $0.isEmpty }) { continue }
            do {
                guard let dateText = field(raw, report.mapping, .date) else { throw CsvImportError.message("缺少日期") }
                guard let symbolText = field(raw, report.mapping, .symbol) else { throw CsvImportError.message("缺少代码") }
                guard let sideText = field(raw, report.mapping, .side) else { throw CsvImportError.message("缺少买卖方向") }
                guard let quantityText = field(raw, report.mapping, .quantity) else { throw CsvImportError.message("缺少数量") }
                guard let priceText = field(raw, report.mapping, .price) else { throw CsvImportError.message("缺少单价") }

                if let currency = field(raw, report.mapping, .currency), currency.uppercased() != "USD" {
                    throw CsvImportError.message("只支持美元记录，币种为 \(currency)")
                }
                let date = try dateTime(dateText)
                let symbol = try LedgerValidation.symbol(symbolText)
                let side = try side(sideText)
                let quantity = try number(quantityText, "数量")
                let price = try number(priceText, "单价")
                let fee = try field(raw, report.mapping, .fee).map { try number($0, "手续费", allowZero: true) } ?? 0
                let note = try field(raw, report.mapping, .note).map { try LedgerValidation.note($0) } ?? ""
                let externalId = field(raw, report.mapping, .id)

                let trade = Trade(id: UUID(), sequence: 0, symbol: symbol, side: side, date: date,
                                  quantity: quantity, price: price, fee: fee, note: note,
                                  source: "import", externalId: externalId)
                var status: RowStatus = .ready
                var message: String?
                if let externalId, existingIds.contains(externalId) {
                    status = .duplicate
                    message = "账本中已有相同成交编号"
                } else if let externalId, !seenIds.insert(externalId).inserted {
                    status = .duplicate
                    message = "文件内重复的成交编号"
                    duplicateInFile.insert(externalId)
                } else if existingValues.contains(signature(date, symbol, side, quantity, price, fee)) {
                    status = .suspected
                    message = "与账本中已有记录日期、代码、方向、数量、单价与手续费完全相同"
                }
                report.rows.append(ImportRow(line: line, status: status, trade: trade, message: message, selected: status == .ready))
            } catch {
                report.rows.append(ImportRow(line: line, status: .error, trade: nil,
                                             message: (error as? CsvImportError)?.errorDescription ?? error.localizedDescription,
                                             selected: false))
            }
        }

        if report.rows.isEmpty { throw CsvImportError.message("文件里没有可读取的交易记录。") }
        report.batchError = validate(candidate(ledger: ledger, rows: report.rows, insertBeforeSameDay: false))
        return report
    }

    /// 预览与提交共用同一份候选账本生成逻辑，避免预览通过而提交失败。
    static func candidate(ledger: Ledger, rows: [ImportRow], insertBeforeSameDay: Bool) -> Ledger {
        var next = ledger
        let imported = rows.filter { $0.selected }.compactMap(\.trade)
        next.trades = merge(ledger.orderedTrades, imported, insertBeforeSameDay: insertBeforeSameDay)
        return next
    }

    static func batchProblem(ledger: Ledger, rows: [ImportRow], insertBeforeSameDay: Bool) -> String? {
        validate(candidate(ledger: ledger, rows: rows, insertBeforeSameDay: insertBeforeSameDay))
    }

    /// 同日相对顺序由用户选择：默认追加到同日已有交易之后，也可插入到同日已有交易之前。
    /// 合并后统一按数组顺序重排 sequence，保持 (日期, sequence) 排序语义。
    static func merge(_ existing: [Trade], _ imported: [Trade], insertBeforeSameDay: Bool) -> [Trade] {
        var result = existing.sorted { $0.date == $1.date ? $0.sequence < $1.sequence : $0.date < $1.date }
        for trade in imported {
            if insertBeforeSameDay {
                if let index = result.firstIndex(where: { $0.date >= trade.date }) { result.insert(trade, at: index) }
                else { result.append(trade) }
            } else if let index = result.lastIndex(where: { $0.date <= trade.date }) {
                result.insert(trade, at: index + 1)
            } else {
                result.insert(trade, at: 0)
            }
        }
        return result.enumerated().map { index, trade in
            var copy = trade
            copy.sequence = index
            return copy
        }
    }

    /// 候选账本的规则校验；返回 nil 表示可以导入。
    static func validate(_ ledger: Ledger) -> String? {
        var quantity: [String: Decimal] = [:]
        for trade in ledger.orderedTrades {
            let current = quantity[trade.symbol] ?? 0
            if trade.side == .sell {
                guard current >= trade.quantity else {
                    return "\(trade.symbol) 在 \(trade.date) 的卖出数量超过持有数量，请核对顺序或数量。"
                }
                quantity[trade.symbol] = current - trade.quantity
            } else {
                guard current + trade.quantity < Decimal(1_000_000_000) else {
                    return "\(trade.symbol) 的持有数量超出支持范围。"
                }
                quantity[trade.symbol] = current + trade.quantity
            }
        }
        return nil
    }

    private static func signature(_ date: String, _ symbol: String, _ side: TradeSide,
                                  _ quantity: Decimal, _ price: Decimal, _ fee: Decimal) -> String {
        [date, symbol, side.rawValue, "\(quantity)", "\(price)", "\(fee)"].joined(separator: "|")
    }

    static let template = "Trade Date,Symbol,Side,Quantity,Price,Fee,Execution ID,Currency,Note\n2026-09-17,AAPL,Buy,10,229.15,1.00,EX-0001,USD,示例行"
}
