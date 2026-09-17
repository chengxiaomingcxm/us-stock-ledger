import { describe, it, expect } from 'vitest';
import { D, emptyLedger, calculate, saveTrade, validateLedger, type Trade } from '../src/ledger';
import { cashTotals, setOpening } from '../src/cash';
import { parseCsv, decodeCsvBytes, autoMap, analyzeTradeCsv, analyzeCashCsv, applyTradeImport, applyCashImport, parseTradeDateTime, tradeFields, cashFields, TRADE_ALIASES, CASH_ALIASES } from '../src/csv-import';

const buy = (v: Partial<Trade> = {}): Trade => ({ id: 'b', sequence: 0, symbol: 'AAPL', side: 'buy', date: '2025-06-01', quantity: '10', price: '100', fee: '1', note: '', ...v });

describe('R2-01 现金编辑保留编号与保守去重', () => {
  it('有编号记录也会与账本中无编号的同值记录比对，标为疑似重复', () => {
    const base = applyCashImport(emptyLedger(), [{ id: '', sequence: 0, date: '2025-07-01', kind: 'dividend', amount: '120', tax: '12', symbol: 'AAPL', note: '手动补记', source: 'manual' }], () => 'seed');
    const t = parseCsv('Date,Type,Symbol,Amount,Tax,FlowID\n2025-07-01,DIVIDEND,AAPL,120,12,FLOW-1');
    const a = analyzeCashCsv(t, autoMap(t.header, cashFields, CASH_ALIASES), 'deposit', base);
    expect(a.rows[0].status).toBe('suspected'); // 编号不在账本，但数值与已有无编号记录一致 → 保守提示
  });
  it('已有编号记录再次导入仍为已导入，提交层拒绝', () => {
    const base = applyCashImport(emptyLedger(), [{ id: '', sequence: 0, date: '2025-07-01', kind: 'dividend', amount: '120', tax: '12', symbol: 'AAPL', note: '', source: 'import', externalId: 'FLOW-1' }], () => 'seed');
    const t = parseCsv('Date,Type,Symbol,Amount,Tax,FlowID\n2025-07-01,DIVIDEND,AAPL,120,12,FLOW-1');
    const a = analyzeCashCsv(t, autoMap(t.header, cashFields, CASH_ALIASES), 'deposit', base);
    expect(a.rows[0].status).toBe('duplicate');
    expect(() => applyCashImport(base, a.rows.map(r => r.record), () => 'z')).toThrow('编号已存在');
  });
});

describe('R2-02 订单号与成交号', () => {
  it('自动映射优先唯一成交编号（ExecutionID），不把订单号当唯一编号', () => {
    const m = autoMap(['Date', 'Symbol', 'Side', 'Quantity', 'Price', 'OrderID', 'ExecutionID'], tradeFields, TRADE_ALIASES);
    expect(m.id).toBe(6); // ExecutionID
  });
  it('同一订单两笔成交不会互相判重，也不会被禁用', () => {
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,OrderID\n2026-09-11 10:00:00,AAPL,BUY,1,100,O-1\n2026-09-11 10:00:01,AAPL,BUY,2,110,O-1');
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), emptyLedger());
    expect(a.rows).toHaveLength(2);
    expect(a.rows.every(r => r.status === 'new')).toBe(true);
  });
  it('有成交编号时按成交编号去重', () => {
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,ExecutionID\n2026-09-11,AAPL,BUY,1,100,E-1\n2026-09-11,AAPL,BUY,2,110,E-1');
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), emptyLedger());
    expect(a.rows.map(r => r.status)).toEqual(['new', 'duplicate']);
  });
});

describe('R2-03 增量导入同日相对顺序', () => {
  const existing = () => validateLedger({ ...emptyLedger(), trades: [buy({ date: '2025-09-10', quantity: '10', price: '100', fee: '0' }), buy({ id: 'b2', sequence: 1, date: '2025-09-11', quantity: '10', price: '200', fee: '0' })] });
  const sellCsv = () => parseCsv('Date,Symbol,Side,Quantity,Price\n2025-09-11 10:00:00,AAPL,SELL,10,150');
  it('检测账本已有同日买卖混合', () => {
    const t = sellCsv();
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), existing());
    expect(a.sameDayMixed).toBe(true);
  });
  it('追加到已有同日之后：卖出按移动平均，已实现为 0', () => {
    const t = sellCsv();
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), existing());
    const next = applyTradeImport(existing(), a.rows.map(r => r.trade), () => 'x');
    expect(calculate(next).realized.toString()).toBe('0');
    expect(calculate(next).open[0].cost.toString()).toBe('1500');
  });
  it('插入到已有同日之前：先卖旧股，已实现 500，剩余成本 2000', () => {
    const t = sellCsv();
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), existing());
    const next = applyTradeImport(existing(), a.rows.map(r => r.trade), () => 'x', { insertBeforeSameDay: true });
    expect(calculate(next).realized.toString()).toBe('500');
    expect(calculate(next).open[0].cost.toString()).toBe('2000');
    expect(calculate(next).open[0].quantity.toString()).toBe('10');
  });
});

describe('R2-04 时间后缀与非法偏移', () => {
  it('拒绝带 Z 或偏移的时间，不静默丢弃时区', () => {
    expect(() => parseTradeDateTime('2026-09-12T01:00:00Z')).toThrow('时区');
    expect(() => parseTradeDateTime('2026-09-12 09:30:00+08:00')).toThrow('时区');
    expect(() => parseTradeDateTime('2026-09-12 09:30+99:99')).toThrow('时区');
  });
  it('美东本地时间仍可用', () => {
    expect(parseTradeDateTime('2026-09-12 09:30:00')).toEqual({ date: '2026-09-12', time: '09:30:00' });
  });
});

describe('R2-05 账户收益全历史口径', () => {
  it('修改现金期初不会移除已记录的分红收益', () => {
    const base = validateLedger({ ...emptyLedger(), cash: { records: [{ id: 'd', sequence: 0, date: '2025-09-10', kind: 'dividend', amount: '120', tax: '12', symbol: 'AAPL', note: '', source: 'manual' }] } });
    const withOpening = setOpening(base, { amount: '1000', date: '2025-09-11', note: '' });
    const t = cashTotals(withOpening);
    expect(t.investNetAll.toString()).toBe('108'); // 全历史，不受期初边界影响
    expect(t.investNet.toString()).toBe('0');      // 现金面板口径：边界内无分红
  });
});

describe('R2 其他边界', () => {
  it('奇数长度的 UTF-16 字节明确报错', () => {
    expect(() => decodeCsvBytes(Uint8Array.from([0xff, 0xfe, 0x41]))).toThrow('编码');
  });
});

describe('第三轮：同日顺序与预览校验', () => {
  const map = (t: ReturnType<typeof parseCsv>) => autoMap(t.header, tradeFields, TRADE_ALIASES);
  it('已有同日买卖都有时，补录任一方向都判为顺序不确定', () => {
    const existing = validateLedger({ ...emptyLedger(), trades: [buy({ date: '2025-09-10' }), buy({ id: 'b2', sequence: 1, date: '2025-09-11', quantity: '10', price: '200', fee: '0' }), buy({ id: 's', sequence: 2, date: '2025-09-11', side: 'sell', quantity: '4', price: '180', fee: '0' })] });
    const t = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-09-11 10:00,AAPL,BUY,1,150');
    const a = analyzeTradeCsv(t, map(t), existing);
    expect(a.sameDayMixed).toBe(true);
  });
  it('已有与导入同一天都含买卖时，标为交错且无法仅用前后表达', () => {
    const existing = validateLedger({ ...emptyLedger(), trades: [buy({ date: '2025-09-10' }), buy({ id: 'b2', sequence: 1, date: '2025-09-11', quantity: '10', price: '200', fee: '0' }), buy({ id: 's', sequence: 2, date: '2025-09-11', side: 'sell', quantity: '4', price: '180', fee: '0' })] });
    const t = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-09-11 10:00,AAPL,SELL,1,150\n2025-09-11 11:00,AAPL,BUY,1,150');
    const a = analyzeTradeCsv(t, map(t), existing);
    expect(a.interleaved).toBe(true);
    expect(a.sameDayMixed).toBe(false);
  });
  it('候选账本与提交共用同一排序：追加超卖而插入合法', () => {
    const existing = validateLedger({ ...emptyLedger(), trades: [buy({ date: '2025-09-10', quantity: '10', price: '100', fee: '0' }), buy({ id: 's', sequence: 1, date: '2025-09-11', side: 'sell', quantity: '10', price: '200', fee: '0' })] });
    const t = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-09-11 10:00,AAPL,SELL,5,150\n2025-09-11 11:00,AAPL,BUY,5,100');
    const a = analyzeTradeCsv(t, map(t), existing);
    expect(a.sameDayMixed).toBe(true);
    let n = 0;
    expect(() => applyTradeImport(existing, a.rows.map(r => r.trade), () => 'x' + ++n)).toThrow('超过当时持仓'); // 追加：先卖 10 后无法再卖 5
    const next = applyTradeImport(existing, a.rows.map(r => r.trade), () => 'x' + ++n, { insertBeforeSameDay: true });
    expect(calculate(next).realized.toString()).toBe('1250'); // 卖5(250) + 卖10(1000)
    expect(calculate(next).open).toHaveLength(0);
  });
});
