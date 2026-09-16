import { describe, it, expect, vi, afterEach } from 'vitest';
import { defaultApi, validateApi, parseLive, withLive, fetchLive } from '../src/quote-api';
import { emptyLedger } from '../src/ledger';
const now=Date.parse('2026-09-16T15:00:00Z');
const body={symbol:'AAPL',currency:'USD',price:'230.50',timestamp:'2026-09-16T14:59:00Z'};
describe('quote API isolation and validation',()=>{
 afterEach(()=>vi.unstubAllGlobals());
 it('validates HTTPS URL, symbol template and refresh interval',()=>{
  expect(validateApi({...defaultApi,provider:'custom',url:'https://example.com/{symbol}'}).provider).toBe('custom');
  for(const url of ['http://example.com/{symbol}','https://example.com/quote','https://user:pass@example.com/{symbol}'])expect(()=>validateApi({...defaultApi,provider:'custom',url})).toThrow();
  expect(()=>validateApi({...defaultApi,interval:1})).toThrow();
  expect(()=>validateApi({...defaultApi,provider:'finnhub'})).toThrow();
 });
 it('parses custom and Finnhub timestamps and prices',()=>{
  expect(parseLive(body,'AAPL','custom',now).quote.price).toBe('230.5');
  expect(parseLive({c:230.5,t:(now-60_000)/1000},'AAPL','finnhub',now).timestamp).toBe(now-60_000);
 });
 it('rejects incorrect symbols, currencies, malformed prices and future dates',()=>{
  for(const change of [{symbol:'MSFT'},{currency:'EUR'},{price:0},{price:'NaN'},{price:null},{timestamp:'2026-09-16T14:59:00'},{timestamp:'2026-10-16T14:59:00Z'}])expect(()=>parseLive({...body,...change},'AAPL','custom',now)).toThrow();
 });
 it('retains old timestamps without pretending they are current',()=>{
  const q=parseLive({...body,timestamp:'2026-09-11T20:00:00Z'},'AAPL','custom',now);
  expect(q.quote.date).toBe('2026-09-11');
 });
 it('keeps live prices out of the stored ledger and respects manual prices',()=>{
  const data=emptyLedger();data.quotes=[{symbol:'AAPL',price:'200',date:'2026-09-15',source:'yahoo-close',fetchedAt:new Date(now).toISOString()}];
  const original=JSON.stringify(data),live=new Map([['AAPL',parseLive(body,'AAPL','custom',now)]]);
  expect(withLive(data,live).quotes[0].price).toBe('230.5');expect(JSON.stringify(data)).toBe(original);
  data.quotes=[{symbol:'AAPL',price:'250',date:'2026-09-16'}];expect(withLive(data,live).quotes[0].price).toBe('250');
  data.quotes[0].date='2026-09-17';expect(withLive(data,live).quotes[0].price).toBe('250');
 });
 it('redacts network errors containing credentials and URL',async()=>{
  vi.stubGlobal('fetch',vi.fn().mockRejectedValue(Error('https://secret.example/?token=SECRET')));
  await expect(fetchLive('AAPL',{...defaultApi,provider:'finnhub',key:'SECRET'})).rejects.toThrow('连接失败：请检查网络、接口地址及跨域设置');
 });
 it('sends credentials in headers and explains rate limiting',async()=>{
  const request=vi.fn().mockResolvedValue({ok:false,status:429});vi.stubGlobal('fetch',request);
  await expect(fetchLive('AAPL',{...defaultApi,provider:'finnhub',key:'SECRET'})).rejects.toThrow('限流');
  expect(request.mock.calls[0][0]).not.toContain('SECRET');expect(request.mock.calls[0][1].headers['X-Finnhub-Token']).toBe('SECRET');
 });
});
