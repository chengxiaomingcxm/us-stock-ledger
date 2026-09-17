import { D, calculate, orderedTrades, type Ledger, type Trade } from './ledger';

export interface TradeRange { from?: string; to?: string; side?: 'all' | 'buy' | 'sell'; query?: string }
export interface RangeStats {
  list: Trade[];
  count: number;
  fees: ReturnType<typeof D>;
  realized: ReturnType<typeof D>;
  buyQty: ReturnType<typeof D>;
  sellQty: ReturnType<typeof D>;
  /** 所选范围内每笔卖出都有已实现收益（账本有效时恒为 true）。 */
  hasRealized: boolean;
}

/** 按日期区间、买卖类型和关键字组合筛选，并汇总范围内手续费与已实现收益。 */
export function rangeStats(data: Ledger, range: TradeRange = {}): RangeStats {
  const gains = calculate(data).gains;
  const q = (range.query ?? '').toLowerCase();
  const list = orderedTrades(data.trades).reverse().filter(t => {
    if (range.side && range.side !== 'all' && t.side !== range.side) return false;
    if (range.from && t.date < range.from) return false;
    if (range.to && t.date > range.to) return false;
    if (q && !`${t.symbol} ${t.note}`.toLowerCase().includes(q)) return false;
    return true;
  });
  let fees = D(0), realized = D(0), buyQty = D(0), sellQty = D(0), hasRealized = true;
  for (const t of list) {
    fees = fees.plus(t.fee);
    if (t.side === 'buy') buyQty = buyQty.plus(t.quantity);
    else {
      sellQty = sellQty.plus(t.quantity);
      const g = gains.get(t.id);
      if (g) realized = realized.plus(g); else hasRealized = false;
    }
  }
  return { list, count: list.length, fees, realized, buyQty, sellQty, hasRealized };
}
