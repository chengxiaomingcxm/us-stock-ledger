import { D, orderedTrades, validateLedger, type CashKind, type CashRecord, type Ledger } from './ledger';

// 期初余额是“期初日当天开始前”的现金；期初日及之后的入金、出金、分红、费用和股票买卖都计入余额，
// 之前的记录视为已包含在期初余额中，仅保留备查。买卖联动现金是资产转换，不计入任何收益口径；
// 未设置期初余额时不根据股票历史推断现金。

export interface CashTotals {
  opening: ReturnType<typeof D>;   // 期初余额
  deposit: ReturnType<typeof D>;   // 累计入金（边界内）
  withdraw: ReturnType<typeof D>;  // 累计出金（边界内）
  dividend: ReturnType<typeof D>;  // 分红毛额（边界内）
  tax: ReturnType<typeof D>;       // 分红预扣税费（边界内）
  fee: ReturnType<typeof D>;       // 账户费用（边界内）
  buyOut: ReturnType<typeof D>;    // 买入支出（含手续费，边界内）
  sellIn: ReturnType<typeof D>;    // 卖出收入（扣手续费，边界内）
  tradeNet: ReturnType<typeof D>;  // 买卖净现金流
  net: ReturnType<typeof D>;       // 全部现金变化净额（不含期初）
  balance?: ReturnType<typeof D>;  // 期初 + 净额；未设置期初余额时为 undefined
  investNet: ReturnType<typeof D>; // 分红净额 − 账户费用（账户现金投资收益）
  externalNet: ReturnType<typeof D>; // 入金 − 出金（外部净流入）
  excludedRecords: number;         // 期初边界之前的现金记录数（仅备查）
  excludedTrades: number;          // 期初边界之前的交易数（已含在期初余额）
}

export const openingDate = (data: Ledger): string | undefined => data.cash?.opening?.date;

/** 单笔现金记录对余额的净影响（正数增加、负数减少）。 */
export function cashNet(r: Pick<CashRecord, 'kind' | 'amount' | 'tax'>): ReturnType<typeof D> {
  if (r.kind === 'deposit') return D(r.amount);
  if (r.kind === 'withdraw') return D(r.amount).neg();
  if (r.kind === 'dividend') return D(r.amount).minus(r.tax ?? 0);
  return D(r.amount).neg();
}

export function isBeforeOpening(date: string, data: Ledger): boolean {
  const o = openingDate(data);
  return !!o && date < o;
}

export function cashTotals(data: Ledger): CashTotals {
  const opening = data.cash?.opening;
  const inBoundary = (date: string) => !opening || date >= opening.date;
  const t: CashTotals = {
    opening: D(opening?.amount ?? 0), deposit: D(0), withdraw: D(0), dividend: D(0), tax: D(0), fee: D(0),
    buyOut: D(0), sellIn: D(0), tradeNet: D(0), net: D(0),
    investNet: D(0), externalNet: D(0), excludedRecords: 0, excludedTrades: 0,
  };
  for (const r of data.cash?.records ?? []) {
    if (!inBoundary(r.date)) { t.excludedRecords++; continue; }
    if (r.kind === 'deposit') t.deposit = t.deposit.plus(r.amount);
    else if (r.kind === 'withdraw') t.withdraw = t.withdraw.plus(r.amount);
    else if (r.kind === 'dividend') { t.dividend = t.dividend.plus(r.amount); t.tax = t.tax.plus(r.tax ?? 0); }
    else t.fee = t.fee.plus(r.amount);
    t.net = t.net.plus(cashNet(r));
  }
  if (opening) {
    for (const tr of orderedTrades(data.trades)) {
      if (!inBoundary(tr.date)) { t.excludedTrades++; continue; }
      const gross = D(tr.quantity).mul(tr.price);
      if (tr.side === 'buy') {
        t.buyOut = t.buyOut.plus(gross).plus(tr.fee);
        t.net = t.net.minus(gross).minus(tr.fee);
      } else {
        t.sellIn = t.sellIn.plus(gross).minus(tr.fee);
        t.net = t.net.plus(gross).minus(tr.fee);
      }
    }
  }
  t.tradeNet = t.sellIn.minus(t.buyOut);
  if (opening) t.balance = t.opening.plus(t.net);
  t.investNet = t.dividend.minus(t.tax).minus(t.fee);
  t.externalNet = t.deposit.minus(t.withdraw);
  return t;
}

export function orderedCashRecords(data: Ledger): CashRecord[] {
  return [...(data.cash?.records ?? [])].sort((a, b) => a.date.localeCompare(b.date) || a.sequence - b.sequence);
}

export function saveCashRecord(data: Ledger, record: CashRecord): Ledger {
  return validateLedger({ ...data, cash: { ...data.cash, records: [...(data.cash?.records ?? []).filter(r => r.id !== record.id), record] } });
}

export function deleteCashRecord(data: Ledger, id: string): Ledger {
  if (!data.cash) return data;
  return validateLedger({ ...data, cash: { ...data.cash, records: data.cash.records.filter(r => r.id !== id) } });
}

export function setOpening(data: Ledger, opening: { amount: string; date: string; note: string }): Ledger {
  return validateLedger({ ...data, cash: { records: [...(data.cash?.records ?? [])], ...data.cash, opening } });
}

export function kindLabel(kind: CashKind): string {
  return kind === 'deposit' ? '入金' : kind === 'withdraw' ? '出金' : kind === 'dividend' ? '分红' : '账户费用';
}
