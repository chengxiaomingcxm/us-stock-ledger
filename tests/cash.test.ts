import { describe, it, expect } from 'vitest';
import { D, emptyLedger, calculate, validateLedger, parseBackup, backupText, deleteTrade, demoLedger, type CashRecord, type Trade } from '../src/ledger';
import { cashTotals, cashNet, orderedCashRecords, saveCashRecord, deleteCashRecord, setOpening, isBeforeOpening } from '../src/cash';

const trade = (v: Partial<Trade> = {}): Trade => ({ id: 'buy1', sequence: 0, symbol: 'AAPL', side: 'buy', date: '2025-01-01', quantity: '10', price: '100', fee: '1', note: '', ...v });
const rec = (v: Partial<CashRecord> = {}): CashRecord => ({ id: 'c0', sequence: 0, date: '2025-03-01', kind: 'deposit', amount: '100', note: '', source: 'manual', ...v });

describe('现金记录净额与余额', () => {
  it('按类型计算净额：入金为正、出金和费用为负、分红为毛额减税', () => {
    expect(cashNet({ kind: 'deposit', amount: '100' }).toString()).toBe('100');
    expect(cashNet({ kind: 'withdraw', amount: '30' }).toString()).toBe('-30');
    expect(cashNet({ kind: 'dividend', amount: '120', tax: '12' }).toString()).toBe('108');
    expect(cashNet({ kind: 'fee', amount: '5' }).toString()).toBe('-5');
  });
  it('余额为期初加边界内净流入，未设置期初时无余额', () => {
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
  it('买卖联动现金：买入扣含费支出、卖出加扣费收入，不改变证券成本与收益', () => {
    // A1：期初 2000 在前；买 10@100 费 1；卖 4@120 费 2；剩 6 股报价 110
    const trades = validateLedger({ ...emptyLedger(), trades: [trade(), trade({ id: 's', sequence: 1, side: 'sell', quantity: '4', price: '120', fee: '2' })] });
    const before = calculate(trades);
    const next = setOpening(trades, { amount: '2000', date: '2024-12-31', note: '' });
    const after = calculate(next);
    expect(after.cost).toEqual(before.cost);
    expect(after.realized).toEqual(before.realized);
    expect(cashTotals(next).balance?.toString()).toBe('1477');
    expect(cashTotals(next).buyOut.toString()).toBe('1001');
    expect(cashTotals(next).sellIn.toString()).toBe('478');
    // 再卖 6 股@130 费 3：现金 2254，证券已实现 254
    const all = validateLedger({ ...next, trades: [...next.trades, { id: 's2', sequence: 2, symbol: 'AAPL', side: 'sell', date: '2025-01-02', quantity: '6', price: '130', fee: '3', note: '' }] });
    expect(cashTotals(all).balance?.toString()).toBe('2254');
    expect(calculate(all).realized.toString()).toBe('254');
  });
  it('期初边界：之前的交易与流水不重复计入，当日及之后计入，修改期初日期重算', () => {
    const base = validateLedger({
      ...emptyLedger(),
      trades: [trade({ date: '2025-09-01' }), trade({ id: 'b2', sequence: 1, date: '2025-09-12', quantity: '1', price: '100', fee: '0' })],
      cash: { records: [rec({ id: 'r1', sequence: 0, date: '2025-09-01', kind: 'deposit', amount: '500' }), rec({ id: 'r2', sequence: 1, date: '2025-09-12', kind: 'deposit', amount: '300' })] },
    });
    const d = setOpening(base, { amount: '1000', date: '2025-09-11', note: '' });
    let t = cashTotals(d);
    expect(t.excludedTrades).toBe(1);
    expect(t.excludedRecords).toBe(1);
    expect(t.balance?.toString()).toBe('1200'); // 1000 − 100 + 300
    expect(isBeforeOpening('2025-09-01', d)).toBe(true);
    expect(isBeforeOpening('2025-09-12', d)).toBe(false);
    // 修改期初日期为 9 月 1 日：同日记录全部计入
    const moved = setOpening(d, { amount: '1000', date: '2025-09-01', note: '' });
    expect(cashTotals(moved).excludedTrades).toBe(0);
    expect(cashTotals(moved).balance?.toString()).toBe('699'); // 1000 + 500 + 300 − 1001 − 100
  });
  it('交易编辑、删除后现金自动重算', () => {
    const d = setOpening(validateLedger({ ...emptyLedger(), trades: [trade()] }), { amount: '5000', date: '2024-12-31', note: '' });
    expect(cashTotals(d).balance?.toString()).toBe('3999'); // 5000 − 1001
    const removed = deleteTrade(d, 'buy1');
    expect(cashTotals(removed).balance?.toString()).toBe('5000');
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
  it('期初余额允许为零，拒绝负数', () => {
    const d = setOpening(emptyLedger(), { amount: '0', date: '2025-01-01', note: '满仓' });
    expect(cashTotals(d).balance?.toString()).toBe('0');
    expect(() => setOpening(emptyLedger(), { amount: '-1', date: '2025-01-01', note: '' })).toThrow();
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
  it('旧版备份没有现金字段，读取后保持未初始化；首次启用期初后边界生效', () => {
    const legacy = { version: 1, currency: 'USD', method: 'moving-average', trades: [trade()], quotes: [] };
    const loaded = parseBackup(JSON.stringify(legacy));
    expect(loaded.cash).toBeUndefined();
    expect(cashTotals(loaded).balance).toBeUndefined();
    const migrated = setOpening(loaded, { amount: '9000', date: '2024-12-31', note: '期初' });
    expect(migrated.trades).toEqual(loaded.trades);
    expect(cashTotals(migrated).balance?.toString()).toBe('7999'); // 9000 − 1001（期初后买入）
  });
  it('示例账本包含期初与分红，余额可算', () => {
    const t = cashTotals(demoLedger());
    expect(t.balance?.toString()).toBe('61154');
  });
});
