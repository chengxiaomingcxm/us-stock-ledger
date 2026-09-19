import Foundation

/// 示例账本生成器：**全部为虚构数据**，不含任何真实持仓、交易、盈亏或账户信息。
///
/// 设计取舍：
/// - **相对「现在」生成**：交易日历以最近一个交易日收尾，示例数据不会过期，截图与展示长期有效。
///   测试传入固定 `now` 即可完全复现。
/// - **价格序列与交易共用一份数据**：买入价直接取该交易日的收盘价，所以成本、市值、浮动/已实现
///   收益与每日收益日历天然自洽，不会出现「图表和持仓对不上」。
/// - **自带确定性伪随机**：用 LCG 而不是系统随机数，保证同一 `now` 下生成结果逐字节一致。
/// - **不联网、不看 API Key**：示例数据自带报价与历史收盘价，Demo 模式不需要行情接口。
///
/// 已知边界（`ponytail:`）：交易日历复用 `Engine.knownClosed`，它的休市日表只覆盖 2026–2028。
/// 因此只要运行日期落在 2026 年，节日就不会被当成交易日；更早的日期只会让个别假日被算作交易日，
/// 属于外观问题，不影响账本与计算。升级路径：把休市日表扩展到更早年份。
enum DemoData {
    /// 交易日窗口长度。170 个交易日约 8 个月，足够填满日历页与收益曲线，文件又不会过大。
    static let sessionCount = 170

    /// 自选标的与它们在这段时间里的价格区间（起 → 止）。价格全部是编造的。
    private static let universe: [(symbol: String, start: String, end: String)] = [
        ("VOO", "471.20", "578.05"),
        ("AAPL", "152.30", "229.15"),
        ("MSFT", "341.60", "512.40"),
        ("NVDA", "88.40", "174.30"),
        ("SGOV", "100.42", "103.15"),
        ("TSLA", "288.00", "254.60"),
    ]

    /// 一笔示例交易：`at` 是交易日窗口内的下标，价格由当天的收盘价决定，不手写。
    private struct Seed {
        var at: Int
        var symbol: String
        var side: TradeSide
        var quantity: String
        var fee: String = "1"
        var note: String = ""
    }

    /// 32 笔买卖：`TSLA` 全部卖出（亏损），其余 5 只留有仓位；部分止盈、加仓、减仓、定投都有。
    /// 每一笔卖出的数量都不超过当时的持仓——这是账本自身的不变量，示例数据也必须满足。
    private static let seeds: [Seed] = [
        Seed(at: 1, symbol: "SGOV", side: .buy, quantity: "60"),
        Seed(at: 4, symbol: "VOO", side: .buy, quantity: "6", note: L10n.tr("示例：定投 ETF")),
        Seed(at: 8, symbol: "AAPL", side: .buy, quantity: "20"),
        Seed(at: 13, symbol: "MSFT", side: .buy, quantity: "5"),
        Seed(at: 16, symbol: "SGOV", side: .buy, quantity: "20"),
        Seed(at: 22, symbol: "TSLA", side: .buy, quantity: "10"),
        Seed(at: 27, symbol: "VOO", side: .buy, quantity: "5"),
        Seed(at: 32, symbol: "NVDA", side: .buy, quantity: "40"),
        Seed(at: 37, symbol: "AAPL", side: .buy, quantity: "10"),
        Seed(at: 43, symbol: "MSFT", side: .buy, quantity: "3"),
        Seed(at: 49, symbol: "SGOV", side: .buy, quantity: "25"),
        Seed(at: 55, symbol: "NVDA", side: .sell, quantity: "15", note: L10n.tr("示例：部分止盈")),
        Seed(at: 61, symbol: "VOO", side: .buy, quantity: "4"),
        Seed(at: 66, symbol: "AAPL", side: .sell, quantity: "8", note: L10n.tr("示例：部分止盈")),
        Seed(at: 72, symbol: "NVDA", side: .buy, quantity: "20"),
        Seed(at: 79, symbol: "TSLA", side: .sell, quantity: "10", note: L10n.tr("示例：止损卖出")),
        Seed(at: 85, symbol: "SGOV", side: .buy, quantity: "30"),
        Seed(at: 90, symbol: "AAPL", side: .sell, quantity: "4"),
        Seed(at: 97, symbol: "MSFT", side: .buy, quantity: "2"),
        Seed(at: 103, symbol: "VOO", side: .buy, quantity: "3"),
        Seed(at: 109, symbol: "NVDA", side: .sell, quantity: "5"),
        Seed(at: 116, symbol: "AAPL", side: .buy, quantity: "6"),
        Seed(at: 123, symbol: "SGOV", side: .sell, quantity: "55"),
        Seed(at: 130, symbol: "MSFT", side: .sell, quantity: "2"),
        Seed(at: 136, symbol: "NVDA", side: .buy, quantity: "5"),
        Seed(at: 142, symbol: "VOO", side: .sell, quantity: "3"),
        Seed(at: 147, symbol: "AAPL", side: .sell, quantity: "6"),
        Seed(at: 152, symbol: "SGOV", side: .buy, quantity: "20"),
        Seed(at: 157, symbol: "MSFT", side: .buy, quantity: "1"),
        Seed(at: 161, symbol: "NVDA", side: .sell, quantity: "3"),
        Seed(at: 164, symbol: "VOO", side: .buy, quantity: "2"),
        Seed(at: 166, symbol: "AAPL", side: .buy, quantity: "2"),
    ]

    /// 一笔示例现金流水：`at` 是交易日窗口内的下标。
    private struct CashSeed {
        var at: Int
        var kind: CashKind
        var amount: String
        var tax: String?
        var symbol: String?
        var note: String
    }

    /// 入金 / 出金 / 分红 / 账户费用。现金余额在整段时间里保持为正——
    /// 示例要像一笔真能成交的账户，不能出现透支。（`DemoModeTests` 会重放现金链来守这条不变量。）
    private static let cashSeeds: [CashSeed] = [
        CashSeed(at: 1, kind: .deposit, amount: "22000", tax: nil, symbol: nil, note: L10n.tr("示例入金")),
        CashSeed(at: 18, kind: .fee, amount: "1.25", tax: nil, symbol: nil, note: L10n.tr("示例账户费用")),
        CashSeed(at: 30, kind: .deposit, amount: "9000", tax: nil, symbol: nil, note: L10n.tr("示例入金")),
        CashSeed(at: 45, kind: .dividend, amount: "15.62", tax: "2.34", symbol: "VOO", note: L10n.tr("示例分红")),
        CashSeed(at: 62, kind: .dividend, amount: "5.72", tax: "0.86", symbol: "AAPL", note: L10n.tr("示例分红")),
        CashSeed(at: 80, kind: .dividend, amount: "55.35", tax: nil, symbol: "SGOV", note: L10n.tr("示例分红")),
        CashSeed(at: 95, kind: .dividend, amount: "8.30", tax: "1.25", symbol: "MSFT", note: L10n.tr("示例分红")),
        CashSeed(at: 100, kind: .deposit, amount: "6000", tax: nil, symbol: nil, note: L10n.tr("示例入金")),
        CashSeed(at: 112, kind: .fee, amount: "1.25", tax: nil, symbol: nil, note: L10n.tr("示例账户费用")),
        CashSeed(at: 126, kind: .withdraw, amount: "3000", tax: nil, symbol: nil, note: L10n.tr("示例出金")),
        CashSeed(at: 138, kind: .dividend, amount: "23.70", tax: "3.56", symbol: "VOO", note: L10n.tr("示例分红")),
        CashSeed(at: 150, kind: .dividend, amount: "4.86", tax: "0.73", symbol: "AAPL", note: L10n.tr("示例分红")),
    ]

    /// 生成一份完整的示例账本。`now` 用来锚定最近一个交易日；测试传固定值即可复现。
    static func ledger(now: Date = Date()) -> Ledger {
        let sessions = sessions(endingAt: now)
        var series: [String: [Decimal]] = [:]
        for item in universe {
            series[item.symbol] = prices(symbol: item.symbol, from: item.start, to: item.end, sessions: sessions)
        }
        func close(_ symbol: String, _ index: Int) -> Decimal {
            guard let values = series[symbol], values.indices.contains(index) else { return 0 }
            return values[index]
        }

        var ledger = Ledger()
        // 种子下标是按 `sessionCount` 写死的；钳到窗口内，避免改种子表时越界崩溃。
        // （`DemoModeTests` 的现金链重放会在下标塔缩时直接报错。）
        func day(_ index: Int) -> Int { min(max(index, 0), sessions.count - 1) }
        for seed in seeds {
            ledger.trades.append(Trade(id: UUID(), sequence: ledger.trades.count, symbol: seed.symbol,
                                       side: seed.side, date: sessions[day(seed.at)],
                                       quantity: amount(seed.quantity), price: close(seed.symbol, day(seed.at)),
                                       fee: amount(seed.fee), note: seed.note,
                                       source: "manual", externalId: nil))
        }

        // 仍持有仓位的标的才有报价；全部卖出的标的（TSLA）只留在历史交易里。
        var held: [String: Decimal] = [:]
        for seed in seeds {
            held[seed.symbol, default: 0] += seed.side == .buy ? amount(seed.quantity) : -amount(seed.quantity)
        }
        let last = sessions.count - 1
        let previous = max(last - 1, 0)
        ledger.quotes = universe.map { $0.symbol }.filter { (held[$0] ?? 0) > 0 }.map { symbol in
            Quote(symbol: symbol, price: close(symbol, last), date: sessions[last],
                  source: nil, fetchedAt: nil,
                  previousClose: close(symbol, previous), previousCloseDate: sessions[previous])
        }

        ledger.opening = CashOpening(amount: amount("3000"), date: sessions[0], note: L10n.tr("示例期初余额"))
        for seed in cashSeeds {
            ledger.cash.append(CashRecord(id: UUID(), sequence: ledger.cash.count, date: sessions[day(seed.at)],
                                          kind: seed.kind, amount: amount(seed.amount),
                                          tax: seed.tax.map(amount), symbol: seed.symbol, note: seed.note,
                                          source: "manual", externalId: nil))
        }

        ledger.history.sessions = sessions
        ledger.history.closes = universe.flatMap { item in
            (series[item.symbol] ?? []).enumerated().map { entry in
                PricePoint(symbol: item.symbol, date: sessions[entry.offset], price: entry.element)
            }
        }
        return ledger
    }

    // MARK: - 内部

    /// 最近 `sessionCount` 个交易日，升序；最后一天是「今天或最近一个工作日」。
    private static func sessions(endingAt now: Date) -> [String] {
        var days: [String] = []
        var cursor = MarketClock.utcDay(MarketClock.date(now)) ?? now
        while days.count < sessionCount {
            let text = MarketClock.utcDate(cursor)
            if !Engine.knownClosed(text) { days.append(text) }
            cursor = cursor.addingTimeInterval(-86_400)
        }
        return Array(days.reversed())
    }

    /// 从起价线性走到止价，叠加一个确定性小噪声；最后一天强制等于止价，
    /// 这样「最后收盘价」与持仓页上的报价完全一致。
    private static func prices(symbol: String, from start: String, to end: String,
                               sessions: [String]) -> [Decimal] {
        let first = amount(start), target = amount(end)
        let steps = max(sessions.count - 1, 1)
        var noise = Noise(fingerprint(symbol))
        return sessions.indices.map { index in
            guard index < steps else { return target }
            let base = first + (target - first) * Decimal(index) / Decimal(steps)
            let wobble = Decimal(noise.next(17) - 8) / 1000
            return rounded(base * (1 + wobble))
        }
    }

    private static func amount(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US")) ?? 0
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    /// 由标的代码得到稳定的种子。不用 `hashValue`：它每次进程启动都会变，破坏可复现性。
    private static func fingerprint(_ text: String) -> UInt64 {
        text.utf8.reduce(5381) { ($0 &* 33) &+ UInt64($1) }
    }

    /// 确定性线性同余伪随机数，只为价格噪声服务。
    private struct Noise {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed | 1 }
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }
}
