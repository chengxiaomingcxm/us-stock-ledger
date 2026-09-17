import { D, orderedTrades, type Ledger } from './ledger';
import { knownClosed } from './history';
import { marketDate } from './market';

type Amount = ReturnType<typeof D>;
export interface TodayRow { symbol: string; pnl?: Amount; reason?: string }
export interface TodayPnl {
  today: string;
  prevCloseDate?: string;
  /** 今日已是已确认的完整交易日（日历含今日）。 */
  closed: boolean;
  /** 今日是周末或已公布的 NYSE 假日。 */
  nonTrading: boolean;
  /** 账本是否已有交易日历。 */
  hasCalendar: boolean;
  /** 全部所需行情齐全时的今日盈亏；否则为 undefined（显示待补全，不当作零）。 */
  pnl?: Amount;
  /** 今日盈亏 / 上一收盘市值（用于百分比）。 */
  pct?: Amount;
  /** 上一交易日收盘时的持仓市值（仅含能取到上一收盘价的持仓）。 */
  basis?: Amount;
  tradedToday: number;
  missing: string[];
  rows: TodayRow[];
}

/**
 * 今日盈亏 = 期末市值 − 期初（上一交易日收盘）市值 − 当日买入含费支出 + 当日卖出净收入。
 * 任一必需行情缺失时整体返回待补全，缺失明细在 missing 中，绝不按零计算。
 */
export function todayPnl(data: Ledger, now = Date.now()): TodayPnl {
  const today = marketDate(now);
  const sessions = data.history?.sessions ?? [];
  const nonTrading = knownClosed(today);
  const closed = !nonTrading && sessions.includes(today);
  // Never treat the last cached session as yesterday without checking calendar gaps.
  let expectedPrevious = new Date(Date.parse(today) - 86400000).toISOString().slice(0, 10);
  while (knownClosed(expectedPrevious)) {
    expectedPrevious = new Date(Date.parse(expectedPrevious) - 86400000).toISOString().slice(0, 10);
  }
  const prevCloseDate = sessions.includes(expectedPrevious) ? expectedPrevious : undefined;
  const closes = new Map((data.history?.closes ?? []).map(c => [c.symbol + '|' + c.date, D(c.price)]));
  const quotes = new Map(data.quotes.map(q => [q.symbol, q]));
  const trades = orderedTrades(data.trades);
  const todayTrades = trades.filter(t => t.date === today);
  const first = new Map<string, string>();
  for (const t of trades) if (!first.has(t.symbol)) first.set(t.symbol, t.date);
  const splitSymbols = new Set((data.history?.splits ?? [])
    .filter(s => first.has(s.symbol) && s.date >= first.get(s.symbol)! && s.date <= today)
    .map(s => s.symbol));
  // Older versions defaulted to the device date. Preserve records, but don't silently
  // exclude dates ahead of New York or fold non-session trades into opening value.
  const uncertainDates = new Set(trades.filter(t => t.date > today ||
    (t.date > expectedPrevious && t.date < today)).map(t => t.symbol));
  // 今日开盘股数：今天之前所有交易累计。
  const opening = new Map<string, Amount>();
  for (const t of trades) {
    if (t.date >= today) break;
    opening.set(t.symbol, (opening.get(t.symbol) ?? D(0)).plus(D(t.quantity).mul(t.side === 'buy' ? 1 : -1)));
  }
  const symbols = [...new Set([...opening.keys(), ...todayTrades.map(t => t.symbol), ...uncertainDates])]
    .filter(s => (opening.get(s) ?? D(0)).gt(0) || todayTrades.some(t => t.symbol === s) || uncertainDates.has(s));
  const rows: TodayRow[] = [];
  const missing: string[] = [];
  let sum = D(0), basis = D(0), complete = true;
  for (const symbol of symbols) {
    const openQty = opening.get(symbol) ?? D(0);
    const buys = todayTrades.filter(t => t.symbol === symbol && t.side === 'buy');
    const sells = todayTrades.filter(t => t.symbol === symbol && t.side === 'sell');
    const bought = buys.reduce((a, t) => a.plus(t.quantity), D(0));
    const sold = sells.reduce((a, t) => a.plus(t.quantity), D(0));
    const endQty = openQty.plus(bought).minus(sold);
    let reason: string | undefined;
    let prevClose: Amount | undefined;
    let current: Amount | undefined;
    if (uncertainDates.has(symbol)) reason = '交易日期与美东交易日不一致，请核对原记录';
    else if (splitSymbols.has(symbol)) reason = '发现拆股，需先核对股数与成本';
    else if (nonTrading && (buys.length || sells.length)) reason = '休市日存在交易，请核对美东成交日期';
    if (!reason && openQty.gt(0)) {
      if (!prevCloseDate) reason = `交易日历未确认 ${expectedPrevious}，请更新行情`;
      else {
        prevClose = closes.get(symbol + '|' + prevCloseDate);
        if (prevClose === undefined) reason = `缺少 ${prevCloseDate} 收盘价`;
      }
    }
    if (!reason && endQty.gt(0)) {
      const q = quotes.get(symbol);
      if (closed) {
        // A confirmed market session does not confirm this stock's closing price.
        current = closes.get(symbol + '|' + today);
        if (current === undefined) reason = `缺少 ${today} 收盘价`;
      } else if (nonTrading) {
        // Freeze both ends at the same confirmed regular close; ignore after-hours quotes.
        current = prevClose;
        if (current === undefined) reason = '缺少最近已确认收盘价';
      } else {
        // Only quotes explicitly dated today can value today's ending holdings.
        if (q && q.date === today) current = D(q.price);
        else reason = `盘中尚未取得当日报价`;
      }
    }
    if (reason) {
      complete = false;
      missing.push(`${symbol}：${reason}`);
      rows.push({ symbol, reason });
      continue;
    }
    const vStart = openQty.gt(0) ? openQty.mul(prevClose!) : D(0);
    const vEnd = endQty.gt(0) ? endQty.mul(current!) : D(0);
    const buyCost = buys.reduce((a, t) => a.plus(D(t.quantity).mul(t.price).plus(t.fee)), D(0));
    const sellNet = sells.reduce((a, t) => a.plus(D(t.quantity).mul(t.price).minus(t.fee)), D(0));
    if (openQty.gt(0)) basis = basis.plus(vStart);
    const pnl = vEnd.minus(vStart).minus(buyCost).plus(sellNet);
    sum = sum.plus(pnl);
    rows.push({ symbol, pnl });
  }
  return {
    today, prevCloseDate, closed, nonTrading, hasCalendar: sessions.length > 0,
    pnl: complete ? sum : undefined,
    pct: complete && basis.gt(0) ? sum.div(basis).mul(100) : undefined,
    basis: complete ? basis : undefined,
    tradedToday: todayTrades.length,
    missing, rows,
  };
}
