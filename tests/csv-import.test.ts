import { describe, it, expect } from 'vitest';
import { emptyLedger, saveTrade, type Trade } from '../src/ledger';
import { parseCsv, autoMap, analyzeTradeCsv, analyzeCashCsv, applyTradeImport, applyCashImport, tradeFields, cashFields, TRADE_ALIASES, CASH_ALIASES } from '../src/csv-import';

const buy = (v: Partial<Trade> = {}): Trade => ({ id: 'buy1', sequence: 0, symbol: 'AAPL', side: 'buy', date: '2025-06-01', quantity: '10', price: '100', fee: '1', note: '', ...v });
const ledger = () => saveTrade(emptyLedger(), buy());

describe('CSV 解析', () => {
  it('识别逗号、BOM、CRLF 与带引号字段', () => {
    const t = parseCsv('\uFEFFDate,Symbol,Side,Quantity,Price,Fee,Note\r\n2025-01-02,AAPL,BUY,10,100.5,1,"分批,建仓"\r\n2025-01-03,MSFT,SELL,2,"1,000",0,"""止盈"""\r\n');
    expect(t.header).toEqual(['Date', 'Symbol', 'Side', 'Quantity', 'Price', 'Fee', 'Note']);
    expect(t.rows).toHaveLength(2);
    expect(t.rows[0][6]).toBe('分批,建仓');
    expect(t.rows[1][4]).toBe('1,000');
    expect(t.rows[1][6]).toBe('"止盈"');
  });
  it('识别分号与制表符分隔', () => {
    expect(parseCsv('Date;Symbol;Amount\n2025-01-02;AAPL;10').header.length).toBe(3);
    expect(parseCsv('Date\tSymbol\tAmount\n2025-01-02\tAAPL\t10').header.length).toBe(3);
  });
  it('拒绝列数不一致、缺少数据行和空文件', () => {
    expect(() => parseCsv('Date,Symbol\n2025-01-02,AAPL,9')).toThrow('列数');
    expect(() => parseCsv('Date,Symbol')).toThrow('数据行');
    expect(() => parseCsv('')).toThrow();
  });
});

describe('字段自动映射', () => {
  it('映射英文表头', () => {
    const m = autoMap(['Date', 'Symbol', 'Side', 'Quantity', 'Price', 'Fee', 'Note'], tradeFields, TRADE_ALIASES);
    expect(m).toEqual({ date: 0, symbol: 1, side: 2, quantity: 3, price: 4, fee: 5, note: 6, currency: undefined });
  });
  it('映射中文表头与别名', () => {
    const m = autoMap(['交易日期', '证券代码', '买卖', '成交数量', '成交价', '手续费', '备注'], tradeFields, TRADE_ALIASES);
    expect(m.date).toBe(0); expect(m.symbol).toBe(1); expect(m.side).toBe(2); expect(m.quantity).toBe(3); expect(m.price).toBe(4); expect(m.fee).toBe(5); expect(m.note).toBe(6);
    const c = autoMap(['日期', '资金类型', '发生金额', '预扣税费', '备注'], cashFields, CASH_ALIASES);
    expect(c.date).toBe(0); expect(c.type).toBe(1); expect(c.amount).toBe(2); expect(c.tax).toBe(3); expect(c.note).toBe(4);
  });
});

describe('交易 CSV 分析', () => {
  const table = () => parseCsv('Date,Symbol,Side,Quantity,Price,Fee,Note\n2025-07-01,AAPL,BUY,5,110.5,1,加仓\n2025-07-02,MSFT,SELL,2,390,0,\n2025/07/03,NVDA,买,3,120,,');
  it('解析有效行并标记 CSV 来源', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const a = analyzeTradeCsv(table(), m, emptyLedger());
    expect(a.errors).toHaveLength(0);
    expect(a.rows).toHaveLength(3);
    expect(a.rows[0].trade.source).toBe('import');
    expect(a.rows[2].trade.side).toBe('buy');
    expect(a.rows[2].trade.fee).toBe('0');
    expect(a.rows[0].trade.date).toBe('2025-07-01');
  });
  it('与已有记录重复的行标为疑似重复', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,Fee,Note\n2025-06-01,AAPL,BUY,10,100,1,重复\n2025-06-02,AAPL,BUY,10,100,1,\n2025-06-02,AAPL,BUY,10,100,1,');
    const a = analyzeTradeCsv(t, m, ledger());
    expect(a.rows[0].duplicate).toBe(true); // 与账本已有 buy 相同
    expect(a.rows[1].duplicate).toBe(false); // 日期不同
    expect(a.rows[2].duplicate).toBe(true);  // 与文件内第 2 行相同
  });
  it('收集错误行：日期、方向、数量、币种', () => {
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,Fee,Currency\n2100-01-01,AAPL,BUY,5,110,1,USD\n2025-07-01,AAPL,HOLD,5,110,1,\n2025-07-01,AAPL,BUY,0,110,1,\n2025-07-01,AAPL,BUY,5,110,1,CNY');
    const m = autoMap(t.header, tradeFields, TRADE_ALIASES);
    const a = analyzeTradeCsv(t, m, emptyLedger());
    expect(a.errors.map(e => e.line)).toEqual([2, 3, 4, 5]);
    expect(a.errors[0].reason).toContain('日期');
    expect(a.errors[1].reason).toContain('方向');
    expect(a.errors[3].reason).toContain('美元');
  });
  it('写入时延续序号、注入 id，并通过账本校验', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);

    const base = saveTrade(saveTrade(emptyLedger(), buy()), buy({ id: 'm', sequence: 1, symbol: 'MSFT', quantity: '5', date: '2025-06-01', price: '300' }));
    const merged = analyzeTradeCsv(table(), m, base);
    let n = 0;
    const next = applyTradeImport(base, merged.rows.map(r => r.trade), () => 'new-' + ++n);
    expect(next.trades.map(t => t.sequence)).toEqual([0, 1, 2, 3, 4]);
    expect(next.trades[2].id).toBe('new-1');
    expect(next.trades).toHaveLength(5);
  });
  it('导入导致超卖时整体拒绝，原账本不变', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const t = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-07-01,AAPL,SELL,99,110');
    const a = analyzeTradeCsv(t, m, ledger());
    expect(() => applyTradeImport(ledger(), a.rows.map(r => r.trade), () => 'x')).toThrow('当前账本未改变');
  });
});

describe('资金 CSV 分析', () => {
  const table = () => parseCsv('Date,Type,Symbol,Amount,Tax,Note\n2025-07-01,DEPOSIT,,2000,,转入\n2025-07-02,分红,AAPL,120,12,季度\n2025-07-03,费用,,5,,维护费');
  it('识别中英文类型与分红税费', () => {
    const m = autoMap(table().header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(table(), m, 'deposit', emptyLedger());
    expect(a.errors).toHaveLength(0);
    expect(a.rows.map(r => r.record.kind)).toEqual(['deposit', 'dividend', 'fee']);
    expect(a.rows[1].record.tax).toBe('12');
    expect(a.rows[1].record.symbol).toBe('AAPL');
    expect(a.rows[0].record.source).toBe('import');
  });
  it('没有类型列时按统一类型解析，入金错误行单独列出', () => {
    const t = parseCsv('Date,Amount,Note\n2025-07-01,2000,ok\n2025-13-40,10,bad\n2025-07-02,-5,负数');
    const m = autoMap(t.header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(t, m, 'withdraw', emptyLedger());
    expect(a.rows).toHaveLength(1);
    expect(a.rows[0].record.kind).toBe('withdraw');
    expect(a.errors).toHaveLength(2);
  });
  it('与已有现金记录重复的行标为疑似重复', () => {
    const base = applyCashImport(emptyLedger(), [{ id: '', sequence: 0, date: '2025-07-01', kind: 'deposit', amount: '2000', note: '已有', source: 'import' }], () => 'seed');
    const m = autoMap(table().header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(table(), m, 'deposit', base);
    expect(a.rows[0].duplicate).toBe(true);
  });
  it('写入保留期初余额并延续序号', () => {
    const base = applyCashImport(emptyLedger(), [{ id: '', sequence: 0, date: '2025-06-01', kind: 'deposit', amount: '10', note: '', source: 'manual' }], () => 'seed');
    const m = autoMap(table().header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(table(), m, 'deposit', base);
    let n = 0;
    const next = applyCashImport(base, a.rows.map(r => r.record), () => 'id-' + ++n);
    expect(next.cash?.records.map(r => r.sequence)).toEqual([0, 1, 2, 3]);
    expect(next.cash?.records[1].id).toBe('id-1');
  });
});
