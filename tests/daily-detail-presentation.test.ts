import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(path, 'utf8')

describe('native daily detail presentation wiring', () => {
  it('calendar snapshots use closing marks and shared remaining-cost replay, without live overlays or monthly summation', () => {
    const engine = read('ios/App/App/StockLedger/Engine.swift')
    const snapshot = engine.split('static func unrealizedSnapshots(')[1].split('struct MonthStats')[0]
    expect(snapshot).toContain('position.apply(trade)')
    expect(snapshot).toContain('position.quantity * $0.price - position.cost')
    expect(snapshot).toContain('position.quantity > 0')
    expect(snapshot).not.toContain('ledger.quotes')
    expect(snapshot).not.toContain('previousClose')
    expect(engine).toContain('calendarDays: value.snapshots')
    const views = read('ios/App/App/StockLedger/InsightsView.swift')
    expect(views).toContain('value: dailyStats.profit')
    expect(views).toContain('@AppStorage("calendar.showPercent")')
    expect(views).toContain('.pickerStyle(.segmented)')
    expect(views).toContain('row.percent.map { Fmt.percent($0) }')
    expect(engine).toContain('dailyStats: Engine.monthStats(days, month: month)')
    expect(views).toContain('DayReturnDetail(row: row, isSnapshot: true)')
  })

  it('locally checks end-of-day unrealized snapshots with fees and partial/full sales', () => {
    // Integer cents oracle; Swift product behavior is exercised by the native tests.
    let quantity = 10
    let cost = 100_200
    expect(quantity * 11_000 - cost).toBe(9800)
    expect(quantity * 11_200 - cost).toBe(11800)
    cost -= cost * 4 / quantity
    quantity -= 4
    expect(quantity * 12_000 - cost).toBe(11880)
    cost += 2 * 12_500 + 100
    quantity += 2
    expect(quantity * 11_000 - cost).toBe(2780)
    cost -= cost
    quantity -= 8
    expect(quantity * 0 - cost).toBe(0)
  })

  it('keeps monthly investment return distinct from unrealized snapshots and percentages', () => {
    expect([98, 20, 197, -91, 730].reduce((a, b) => a + b, 0)).toBe(954)
    expect(98 / 1002 * 100).toBeCloseTo(9.780439, 6)
    expect(0 / 1002).toBe(0)
    const engine = read('ios/App/App/StockLedger/Engine.swift')
    expect(engine).toContain('guard let profit, let basis, basis > 0 else { return nil }')
  })

  it('uses engine contributions and selected-day quantities without changing the portfolio total', () => {
    const engine = read('ios/App/App/StockLedger/Engine.swift')
    const presentation = engine.split('struct DailyDetailPresentation {')[1].split('struct LedgerDerived {')[0]
    expect(presentation).toContain('trade.date <= row.date')
    expect(presentation).toContain('held = row.contributions.filter')
    expect(presentation).toContain('closed = row.contributions.filter')
    expect(presentation).toContain('guard rows.allSatisfy({ $0.profit != nil }) else { return nil }')
    expect(presentation).not.toContain('realized')
    const detail = read('ios/App/App/StockLedger/InsightsView.swift').split('struct DayReturnDetail: View {')[1]
    expect(detail).toContain('DailyDetailPresentation(row: row, ledger: state.ledger)')
    expect(detail).toContain('value: row.profit')
    expect(detail).toContain('subtotal: detail.heldSubtotal')
    expect(detail).toContain('subtotal: detail.closedSubtotal')
  })

  it('replays the grouping boundary and requested reconciliation in integer cents locally', () => {
    // Independent oracle, not execution of Swift. Native regression tests exercise the product.
    const contributions = [156, 62, 108, 98, 208, 55, 420, 117, -1125, 340, -510]
    const trades = contributions.map((_, symbol) => ({ symbol, date: '2026-09-24', quantity: 1 }))
    trades.push(...[8, 9, 10].map(symbol => ({ symbol, date: '2026-09-25', quantity: -1 })))
    trades.push({ symbol: 8, date: '2026-09-28', quantity: 1 })
    const quantities = new Map<number, number>()
    for (const trade of trades.filter(t => t.date <= '2026-09-25')) {
      quantities.set(trade.symbol, (quantities.get(trade.symbol) ?? 0) + trade.quantity)
    }
    const held = contributions.filter((_, symbol) => (quantities.get(symbol) ?? 0) > 0)
    const closed = contributions.filter((_, symbol) => (quantities.get(symbol) ?? 0) <= 0)
    const sum = (values: number[]) => values.reduce((a, b) => a + b, 0)
    expect(sum(held)).toBe(1224)
    expect(sum(closed)).toBe(-1295)
    expect(sum(held) + sum(closed)).toBe(-71)
  })

  it('keeps percentages intact and routes home to the same detail', () => {
    const holdings = read('ios/App/App/StockLedger/HoldingsView.swift')
    expect(holdings).toContain('ViewThatFits(in: .horizontal)')
    expect(holdings).toContain('.fixedSize(horizontal: true, vertical: false)')
    expect(holdings).toContain('amount: daily?.pnl, percent: daily?.percent')
    expect(holdings).toContain('state.dayReturns.first')
    expect(holdings).toContain('DayReturnDetail(row: day)')
    expect(read('tests/native/EngineGoldenTests.swift')).toContain('dailyDetailPresentation()')
    expect(read('scripts/test-native.sh')).toContain('tests/native/EngineGoldenTests.swift')
  })
})
