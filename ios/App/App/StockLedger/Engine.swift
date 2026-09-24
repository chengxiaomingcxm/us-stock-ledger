import Foundation
import CoreGraphics

// 计算引擎：移动平均成本、期初边界、买卖联动现金。

struct Position: Identifiable {
    var symbol: String
    var quantity: Decimal
    var cost: Decimal
    var realized: Decimal
    var average: Decimal { quantity > 0 ? cost / quantity : 0 }
    var quote: Quote?
    var value: Decimal? { quote.map { quantity * $0.price } }
    var unrealized: Decimal? { value.map { $0 - cost } }
    var id: String { symbol }
}

struct LedgerSummary {
    var positions: [Position] = []
    var open: [Position] = []
    var missing: [Position] = []
    var cost: Decimal = 0
    var realized: Decimal = 0
    var value: Decimal? = nil
    var unrealized: Decimal? = nil
    var totalProfit: Decimal? = nil
    var gains: [UUID: Decimal] = [:]
    var fees: Decimal = 0
}

struct CashTotals {
    var opening: Decimal = 0
    var deposit: Decimal = 0
    var withdraw: Decimal = 0
    var dividend: Decimal = 0
    var tax: Decimal = 0
    var fee: Decimal = 0
    var buyOut: Decimal = 0
    var sellIn: Decimal = 0
    var net: Decimal = 0
    var balance: Decimal?
    var investNet: Decimal = 0      // 边界内：分红净额 − 费用（现金面板口径）
    var investNetAll: Decimal = 0   // 全历史：用于账户总收益
    var externalNet: Decimal = 0
    var excludedRecords = 0
    var excludedTrades = 0
    var tradeNet: Decimal { sellIn - buyOut }
}

enum Engine {
    static func summary(_ ledger: Ledger) -> LedgerSummary {
        var map: [String: Position] = [:]
        var gains: [UUID: Decimal] = [:]
        var fees: Decimal = 0

        for trade in ledger.orderedTrades {
            var position = map[trade.symbol] ?? Position(symbol: trade.symbol, quantity: 0, cost: 0, realized: 0)
            let gross = trade.gross
            fees += trade.fee
            if trade.side == .buy {
                position.cost += gross + trade.fee
                position.quantity += trade.quantity
            } else {
                let removed = trade.quantity == position.quantity ? position.cost : position.cost * trade.quantity / position.quantity
                let profit = gross - trade.fee - removed
                position.realized += profit
                gains[trade.id] = profit
                position.cost -= removed
                position.quantity -= trade.quantity
            }
            map[trade.symbol] = position
        }

        var positions = map.values.sorted { $0.symbol < $1.symbol }
        for index in positions.indices {
            positions[index].quote = ledger.quote(for: positions[index].symbol)
        }
        let open = positions.filter { $0.quantity > 0 }
        let missing = open.filter { $0.quote == nil }
        let cost = open.reduce(Decimal(0)) { $0 + $1.cost }
        let realized = positions.reduce(Decimal(0)) { $0 + $1.realized }
        let value = missing.isEmpty ? open.reduce(Decimal(0)) { $0 + ($1.value ?? 0) } : nil
        let unrealized = value.map { $0 - cost }
        return LedgerSummary(
            positions: positions,
            open: open,
            missing: missing,
            cost: cost,
            realized: realized,
            value: value,
            unrealized: unrealized,
            totalProfit: unrealized.map { $0 + realized },
            gains: gains,
            fees: fees
        )
    }

    /// 一个「卖出超过当时可用股数」的历史时点及其超额股数。
    struct Oversell: Identifiable, Equatable {
        var symbol: String
        var date: String
        var sequence: Int
        var quantity: Decimal
        var id: String { "\(symbol)|\(date)|\(sequence)" }
    }

    /// 交易不变量：按时间顺序重放，找出每个「卖出超过当时可用股数」的时点。
    /// 只看最终数量是不够的：Jan1 买 100 / Jan2 卖 100 / Jan3 买 100 的最终持仓虽然为 100，
    /// 但删掉 Jan1 的买入后 Jan2 就已超卖，因此必须逐笔重放（负持仓向后续时点累计）。
    static func oversells(_ ledger: Ledger) -> [Oversell] {
        var holding: [String: Decimal] = [:]
        var found: [Oversell] = []
        for trade in ledger.orderedTrades {
            if trade.side == .buy {
                holding[trade.symbol, default: 0] += trade.quantity
            } else {
                let available = holding[trade.symbol] ?? 0
                if trade.quantity > available {
                    found.append(Oversell(symbol: trade.symbol, date: trade.date, sequence: trade.sequence,
                                          quantity: trade.quantity - available))
                }
                holding[trade.symbol] = available - trade.quantity
            }
        }
        return found
    }

    /// 期初余额是“期初日当天开始前”的现金；期初日及之后的入金、出金、分红、费用和买卖计入余额。
    /// 未设置期初时不根据股票历史推断现金，也不计入买卖现金流。
    static func cashTotals(_ ledger: Ledger) -> CashTotals {
        var totals = CashTotals()
        let opening = ledger.opening
        func inBoundary(_ date: String) -> Bool { opening.map { date >= $0.date } ?? true }

        for record in ledger.cash {
            if record.kind == .dividend { totals.investNetAll += record.amount - (record.tax ?? 0) }
            else if record.kind == .fee { totals.investNetAll -= record.amount }
            guard inBoundary(record.date) else { totals.excludedRecords += 1; continue }
            switch record.kind {
            case .deposit: totals.deposit += record.amount
            case .withdraw: totals.withdraw += record.amount
            case .dividend: totals.dividend += record.amount; totals.tax += record.tax ?? 0
            case .fee: totals.fee += record.amount
            }
            totals.net += record.net
        }
        if let opening {
            totals.opening = opening.amount
            for trade in ledger.orderedTrades {
                guard inBoundary(trade.date) else { totals.excludedTrades += 1; continue }
                if trade.side == .buy {
                    totals.buyOut += trade.gross + trade.fee
                    totals.net -= trade.gross + trade.fee
                } else {
                    totals.sellIn += trade.gross - trade.fee
                    totals.net += trade.gross - trade.fee
                }
            }
            totals.balance = opening.amount + totals.net
        }
        totals.investNet = totals.dividend - totals.tax - totals.fee
        totals.externalNet = totals.deposit - totals.withdraw
        return totals
    }

    static func isBeforeOpening(_ date: String, _ ledger: Ledger) -> Bool {
        guard let opening = ledger.opening else { return false }
        return date < opening.date
    }

    /// 报价是否明显过期（超过 4 个自然日）：只用于提示，不隐藏已有价格。
    static func isStaleQuote(_ quote: Quote, now: Date = Date()) -> Bool {
        guard let quoted = MarketClock.utcDay(quote.date),
              let today = MarketClock.utcDay(MarketClock.date(now)) else { return false }
        return today.timeIntervalSince(quoted) > 4 * 86_400
    }

    // MARK: - 收益日历

    struct Contribution: Identifiable, Equatable {
        var symbol: String
        var profit: Decimal?
        var reason: String?
        var id: String { symbol }
    }

    struct DayReturn: Identifiable, Equatable {
        var date: String
        var previous: String?
        var profit: Decimal?
        var cumulative: Decimal?
        var contributions: [Contribution]
        var missing: [String]
        var id: String { date }
    }

    /// 已公布的 NYSE 休市日（2026–2028）；未知工作日绝不当作休市。
    private static let holidays: Set<String> = [
        "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19", "2026-07-03",
        "2026-09-07", "2026-11-26", "2026-12-25",
        "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18", "2027-07-05",
        "2027-09-06", "2027-11-25", "2027-12-24",
        "2028-01-17", "2028-02-21", "2028-04-14", "2028-05-29", "2028-06-19", "2028-07-04", "2028-09-04",
        "2028-11-23", "2028-12-25",
    ]

    static func knownClosed(_ date: String) -> Bool {
        guard let parsed = MarketClock.utcDay(date) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = calendar.component(.weekday, from: parsed)
        return weekday == 1 || weekday == 7 || holidays.contains(date)
    }

    /// 每日收益：期末市值 − 期初（上一交易日收盘）市值 + 当日卖出净额 − 当日买入含费支出。
    /// 重放当前账本，历史交易被修改后不会留下过期收益；任一必需收盘价缺失时该日显示待补全。
    static func dailyReturns(_ ledger: Ledger) -> [DayReturn] {
        let sessions = ledger.history.sessions.sorted()
        let trades = ledger.orderedTrades
        guard !sessions.isEmpty, !trades.isEmpty else { return [] }

        var prices: [String: Decimal] = [:]
        for close in ledger.history.closes { prices[close.symbol + "|" + close.date] = close.price }
        var firstTrade: [String: String] = [:]
        for trade in trades where firstTrade[trade.symbol] == nil { firstTrade[trade.symbol] = trade.date }
        let splitSymbols = Set(ledger.history.splits.filter { split in
            guard let first = firstTrade[split.symbol] else { return false }
            return split.date >= first
        }.map(\.symbol))
        guard let firstDate = trades.first?.date else { return [] }

        var quantity: [String: Decimal] = [:]
        var cash = Decimal(0)
        var index = 0
        var output: [DayReturn] = []

        func apply(_ trade: Trade) -> Decimal {
            let net = trade.side == .buy ? -(trade.gross + trade.fee) : trade.gross - trade.fee
            quantity[trade.symbol, default: 0] += trade.side == .buy ? trade.quantity : -trade.quantity
            cash += net
            return net
        }

        for (position, date) in sessions.enumerated() {
            if Task.isCancelled { return [] }
            let previous = position > 0 ? sessions[position - 1] : nil
            if date < firstDate { continue }

            var stray: Set<String> = []
            while index < trades.count, trades[index].date < date {
                let trade = trades[index]
                index += 1
                if let previous, trade.date > previous { stray.insert(trade.symbol) }
                _ = apply(trade)
            }

            var gap = false
            if let previous, let start = MarketClock.utcDay(previous), let end = MarketClock.utcDay(date) {
                var cursor = start.addingTimeInterval(86_400)
                while cursor < end {
                    if !knownClosed(MarketClock.utcDate(cursor)) { gap = true; break }
                    cursor = cursor.addingTimeInterval(86_400)
                }
            }

            let opening = quantity
            var flows: [String: Decimal] = [:]
            while index < trades.count, trades[index].date == date {
                let trade = trades[index]
                index += 1
                flows[trade.symbol, default: 0] += apply(trade)
            }

            let symbols = Set(opening.filter { $0.value > 0 }.keys)
                .union(quantity.filter { $0.value > 0 }.keys)
                .union(flows.keys)
                .sorted()

            var total = Decimal(0)
            var value = Decimal(0)
            var endComplete = true
            var missing: [String] = []
            var contributions: [Contribution] = []

            for symbol in symbols {
                let startQty = opening[symbol] ?? 0
                let endQty = quantity[symbol] ?? 0
                let before = previous.flatMap { prices[symbol + "|" + $0] }
                let after = prices[symbol + "|" + date]
                let isSplit = splitSymbols.contains(symbol)
                var reason: String?
                if isSplit { reason = L10n.tr("发现拆股，需先核对股数与成本") }
                else if stray.contains(symbol) { reason = L10n.tr("相邻交易日之间有交易记录，请核对美东交易日期") }
                else if gap, startQty > 0 { reason = L10n.tr("相邻收盘记录之间有未确认日期") }
                else if startQty > 0, before == nil { reason = L10n.tr("缺少") + " \(previous ?? L10n.tr("前一交易日")) " + L10n.tr("收盘价") }
                else if endQty > 0, after == nil { reason = L10n.tr("缺少") + " \(date) " + L10n.tr("收盘价") }

                if endQty > 0, let after, !isSplit { value += endQty * after } else if endQty > 0 { endComplete = false }
                if isSplit { endComplete = false }

                if let reason {
                    missing.append(L10n.tr("{}：{}", symbol, reason))
                    contributions.append(Contribution(symbol: symbol, profit: nil, reason: reason))
                } else {
                    let endValue = endQty > 0 && after != nil ? endQty * after! : 0
                    let startValue = startQty > 0 && before != nil ? startQty * before! : 0
                    let profit = endValue - startValue + (flows[symbol] ?? 0)
                    total += profit
                    contributions.append(Contribution(symbol: symbol, profit: profit, reason: nil))
                }
            }

            if splitSymbols.contains(where: { firstTrade[$0].map { $0 <= date } ?? false }) { endComplete = false }

            output.append(DayReturn(
                date: date,
                previous: previous,
                profit: missing.isEmpty ? total : nil,
                cumulative: endComplete ? value + cash : nil,
                contributions: contributions,
                missing: missing
            ))
        }
        return output
    }

    /// Latest API marks replace only the most recent market-session row; prior days remain close-based.
    static func applyingLiveQuotes(_ days: [DayReturn], to ledger: Ledger, now: Date = Date()) -> [DayReturn] {
        let today = MarketClock.date(now)
        let liveQuotes = ledger.quotes.filter { $0.isLive && $0.date <= today && !isStaleQuote($0, now: now) }
        guard let date = liveQuotes.map(\.date).max(),
              days.last.map({ date >= $0.date }) ?? true else { return days }

        var previousClose: [String: Decimal] = [:]
        var previousCloseDates: [String: String] = [:]
        for quote in liveQuotes where quote.date == date {
            if let price = quote.previousClose, let previousDate = quote.previousCloseDate, previousDate < date {
                previousClose[quote.symbol] = price
                previousCloseDates[quote.symbol] = previousDate
            }
        }
        for symbol in Set(ledger.trades.map(\.symbol)) where previousClose[symbol] == nil {
            if let close = ledger.history.closes.filter({ $0.symbol == symbol && $0.date < date }).max(by: { $0.date < $1.date }) {
                previousClose[symbol] = close.price
                previousCloseDates[symbol] = close.date
            }
        }

        let result = todayPnl(ledger, previousClose: previousClose, previousCloseDates: previousCloseDates, today: date)
        let contributions = result.rows.map { Contribution(symbol: $0.symbol, profit: $0.pnl, reason: $0.reason) }
        let previous = days.last(where: { $0.date < date })
        let row = DayReturn(date: date, previous: previousCloseDates.values.min() ?? previous?.date,
                            profit: result.pnl, cumulative: result.pnl.flatMap { profit in previous?.cumulative.map { $0 + profit } },
                            contributions: contributions, missing: result.missing)
        var updated = days
        if let index = updated.firstIndex(where: { $0.date == date }) { updated[index] = row }
        else { updated.append(row); updated.sort { $0.date < $1.date } }
        return updated
    }

    struct MonthStats {
        var rows: [DayReturn] = []
        var complete = 0
        var missing = 0
        var profit = Decimal(0)
    }

    static func monthStats(_ days: [DayReturn], month: String) -> MonthStats {
        let rows = days.filter { $0.date.hasPrefix(month) }
        var stats = MonthStats(rows: rows)
        for row in rows {
            if let profit = row.profit { stats.profit += profit; stats.complete += 1 } else { stats.missing += 1 }
        }
        return stats
    }

    /// 交易区间筛选与汇总（日期区间、买卖类型、关键字）。
    struct RangeResult {
        var list: [Trade] = []
        var buyCount = 0
        var sellCount = 0
        /// 成交金额 = Σ(股数 × 成交价)，**不含手续费**；手续费单独列示，不混进金额。
        var buyAmount: Decimal = 0
        var sellAmount: Decimal = 0
        var fees: Decimal = 0
        var realized: Decimal = 0
        var hasRealized = false
    }

    static func range(_ ledger: Ledger, from: String, to: String, side: TradeSide?, query: String,
                      gains precomputed: [UUID: Decimal]? = nil,
                      ordered: [Trade]? = nil) -> RangeResult {
        var result = RangeResult()
        let gains = precomputed ?? summary(ledger).gains
        let keyword = query.trimmingCharacters(in: .whitespaces).lowercased()
        for trade in ordered ?? ledger.trades {
            if !from.isEmpty && trade.date < from { continue }
            if !to.isEmpty && trade.date > to { continue }
            if let side, trade.side != side { continue }
            if !keyword.isEmpty {
                let haystack = (trade.symbol + " " + trade.note).lowercased()
                if !haystack.contains(keyword) { continue }
            }
            result.list.append(trade)
            result.fees += trade.fee
            // 金额口径按产品定义：股数 × 成交价，不含手续费。
            // 不用 `gross`：那个在结单导入的行上等于银行舍入后的整笔交收额，
            // 会让同一个数同时表达「成交额」与「银行现金流」两种含义。
            if trade.side == .buy {
                result.buyCount += 1
                result.buyAmount += trade.quantity * trade.price
            } else {
                result.sellCount += 1
                result.sellAmount += trade.quantity * trade.price
            }
            if trade.side == .sell, let gain = gains[trade.id] {
                result.realized += gain
                result.hasRealized = true
            }
        }
        result.list.sort { $0.date == $1.date ? $0.sequence > $1.sequence : $0.date > $1.date }
        return result
    }

    /// 今日盈亏：期末市值 − 上一收盘市值 − 当日买入含费 + 当日卖出净额。
    /// 任一必需行情缺失时整体返回 nil（界面显示待补全），绝不按零计算。
    struct TodayRow: Identifiable {
        var symbol: String
        var pnl: Decimal?
        var reason: String?
        var id: String { symbol }
    }

    struct TodayResult {
        var title: String = L10n.tr("今日盈亏")
        var pnl: Decimal?
        var percent: Decimal?
        var caption: String
        var missing: [String] = []
        var rows: [TodayRow] = []
        var tradedToday = 0
        var basis: Decimal?
    }

    /// Evaluate a single actual quote session, excluding trades made after that session.
    static func displayedReturn(_ ledger: Ledger, now: Date = Date()) -> TodayResult {
        let today = MarketClock.date(now)
        let symbols = Set(ledger.trades.map(\.symbol))
        let quotes = ledger.quotes.filter { symbols.contains($0.symbol) && $0.date <= today }
        guard let date = quotes.map(\.date).max() else {
            return TodayResult(caption: L10n.tr("尚无报价，请同步行情"))
        }
        var before: [String: Decimal] = [:]
        var dates: [String: String] = [:]
        for quote in quotes where quote.date == date {
            if let value = quote.previousClose, !(quote.source == "finnhub-live" && quote.date < today) {
                before[quote.symbol] = value
                if let day = quote.previousCloseDate { dates[quote.symbol] = day }
            }
        }
        // 没有 previousClose 时用最近的历史收盘价补上当日基准（行情来源不提供，或从备份恢复后）。
        let history = Dictionary(grouping: ledger.history.closes) { $0.symbol }
        for symbol in symbols where before[symbol] == nil {
            if let close = history[symbol]?.filter({ $0.date < date }).max(by: { $0.date < $1.date }),
               let start = MarketClock.utcDay(close.date), let end = MarketClock.utcDay(date),
               end.timeIntervalSince(start) <= 10 * 86400,
               stride(from: start.timeIntervalSince1970 + 86400, to: end.timeIntervalSince1970, by: 86400).allSatisfy({ knownClosed(MarketClock.utcDate(Date(timeIntervalSince1970: $0))) }) {
                before[symbol] = close.price; dates[symbol] = close.date
            }
        }
        var result = todayPnl(ledger, previousClose: before, previousCloseDates: dates, today: date)
        let closed = quotes.filter { $0.date == date }.allSatisfy { $0.source == "yahoo-close" }
        result.title = closed ? L10n.tr("最近收盘收益") : (date == today ? L10n.tr("今日盈亏") : L10n.tr("最近报价日收益"))
        result.caption = "\(L10n.tr("美东")) \(date) · " + (closed ? L10n.tr("已完成交易日收盘") : L10n.tr("最新报价")) + (result.pnl == nil ? " · " + L10n.tr("待补全") : "")
        return result
    }

    static func todayPnl(_ ledger: Ledger, previousClose: [String: Decimal], previousCloseDates: [String: String] = [:], today: String) -> TodayResult {
        // 期初股数＝今日之前所有交易累计；当日买卖按成交金额与手续费单独计入，不重复放大市值变化。
        var opening: [String: Decimal] = [:]
        for trade in ledger.orderedTrades where trade.date < today {
            opening[trade.symbol, default: 0] += trade.side == .buy ? trade.quantity : -trade.quantity
        }
        let todayTrades = ledger.orderedTrades.filter { $0.date == today }
        let symbols = Set(opening.filter { $0.value != 0 }.keys).union(todayTrades.map(\.symbol)).sorted()

        var rows: [TodayRow] = []
        var missing: [String] = []
        var total = Decimal(0)
        var basis = Decimal(0)
        var complete = true

        for symbol in symbols {
            let openQty = opening[symbol] ?? 0
            let buys = todayTrades.filter { $0.symbol == symbol && $0.side == .buy }
            let sells = todayTrades.filter { $0.symbol == symbol && $0.side == .sell }
            let bought = buys.reduce(Decimal(0)) { $0 + $1.quantity }
            let sold = sells.reduce(Decimal(0)) { $0 + $1.quantity }
            let endQty = openQty + bought - sold
            let quote = ledger.quote(for: symbol)
            var reason: String?

            if openQty > 0 {
                if previousClose[symbol] == nil {
                    reason = L10n.tr("缺少上一交易日收盘价")
                } else if let date = previousCloseDates[symbol], date >= today {
                    reason = L10n.tr("上一收盘价日期异常，请重新同步行情")
                }
            }
            if reason == nil, endQty > 0 {
                if let quote {
                    if quote.date != today { reason = L10n.tr("缺少") + " \(today) " + L10n.tr("报价") + " (\(quote.date))" }
                } else {
                    reason = L10n.tr("缺少当日报价")
                }
            }

            if let reason {
                complete = false
                missing.append(L10n.tr("{}：{}", symbol, reason))
                rows.append(TodayRow(symbol: symbol, pnl: nil, reason: reason))
                continue
            }

            let startValue = openQty > 0 ? openQty * previousClose[symbol]! : 0
            let endValue = endQty > 0 ? endQty * quote!.price : 0
            let buyCost = buys.reduce(Decimal(0)) { $0 + $1.gross + $1.fee }
            let sellNet = sells.reduce(Decimal(0)) { $0 + $1.gross - $1.fee }
            if openQty > 0 { basis += startValue }
            let profit = endValue - startValue - buyCost + sellNet
            total += profit
            rows.append(TodayRow(symbol: symbol, pnl: profit, reason: nil))
        }

        var caption = "\(L10n.tr("美东")) \(today)"
        if !previousCloseDates.isEmpty, let date = previousCloseDates.values.min() {
            caption += " · \(L10n.tr("对比")) \(date) " + L10n.tr("收盘")
        } else if !previousClose.isEmpty {
            caption += " · " + L10n.tr("对比上一交易日收盘")
        }
        if todayTrades.isEmpty == false { caption += " · \(L10n.tr("今日")) \(todayTrades.count) " + L10n.tr("笔交易已计入") }
        if !complete { caption = missing.count > 1 ? L10n.tr("缺少") + " \(missing.count) " + L10n.tr("项行情 · 待补全") : L10n.tr("缺少行情 · 待补全") }

        return TodayResult(
            pnl: complete ? total : nil,
            percent: complete && basis > 0 ? total / basis : nil,
            caption: caption,
            missing: missing,
            rows: rows,
            tradedToday: todayTrades.count,
            basis: complete ? basis : nil
        )
    }
}

// Precomputed off the main actor; rendering never scans or parses the history.
struct InsightsPresentation {
    struct Cell: Identifiable {
        var key: String
        var day: Int?
        var row: Engine.DayReturn?
        var id: String { key }
    }
    struct Month { var stats: Engine.MonthStats; var cells: [Cell] }
    let revision = UUID()
    var months: [String] = []
    var calendar: [String: Month] = [:]
    var points: [(date: String, value: Decimal)] = []
    var values: [Double] = []
    var ticks: [Int] = []
    var highest: Decimal = 0
    var lowest: Decimal = 0
    var maximum: Double = 0
    var minimum: Double = 0
    var missingDays = 0
    var curve: CGPath = CGMutablePath()
    init(days: [Engine.DayReturn] = []) {
        var running = Decimal(0)
        let grouped = Dictionary(grouping: days) { String($0.date.prefix(7)) }
        months = grouped.keys.sorted()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = MarketClock.timeZone
        for month in months {
            let rows = grouped[month] ?? []
            var stats = Engine.MonthStats(rows: rows)
            for row in rows {
                if let profit = row.profit { stats.profit += profit; stats.complete += 1 }
                else { stats.missing += 1 }
            }
            guard let first = MarketClock.day(month + "-01"), let range = cal.range(of: .day, in: .month, for: first) else { continue }
            let map = Dictionary(rows.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
            var cells: [Cell] = []
            for offset in 1..<cal.component(.weekday, from: first) {
                cells.append(Cell(key: "blank-\(offset)", day: nil, row: nil))
            }
            for day in range {
                let date = String(format: "%@-%02d", month, day)
                cells.append(Cell(key: date, day: day, row: map[date]))
            }
            calendar[month] = Month(stats: stats, cells: cells)
        }
        for day in days {
            if let profit = day.profit { running += profit } else { missingDays += 1 }
            points.append((day.date, running))
            values.append(NSDecimalNumber(decimal: running).doubleValue)
        }
        highest = points.map(\.value).max() ?? 0
        lowest = points.map(\.value).min() ?? 0
        maximum = max(values.max() ?? 0, 0)
        minimum = min(values.min() ?? 0, 0)
        let path = CGMutablePath()
        let span = max(maximum - minimum, 0.0001)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: Double(index) / Double(max(values.count - 1, 1)), y: (maximum - value) / span)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        curve = path
        if !days.isEmpty {
            ticks = Array(Set((0..<min(6, days.count)).map { $0 * (days.count - 1) / max(min(6, days.count) - 1, 1) })).sorted()
        }
    }

    /// 曲线纵轴的参考值：上限、零轴、下限，位置是**归一化的**（0 = 顶边，1 = 底边）。
    ///
    /// `maximum` / `minimum` 已经按 0 夹紧，所以全为正的历史里下限本身就是零轴——两条会落在同一条边上。
    /// `proximity` 之内只保留先出现的那条：宁可少标一个数，也不把两行字压在一起。
    ///
    /// 带上 `$`：同一张卡片的大数走 `Fmt.signedMoney`（`+$58.15`），参考值不带符号会被读成百分比。
    /// 本 App 只记美元（结单导入会跳过非美元行），所以符号是固定的。
    func axisReferences(proximity: CGFloat = 0.09) -> [(text: String, position: CGFloat)] {
        let span = max(maximum - minimum, 0.0001)
        var placed: [CGFloat] = []
        var rows: [(text: String, position: CGFloat)] = []
        for value in [maximum, 0, minimum] {
            let position = CGFloat((maximum - value) / span)
            guard !placed.contains(where: { abs($0 - position) < proximity }) else { continue }
            placed.append(position)
            rows.append((Fmt.compactMoney(Decimal(value)), position))
        }
        return rows
    }
}
struct LedgerDerived {
    var displayReturn = Engine.TodayResult(caption: L10n.tr("正在计算"))
    var unknownDividendTax = 0
    var summary = LedgerSummary()
    var cash = CashTotals()
    var trades: [Trade] = []
    var cashRecords: [CashRecord] = []
    var symbols: [String] = []
    var days: [Engine.DayReturn] = []
    var insights = InsightsPresentation()
    static func compute(_ ledger: Ledger, cached: LedgerDerived?, historyUnchanged: Bool) -> LedgerDerived {
        var value = LedgerDerived()
        value.summary = Engine.summary(ledger)
        value.displayReturn = Engine.displayedReturn(ledger)
        value.cash = Engine.cashTotals(ledger)
        value.unknownDividendTax = ledger.cash.filter { $0.source == "hsbc-statement-net" && $0.tax == nil }.count
        value.trades = ledger.orderedTrades
        value.cashRecords = ledger.orderedCash
        value.symbols = value.summary.open.map(\.symbol)
        let historicalDays = historyUnchanged ? (cached?.days ?? Engine.dailyReturns(ledger)) : Engine.dailyReturns(ledger)
        value.days = Engine.applyingLiveQuotes(historicalDays, to: ledger)
        if historyUnchanged, let cached, value.days == cached.days {
            value.insights = cached.insights
        } else if !Task.isCancelled {
            value.insights = InsightsPresentation(days: value.days)
        }
        return value
    }
}
