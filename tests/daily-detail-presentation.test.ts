import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(path, 'utf8')

describe('native daily detail presentation wiring', () => {
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
