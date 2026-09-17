import { D, validateLedger, type CashKind, type CashRecord, type Ledger } from './ledger';

export interface CashTotals {
  opening: ReturnType<typeof D>;   // 期初余额
  deposit: ReturnType<typeof D>;   // 累计入金
  withdraw: ReturnType<typeof D>;  // 累计出金
  dividend: ReturnType<typeof D>;  // 分红毛额
  tax: ReturnType<typeof D>;       // 分红预扣税费
  fee: ReturnType<typeof D>;       // 账户费用
  net: ReturnType<typeof D>;       // 已记录资金流净额（不含期初）
  balance?: ReturnType<typeof D>;  // 期初 + 净额；未设置期初余额时为 undefined
}

/** 单笔现金记录对余额的净影响（正数增加、负数减少）。 */
export function cashNet(r: Pick<CashRecord, 'kind' | 'amount' | 'tax'>): ReturnType<typeof D> {
  if (r.kind === 'deposit') return D(r.amount);
  if (r.kind === 'withdraw') return D(r.amount).neg();
  if (r.kind === 'dividend') return D(r.amount).minus(r.tax ?? 0);
  return D(r.amount).neg();
}

export function cashTotals(data: Ledger): CashTotals {
  const t: CashTotals = { opening: D(data.cash?.opening?.amount ?? 0), deposit: D(0), withdraw: D(0), dividend: D(0), tax: D(0), fee: D(0), net: D(0) };
  for (const r of data.cash?.records ?? []) {
    t.deposit = t.deposit.plus(r.kind === 'deposit' ? r.amount : 0);
    t.withdraw = t.withdraw.plus(r.kind === 'withdraw' ? r.amount : 0);
    if (r.kind === 'dividend') { t.dividend = t.dividend.plus(r.amount); t.tax = t.tax.plus(r.tax ?? 0); }
    if (r.kind === 'fee') t.fee = t.fee.plus(r.amount);
    t.net = t.net.plus(cashNet(r));
  }
  if (data.cash?.opening) t.balance = t.opening.plus(t.net);
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
