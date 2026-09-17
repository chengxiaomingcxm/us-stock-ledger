import { describe, it, expect } from 'vitest';
import { D, emptyLedger, calculate, validateLedger, parseBackup, backupText, demoLedger, type CashRecord, type Trade } from '../src/ledger';
import { cashTotals, cashNet, orderedCashRecords, saveCashRecord, deleteCashRecord, setOpening } from '../src/cash';

const trade = (v: Partial<Trade> = {}): Trade => ({ id: 'buy1', sequence: 0, symbol: 'AAPL', side: 'buy', date: '2025-01-01', quantity: '10', price: '100', fee: '1', note: '', ...v });
const rec = (v: Partial<CashRecord> = {}): CashRecord => ({ id: 'c0', sequence: 0, date: '2025-03-01', kind: 'deposit', amount: '100', note: '', source: 'manual', ...v });

describe('现金记录净额与余额', () => {
  it('按类型计算净额：入金为正、出金和费用为负、分红为毛额减税', () => {
    expect(cashNet({ kind: 'deposit', amount: '100' }).toString()).toBe('100');
    expect(cashNet({ kind: 'withdraw', amount: '30' }).toString()).toBe('-30');
    expect(cashNet({ kind: 'dividend', amount: '120', tax: '12' }).toString()).toBe('108');
    expect(cashNet({ kind: 'fee', amount: '5' }).toString()).toBe('-5');
  });
  it('余额为期初加全部净流入，未设置期初时无余额', () => {
    const base = validateLedger({
      ...emptyLedger(),
      cash: {
        records: [
          rec({ id: 'a', sequence: 0, date: '2025-01-10', kind: 'deposit', amount: '2000' }),
          rec({ id: 'b', sequence: 1, date: '2025-02-10', kind: 'withdraw', amount: '500' }),
          rec({ id: 'c', sequence: 2, date: '2025-03-10', kind: 'dividend', amount: '120', tax: '12', symbol: 'AAPL' }),
          rec({ id: 'd', sequence: 3, date: '2025-04-10', kind: 'fee', amount: '5' }),
        ],
      },
    });
    let t = cashTotals(base);
    expect(t.balance).toBeUndefined();
    expect(t.net.toString()).toBe('1603');
    const withOpening = validateLedger({ ...base, cash: { ...base.cash, opening: { amount: '50000', date: '2025-01-01', note: '期初' } } });
    t = cashTotals(withOpening);
    expect(t.balance?.toString()).toBe('51603');
    expect(t.deposit.toString()).toBe('2000');
    expect(t.withdraw.toString()).toBe('500');
    expect(t.dividend.toString()).toBe('120');
    expect(t.tax.toString()).toBe('12');
    expect(t.fee.toString()).toBe('5');
  });
  it('入金出金不改变交易成本与已实现收益', () => {
    const trades = validateLedger({ ...emptyLedger(), trades: [trade(), trade({ id: 's', sequence: 1, side: 'sell', quantity: '4', price: '120', fee: '2' })] });
    const before = calculate(trades);
    const next = setOpening(saveCashRecord(trades, rec()), { amount: '10000', date: '2025-01-01', note: '' });
    const after = calculate(next);
    expect(after.cost).toEqual(before.cost);
    expect(after.realized).toEqual(before.realized);
    expect(cashTotals(next).balance?.toString()).toBe('10100');
  });
});

describe('现金记录增删改', () => {
  it('保存按 id 更新，删除后余额重算', () => {
    let d = saveCashRecord(emptyLedger(), rec({ id: 'a', amount: '100' }));
    d = saveCashRecord(d, rec({ id: 'a', amount: '200' }));
    expect(d.cash?.records).toHaveLength(1);
    expect(cashTotals(d).net.toString()).toBe('200');
    d = deleteCashRecord(d, 'a');
    expect(d.cash?.records).toHaveLength(0);
    expect(cashTotals(d).net.toString()).toBe('0');
  });
  it('期初余额只能有一份，修改覆盖旧值', () => {
    let d = setOpening(emptyLedger(), { amount: '10000', date: '2025-01-01', note: '第一笔' });
    d = setOpening(d, { amount: '12000', date: '2025-01-01', note: '第二笔' });
    expect(d.cash?.opening?.amount).toBe('12000');
    expect(cashTotals(d).balance?.toString()).toBe('12000');
  });
  it('记录按日期和顺序排序', () => {
    const d = saveCashRecord(saveCashRecord(emptyLedger(), rec({ id: 'b', sequence: 1, date: '2025-03-02' })), rec({ id: 'a', sequence: 0, date: '2025-03-01' }));
    expect(orderedCashRecords(d).map(r => r.id)).toEqual(['a', 'b']);
  });
});

describe('现金校验与备份', () => {
  it.each([
    [{ records: [rec({ kind: 'invest' as CashRecord['kind'] })] }],
    [{ records: [rec({ id: 'a' }), rec({ id: 'a', sequence: 1 })] }],
    [{ records: [rec({ amount: '-1' })] }],
    [{ records: [rec({ tax: '5' })] }], // deposit 不允许税费
    [{ records: [rec({ kind: 'dividend', amount: '100', tax: '101' })] }],
    [{ records: [rec({ symbol: 'AAPL' })] }], // deposit 不允许代码
    [{ records: [rec({ date: '2100-01-01' })] }],
  ])('拒绝无效现金记录', cash => expect(() => validateLedger({ ...emptyLedger(), cash })).toThrow());
  it('分红可带代码与税费，费用可带代码', () => {
    const d = validateLedger({
      ...emptyLedger(),
      cash: { records: [rec({ kind: 'dividend', amount: '120', tax: '12', symbol: 'AAPL' }), rec({ id: 'f', sequence: 1, kind: 'fee', amount: '5', symbol: 'MSFT' })] },
    });
    expect(d.cash?.records).toHaveLength(2);
  });
  it('备份往返保留现金记录，通用备份剔除现金与历史', () => {
    const d = setOpening(saveCashRecord(emptyLedger(), rec({ kind: 'dividend', amount: '120', tax: '12', symbol: 'AAPL' })), { amount: '5000', date: '2025-01-01', note: '' });
    const full = parseBackup(backupText(d));
    expect(full.cash?.records).toHaveLength(1);
    expect(full.cash?.opening?.amount).toBe('5000');
    const compat = parseBackup(backupText(d, true));
    expect(compat.cash).toBeUndefined();
    expect(compat.history).toBeUndefined();
  });
  it('旧版备份没有现金字段，读取后自动迁移、不覆盖交易', () => {
    const legacy = { version: 1, currency: 'USD', method: 'moving-average', trades: [trade()], quotes: [] };
    const loaded = parseBackup(JSON.stringify(legacy));
    expect(loaded.cash).toBeUndefined();
    const migrated = setOpening(loaded, { amount: '9000', date: '2025-01-01', note: '期初' });
    expect(migrated.trades).toEqual(loaded.trades);
    expect(cashTotals(migrated).balance?.toString()).toBe('9000');
  });
  it('示例账本包含期初与分红，余额可算', () => {
    const t = cashTotals(demoLedger());
    expect(t.balance?.toString()).toBe('70103');
  });
});
