import { describe, it, expect } from 'vitest';
import { emptyLedger, saveTrade, type Trade } from '../src/ledger';
import { parseCsv, decodeCsvBytes, autoMap, analyzeTradeCsv, analyzeCashCsv, applyTradeImport, applyCashImport, parseTradeDateTime, tradeFields, cashFields, TRADE_ALIASES, CASH_ALIASES } from '../src/csv-import';

const buy = (v: Partial<Trade> = {}): Trade => ({ id: 'buy1', sequence: 0, symbol: 'AAPL', side: 'buy', date: '2025-06-01', quantity: '10', price: '100', fee: '1', note: '', ...v });
const ledger = () => saveTrade(emptyLedger(), buy());

describe('CSV 解析', () => {
  it('识别逗号、BOM、CRLF 与带引号字段', () => {
    const t = parseCsv('\uFEFFDate,Symbol,Side,Quantity,Price,Fee,Note\r\n2025-01-02,AAPL,BUY,10,100.5,1,"分批,建仓"\r\n2025-01-03,MSFT,SELL,2,"1,000",0,"""止盈"""\r\n');
    expect(t.header).toEqual(['Date', 'Symbol', 'Side', 'Quantity', 'Price', 'Fee', 'Note']);
    expect(t.rows).toHaveLength(2);
    expect(t.rows[0].cells[6]).toBe('分批,建仓');
    expect(t.rows[1].cells[4]).toBe('1,000');
    expect(t.rows[1].cells[6]).toBe('"止盈"');
  });
  it('识别分号与制表符分隔', () => {
    expect(parseCsv('Date;Symbol;Amount\n2025-01-02;AAPL;10').header.length).toBe(3);
    expect(parseCsv('Date\tSymbol\tAmount\n2025-01-02\tAAPL\t10').header.length).toBe(3);
  });
  it('拒绝列数不一致、缺少数据行和空文件，行号为真实行', () => {
    expect(() => parseCsv('Date,Symbol\n2025-01-02,AAPL,9')).toThrow('第 2 行');
    expect(() => parseCsv('Date,Symbol')).toThrow('数据行');
    expect(() => parseCsv('')).toThrow();
  });
  it('保留真实行号并支持引号内换行', () => {
    const t = parseCsv('Date,Symbol,Amount\n\n2025-01-02,AAPL,10\n2025-01-03,MSFT,"第一行\n第二行"');
    expect(t.rows[0].line).toBe(3);
    expect(t.rows[1].cells[2]).toBe('第一行\n第二行');
    expect(t.rows[1].line).toBe(4);
  });
});

describe('文件编码', () => {
  const bytes = (s: string) => new Uint8Array([...s].map(c => c.charCodeAt(0)));
  it('识别 UTF-8 与 GBK', () => {
    expect(decodeCsvBytes(bytes('Date,Symbol')).encoding).toBe('UTF-8');
    // GBK 编码的“备注”：备=B1B8，注=D7A2
    expect(decodeCsvBytes(Uint8Array.from([0xb1, 0xb8, 0xd7, 0xa2])).text).toBe('备注');
  });
  it('识别 UTF-16 LE / BE BOM', () => {
    const le = Uint8Array.from([0xff, 0xfe, 0x44, 0x00, 0x61, 0x00]);
    expect(decodeCsvBytes(le).text).toBe('Da');
    const be = Uint8Array.from([0xfe, 0xff, 0x00, 0x44, 0x00, 0x61]);
    expect(decodeCsvBytes(be).text).toBe('Da');
  });
  it('无法识别的编码明确报错', () => {
    expect(() => decodeCsvBytes(Uint8Array.from([0x00, 0xd8, 0x00, 0xe0]))).toThrow('编码无法识别');
  });
});

describe('字段自动映射', () => {
  it('映射英文表头', () => {
    const m = autoMap(['Date', 'Symbol', 'Side', 'Quantity', 'Price', 'Fee', 'TradeID', 'Note'], tradeFields, TRADE_ALIASES);
    expect(m).toEqual({ date: 0, symbol: 1, side: 2, quantity: 3, price: 4, fee: 5, note: 7, currency: undefined, id: 6 });
  });
  it('映射中文表头与别名', () => {
    const m = autoMap(['交易日期', '证券代码', '买卖', '成交数量', '成交价', '手续费', '备注'], tradeFields, TRADE_ALIASES);
    expect(m.date).toBe(0); expect(m.symbol).toBe(1); expect(m.side).toBe(2); expect(m.quantity).toBe(3); expect(m.price).toBe(4); expect(m.fee).toBe(5); expect(m.note).toBe(6);
    const c = autoMap(['日期', '资金类型', '发生金额', '预扣税费', '币种', '备注'], cashFields, CASH_ALIASES);
    expect(c.date).toBe(0); expect(c.type).toBe(1); expect(c.amount).toBe(2); expect(c.tax).toBe(3); expect(c.currency).toBe(4); expect(c.note).toBe(5);
  });
});

describe('日期与数字严格校验', () => {
  it('合法格式：日期、日期时间、千分位', () => {
    expect(parseTradeDateTime('2026-09-10')).toEqual({ date: '2026-09-10' });
    expect(parseTradeDateTime('2026-09-10 09:30:00')).toEqual({ date: '2026-09-10', time: '09:30:00' });
    expect(parseTradeDateTime('09/16/2026 09:30')).toEqual({ date: '2026-09-16', time: '09:30' });
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,Fee\n2025-07-01,AAPL,BUY,1,"1,234.56",0');
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), emptyLedger());
    expect(a.errors).toHaveLength(0);
    expect(a.rows[0].trade.price).toBe('1234.56');
  });
  it('拒绝异常数字与日期尾缀', () => {
    const t = parseCsv('Date,Symbol,Side,Quantity,Price\n2026-09-110oops,AAPL,BUY,1,100\n2025-07-01,AAPL,BUY,1,"1,23"\n2025-07-01,AAPL,BUY,1,"1 2"\n2025-07-01,AAPL,BUY,1.123456789,100\n2025-07-01,AAPL,BUY,NaN,100\n2025-07-01,AAPL,BUY,Infinity,100\n2025-07-01,AAPL,BUY,-1,100\n2025-07-01,AAPL,BUY,1,25:00\n2025-07-01,AAPL,BUY,1,2025-02-30\n2025-07-01,AAPL,BUY,1,99999999999999');
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), emptyLedger());
    expect(a.rows).toHaveLength(0);
    expect(a.errors).toHaveLength(10);
    expect(a.errors[0].reason).toContain('日期');
    expect(a.errors[1].reason).toContain('格式无效');
    expect(a.errors[3].reason).toContain('小数');
  });
});

describe('交易 CSV 分析', () => {
  const table = () => parseCsv('Date,Symbol,Side,Quantity,Price,Fee,Note\n2025-07-01,AAPL,BUY,5,110.5,1,加仓\n2025-07-02,MSFT,SELL,2,390,0,\n2025/07/03,NVDA,买,3,120,,');
  it('解析有效行并标记 CSV 来源', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const a = analyzeTradeCsv(table(), m, emptyLedger());
    expect(a.errors).toHaveLength(0);
    expect(a.rows).toHaveLength(3);
    expect(a.rows.every(r => r.status === 'new')).toBe(true);
    expect(a.rows[0].trade.source).toBe('import');
    expect(a.rows[2].trade.side).toBe('buy');
  });
  it('无编号的数值相同行标为疑似重复，手续费不同则不是', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,Fee,Note\n2025-06-01,AAPL,BUY,10,100,1,重复\n2025-06-01,AAPL,BUY,10,100,2,手续费不同\n2025-06-02,AAPL,BUY,10,100,1,\n2025-06-02,AAPL,BUY,10,100,1,');
    const a = analyzeTradeCsv(t, m, ledger());
    expect(a.rows.map(r => r.status)).toEqual(['suspected', 'new', 'new', 'suspected']);
  });
  it('券商编号决定已导入：同编号重复、不同编号同参数保守提示疑似重复', () => {
    const base = saveTrade(emptyLedger(), buy({ externalId: 'T-1' }));
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,Fee,TradeID\n2025-06-01,AAPL,BUY,10,100,1,T-1\n2025-06-01,AAPL,BUY,10,100,1,T-2\n2025-06-01,AAPL,BUY,10,100,1,T-2');
    const a = analyzeTradeCsv(t, autoMap(t.header, tradeFields, TRADE_ALIASES), base);
    expect(a.rows.map(r => r.status)).toEqual(['duplicate', 'suspected', 'duplicate']);
  });
  it('收集错误行：方向、数量、币种', () => {
    const t = parseCsv('Date,Symbol,Side,Quantity,Price,Fee,Currency\n2025-07-01,AAPL,HOLD,5,110,1,\n2025-07-01,AAPL,BUY,0,110,1,\n2025-07-01,AAPL,BUY,5,110,1,CNY\n2025-07-01,AAPL,BUY,5,110,1,USD');
    const m = autoMap(t.header, tradeFields, TRADE_ALIASES);
    const a = analyzeTradeCsv(t, m, emptyLedger());
    expect(a.errors.map(e => e.line)).toEqual([2, 3, 4]);
    expect(a.errors[1].reason).toContain('数量');
    expect(a.errors[2].reason).toContain('美元');
  });
  it('同日顺序：全部有时间按时间排序；混合买卖且时间不全标为歧义', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const timed = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-07-01,AAPL,SELL,2,110\n2025-07-01,AAPL,BUY,3,100');
    const a = analyzeTradeCsv(timed, m, emptyLedger());
    expect(a.orderAmbiguous).toBe(true);
    const withTime = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-07-01 15:00,AAPL,SELL,2,110\n2025-07-01 10:00,AAPL,BUY,3,100');
    const b = analyzeTradeCsv(withTime, m, emptyLedger());
    expect(b.orderAmbiguous).toBe(false);
    expect(b.rows.map(r => r.trade.side)).toEqual(['buy', 'sell']);
  });
  it('批校验提前暴露超卖，提交层拒绝重复编号', () => {
    const m = autoMap(table().header, tradeFields, TRADE_ALIASES);
    const t = parseCsv('Date,Symbol,Side,Quantity,Price\n2025-07-01,AAPL,SELL,99,110');
    const a = analyzeTradeCsv(t, m, ledger());
    expect(a.batchError).toContain('超过当时持仓');
    expect(() => applyTradeImport(ledger(), a.rows.map(r => r.trade), () => 'x')).toThrow('当前账本未改变');
    const base = saveTrade(emptyLedger(), buy({ externalId: 'T-9' }));
    const dup = parseCsv('Date,Symbol,Side,Quantity,Price,TradeID\n2025-07-01,AAPL,BUY,1,110,T-9');
    const d = analyzeTradeCsv(dup, autoMap(dup.header, tradeFields, TRADE_ALIASES), base);
    expect(d.rows[0].status).toBe('duplicate');
    expect(() => applyTradeImport(base, d.rows.map(r => r.trade), () => 'y')).toThrow('编号已存在');
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
  it('资金 CSV 校验币种：CNY、HKD 报错，USD 或无币种列按美元', () => {
    const t = parseCsv('Date,Type,Amount,Currency\n2025-07-01,DEPOSIT,1000,CNY\n2025-07-02,DEPOSIT,500,HKD\n2025-07-03,DEPOSIT,300,USD');
    const m = autoMap(t.header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(t, m, 'deposit', emptyLedger());
    expect(a.errors.map(e => e.line)).toEqual([2, 3]);
    expect(a.errors[0].reason).toContain('美元');
    const noCur = parseCsv('Date,Type,Amount\n2025-07-01,DEPOSIT,1000');
    const b = analyzeCashCsv(noCur, autoMap(noCur.header, cashFields, CASH_ALIASES), 'deposit', emptyLedger());
    expect(b.errors).toHaveLength(0);
  });
  it('没有类型列时必须选择统一类型，否则全部报错', () => {
    const t = parseCsv('Date,Amount,Note\n2025-07-01,2000,ok\n2025-07-02,500,ok');
    const m = autoMap(t.header, cashFields, CASH_ALIASES);
    const missing = analyzeCashCsv(t, m, undefined, emptyLedger());
    expect(missing.errors).toHaveLength(2);
    expect(missing.errors[0].reason).toContain('统一类型');
    const fallback = analyzeCashCsv(t, m, 'withdraw', emptyLedger());
    expect(fallback.rows.map(r => r.record.kind)).toEqual(['withdraw', 'withdraw']);
  });
  it('流水编号决定已导入，无编号数值相同标为疑似重复', () => {
    const base = applyCashImport(emptyLedger(), [{ id: '', sequence: 0, date: '2025-07-01', kind: 'deposit', amount: '2000', note: '已有', source: 'import', externalId: 'F-1' }], () => 'seed');
    const m = autoMap(table().header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(table(), m, 'deposit', base);
    expect(a.rows[0].status).toBe('suspected'); // 数值相同但无编号
    const withId = parseCsv('Date,Type,Amount,FlowID\n2025-07-01,DEPOSIT,2000,F-1\n2025-07-02,DEPOSIT,2000,F-2\n2025-07-02,DEPOSIT,2000,F-2');
    const b = analyzeCashCsv(withId, autoMap(withId.header, cashFields, CASH_ALIASES), 'deposit', base);
    expect(b.rows.map(r => r.status)).toEqual(['duplicate', 'new', 'duplicate']);
  });
  it('提交层拒绝重复流水编号，写入保留期初余额并延续序号', () => {
    const base = applyCashImport(emptyLedger(), [{ id: '', sequence: 0, date: '2025-06-01', kind: 'deposit', amount: '10', note: '', source: 'manual' }], () => 'seed');
    const m = autoMap(table().header, cashFields, CASH_ALIASES);
    const a = analyzeCashCsv(table(), m, 'deposit', base);
    let n = 0;
    const next = applyCashImport(base, a.rows.map(r => r.record), () => 'id-' + ++n);
    expect(next.cash?.records.map(r => r.sequence)).toEqual([0, 1, 2, 3]);
    expect(next.cash?.records[1].id).toBe('id-1');
    const withId = parseCsv('Date,Type,Amount,FlowID\n2025-07-01,DEPOSIT,5,F-X');
    const seeded = applyCashImport(base, [{ id: '', sequence: 1, date: '2025-07-01', kind: 'deposit', amount: '5', note: '', source: 'import', externalId: 'F-X' }], () => 's');
    const d = analyzeCashCsv(withId, autoMap(withId.header, cashFields, CASH_ALIASES), 'deposit', seeded);
    expect(() => applyCashImport(seeded, d.rows.map(r => r.record), () => 'z')).toThrow('编号已存在');
  });
});

