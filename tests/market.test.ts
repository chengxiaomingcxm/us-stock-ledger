import { describe, it, expect } from 'vitest';
import { marketDate, parseDailyClose, mergeCloses, collectCloses, providerSymbol } from '../src/market';
import { parseBackup, backupText, calculate, type Quote } from '../src/ledger';
import { LedgerStore } from '../src/storage';
import { readFileSync } from 'node:fs';

const time = (s: string) => Date.parse(s);
const seconds = (s: string) => time(s) / 1000;
function chart(dates = ['2025-07-02T13:30:00Z', '2025-07-03T13:30:00Z'], closes: (number|null)[] = [100, 110]) {
  return { chart: { error: null, result: [{ meta: { symbol: 'AAPL', currency: 'USD', instrumentType: 'EQUITY', exchangeTimezoneName: 'America/New_York', priceHint: 2,
    currentTradingPeriod: { regular: { start: seconds('2025-07-03T13:30:00Z'), end: seconds('2025-07-03T17:00:00Z') } } }, timestamp: dates.map(seconds), indicators: { quote: [{ close: closes }], adjclose: [{ adjclose: [1, 2] }] } }] } };
}
const automatic: Quote = { symbol: 'AAPL', price: '110', date: '2025-07-03', source: 'yahoo-close', fetchedAt: '2025-07-04T00:00:00.000Z' };
const oldFile = readFileSync(new URL('./fixtures/v1-backup.json', import.meta.url), 'utf8');

describe('纽约交易日及收盘价', () => {
  it('亚洲清晨仍按纽约交易日估值，冬夏令时正确', () => {
    expect(marketDate(time('2025-07-04T01:00:00Z'))).toBe('2025-07-03');
    expect(marketDate(time('2025-01-04T04:30:00Z'))).toBe('2025-01-03');
  });
  it('盘中忽略尚未完成的日线，取上一交易日', () => {
    const q = parseDailyClose(chart(), 'AAPL', time('2025-07-03T16:00:00Z'));
    expect(q.date).toBe('2025-07-02'); expect(q.price).toBe('100');
  });
  it('提前收盘日也等待15分钟，不用复权价或盘后价', () => {
    expect(parseDailyClose(chart(), 'AAPL', time('2025-07-03T17:14:59Z')).price).toBe('100');
    expect(parseDailyClose(chart(), 'AAPL', time('2025-07-03T17:15:00Z')).price).toBe('110');
  });
  it('周末和节假日保留真实交易日期，不改成今天', () => {
    expect(parseDailyClose(chart(), 'AAPL', time('2025-07-06T01:00:00Z')).date).toBe('2025-07-03');
  });
  it('冬令时正常收盘与夏令时提前收盘各自使用交易时段', () => {
    const c = chart(['2025-01-02T14:30:00Z', '2025-01-03T14:30:00Z']);
    c.chart.result[0].meta.currentTradingPeriod.regular = {start: seconds('2025-01-03T14:30:00Z'), end: seconds('2025-01-03T21:00:00Z')};
    expect(parseDailyClose(c,'AAPL',time('2025-01-03T20:59:00Z')).price).toBe('100');
    expect(parseDailyClose(c,'AAPL',time('2025-01-03T21:15:00Z')).price).toBe('110');
  });
  it('剔除空值和无效价格，并按行情精度去除浮点噪声', () => {
    expect(parseDailyClose(chart(undefined, [100, null]), 'AAPL', time('2025-07-04T01:00:00Z')).price).toBe('100');
    expect(parseDailyClose(chart(undefined, [100, 333.079986572]), 'AAPL', time('2025-07-04T01:00:00Z')).price).toBe('333.08');
    expect(()=>parseDailyClose(chart(undefined,[null,-1]),'AAPL',time('2025-07-04T01:00:00Z'))).toThrow();
  });
  it('拒绝错误币种、代码、市场与损坏响应', () => {
    for(const [key,value] of [['currency','EUR'],['symbol','MSFT'],['exchangeTimezoneName','Europe/London'],['instrumentType','CRYPTOCURRENCY']]) {
      const c=chart();(c.chart.result[0].meta as any)[key]=value;
      expect(()=>parseDailyClose(c,'AAPL',time('2025-07-04T01:00:00Z'))).toThrow();
    }
    expect(()=>parseDailyClose({},'AAPL')).toThrow();
    expect(providerSymbol('BRK.B')).toBe('BRK-B');
  });
});
describe('更新和第一版升级', () => {
  it('第一版备份导入和再次导出不改变任何字段', () => {
    expect(JSON.parse(backupText(parseBackup(oldFile)))).toEqual(JSON.parse(oldFile));
    expect(()=>parseBackup('window.backup = '+oldFile)).toThrow('JSON');
  });
  it('更新只改变报价，不改变历史交易、成本或已实现收益', () => {
    const old=parseBackup(oldFile), before=calculate(old), merged=mergeCloses(old,[automatic]);
    expect(merged.data.trades).toEqual(old.trades);
    expect(calculate(merged.data).cost.eq(before.cost)).toBe(true);
    expect(calculate(merged.data).realized.eq(before.realized)).toBe(true);
    expect(calculate(merged.data).unrealized?.toFixed()).toBe('59.4');
    expect(parseBackup(backupText(merged.data))).toEqual(merged.data);
  });
  it('较新报价和同日手动价受到保护，下一交易日继续更新', () => {
    const old=parseBackup(oldFile); old.quotes=[{symbol:'AAPL',price:'130',date:'2025-07-03'}];
    expect(mergeCloses(old,[automatic]).retained).toBe(1);
    expect(mergeCloses(old,[{...automatic,date:'2025-07-02'}]).updated).toBe(0);
    expect(mergeCloses(old,[{...automatic,date:'2025-07-07'}]).updated).toBe(1);
  });
  it('部分网络失败仍更新成功股票，保留失败股票旧报价', async () => {
    const result=await collectCloses(['AAPL','MSFT','AAPL'],async symbol=>{if(symbol==='MSFT')throw Error('429');return automatic;});
    expect(result.quotes).toHaveLength(1);expect(result.errors).toEqual([{symbol:'MSFT',reason:'429'}]);
    const old=parseBackup(oldFile);
    expect(mergeCloses(old,[]).data).toEqual(old);
  });
  it('第一版原存储位置覆盖升级后可读，新增来源字段保存后也可重启恢复', async () => {
    const original=parseBackup(oldFile), map=new Map([['stock-ledger-v1-0',JSON.stringify({revision:7,data:original})]]);
    const kv={get:async(k:string)=>map.get(k)??null,set:async(k:string,v:string)=>{map.set(k,v);}};
    const store=new LedgerStore(kv);expect((await store.load()).data).toEqual(original);
    const updated=mergeCloses(original,[automatic]).data;await store.save(updated);
    expect(JSON.parse(map.get('stock-ledger-v1-0')!).data).toEqual(original);
    expect((await new LedgerStore(kv).load()).data).toEqual(updated);
  });
});
