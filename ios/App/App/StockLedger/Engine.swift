import Foundation

// 2.0 计算引擎：口径与 1.x 一致（移动平均成本、期初边界、买卖联动现金）。

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
    var positions: [Position]
    var open: [Position]
    var missing: [Position]
    var cost: Decimal
    var realized: Decimal
    var value: Decimal?
    var unrealized: Decimal?
    var totalProfit: Decimal?
    var gains: [UUID: Decimal]
    var fees: Decimal
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
            let gross = trade.quantity * trade.price
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

    // MARK: - 收益日历

    struct Contribution: Identifiable {
        var symbol: String
        var profit: Decimal?
        var reason: String?
        var id: String { symbol }
    }

    struct DayReturn: Identifiable {
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
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: date) else { return false }
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
                if isSplit { reason = "发现拆股，需先核对股数与成本" }
                else if stray.contains(symbol) { reason = "相邻交易日之间有交易记录，请核对美东交易日期" }
                else if gap, startQty > 0 { reason = "相邻收盘记录之间有未确认日期" }
                else if startQty > 0, before == nil { reason = "缺少 \(previous ?? "前一交易日") 收盘价" }
                else if endQty > 0, after == nil { reason = "缺少 \(date) 收盘价" }

                if endQty > 0, let after, !isSplit { value += endQty * after } else if endQty > 0 { endComplete = false }
                if isSplit { endComplete = false }

                if let reason {
                    missing.append("\(symbol)：\(reason)")
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
        var buyQuantity: Decimal = 0
        var sellQuantity: Decimal = 0
        var fees: Decimal = 0
        var realized: Decimal = 0
        var hasRealized = false
    }

    static func range(_ ledger: Ledger, from: String, to: String, side: TradeSide?, query: String) -> RangeResult {
        let summary = summary(ledger)
        var result = RangeResult()
        let keyword = query.trimmingCharacters(in: .whitespaces).lowercased()
        for trade in ledger.trades {
            if !from.isEmpty && trade.date < from { continue }
            if !to.isEmpty && trade.date > to { continue }
            if let side, trade.side != side { continue }
            if !keyword.isEmpty {
                let haystack = (trade.symbol + " " + trade.note).lowercased()
                if !haystack.contains(keyword) { continue }
            }
            result.list.append(trade)
            result.fees += trade.fee
            if trade.side == .buy { result.buyQuantity += trade.quantity } else { result.sellQuantity += trade.quantity }
            if trade.side == .sell, let gain = summary.gains[trade.id] {
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
        var pnl: Decimal?
        var percent: Decimal?
        var caption: String
        var missing: [String] = []
        var rows: [TodayRow] = []
        var tradedToday = 0
        var basis: Decimal?
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
                    reason = "缺少上一交易日收盘价"
                } else if let date = previousCloseDates[symbol], date >= today {
                    reason = "上一收盘价日期异常，请重新同步行情"
                }
            }
            if reason == nil, endQty > 0 {
                if let quote {
                    if quote.date < today { reason = "缺少 \(today) 当日报价（当前报价为 \(quote.date)）" }
                } else {
                    reason = "缺少当日报价"
                }
            }

            if let reason {
                complete = false
                missing.append("\(symbol)：\(reason)")
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

        var caption = "美东 \(today)"
        if !previousCloseDates.isEmpty, let date = previousCloseDates.values.min() {
            caption += " · 对比 \(date) 收盘"
        } else if !previousClose.isEmpty {
            caption += " · 对比上一交易日收盘"
        }
        if todayTrades.isEmpty == false { caption += " · 今日 \(todayTrades.count) 笔交易已计入" }
        if !complete { caption = missing.count > 1 ? "缺少 \(missing.count) 项行情 · 待补全" : "缺少行情 · 待补全" }

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
