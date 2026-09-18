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
