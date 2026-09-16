import { Capacitor, CapacitorHttp } from '@capacitor/core';
import { Preferences } from '@capacitor/preferences';
import { D, type Ledger, type Quote } from './ledger';
import { marketDate } from './market';

export interface ApiSettings { provider: 'yahoo' | 'finnhub' | 'custom'; url: string; key: string; interval: number }
export interface LiveQuote { quote: Quote; timestamp: number }
export const defaultApi: ApiSettings = { provider: 'yahoo', url: '', key: '', interval: 60 };
const settingsKey = 'stock-ledger-market-settings-v1';
export function validateApi(raw: ApiSettings): ApiSettings {
  if (!['yahoo','finnhub','custom'].includes(raw.provider) || ![0,60,300].includes(raw.interval)) throw Error('行情设置无效');
  const clean = {...raw, url: raw.url.trim(), key: raw.key.trim()};
  if (clean.key.length > 2048 || /[\r\n]/.test(clean.key)) throw Error('API Key 格式无效');
  if (clean.provider === 'finnhub' && !clean.key) throw Error('请输入 Finnhub API Key');
  if (clean.provider === 'custom') {
    let url: URL; try { url = new URL(clean.url.replace('{symbol}', 'AAPL')); } catch { throw Error('请输入有效的 HTTPS 接口地址'); }
    if (url.protocol !== 'https:' || url.username || url.password || url.hash || !clean.url.includes('{symbol}')) throw Error('接口必须为 HTTPS，包含 {symbol}，且不含账号、密码或片段');
  }
  return clean;
}
export async function loadApi(): Promise<ApiSettings> {
  const {value} = await Preferences.get({key:settingsKey});
  return value ? validateApi(JSON.parse(value)) : {...defaultApi};
}
export async function saveApi(settings: ApiSettings) { await Preferences.set({key:settingsKey, value:JSON.stringify(validateApi(settings))}); }
export function parseLive(raw: any, symbol: string, provider: ApiSettings['provider'], now = Date.now()): LiveQuote {
  if (!raw || typeof raw !== 'object' || raw.error) throw Error('接口未返回有效报价');
  const price = provider === 'finnhub' ? raw.c : raw.price;
  const timestamp = provider === 'finnhub' ? raw.t * 1000 : Date.parse(raw.timestamp);
  if (provider === 'custom' && (raw.symbol !== symbol || raw.currency !== 'USD' || typeof raw.timestamp !== 'string' || !/(Z|[+-]\d{2}:\d{2})$/.test(raw.timestamp))) throw Error('报价代码、美元币种或带时区的时间不匹配');
  if (!['number','string'].includes(typeof price) || !/^\d+(\.\d+)?$/.test(String(price)) || !D(price).gt(0) || !D(price).lt('1000000000000')) throw Error('报价价格无效');
  if (!Number.isFinite(timestamp) || timestamp <= 0 || timestamp > now + 60_000) throw Error('报价时间无效或来自未来');
  return {quote:{symbol, price:D(price).toDecimalPlaces(8).toFixed(), date:marketDate(timestamp)}, timestamp};
}
export async function fetchLive(symbol: string, settings: ApiSettings): Promise<LiveQuote> {
  const config = validateApi(settings);
  if (config.provider === 'yahoo') throw Error('当前使用收盘行情');
  const url = config.provider === 'finnhub' ? `https://finnhub.io/api/v1/quote?symbol=${encodeURIComponent(symbol)}` : config.url.replaceAll('{symbol}',encodeURIComponent(symbol));
  const headers: Record<string,string> = {};
  if (config.key) headers[config.provider === 'finnhub' ? 'X-Finnhub-Token' : 'Authorization'] = config.provider === 'finnhub' ? config.key : `Bearer ${config.key}`;
  let status: number, body: unknown;
  try {
    if (Capacitor.isNativePlatform()) {
      const response = await CapacitorHttp.get({url,headers,responseType:'json',connectTimeout:10_000,readTimeout:10_000});
      status=response.status;body=typeof response.data==='string'?JSON.parse(response.data):response.data;
    } else {
      const response = await fetch(url,{headers,signal:AbortSignal.timeout(12_000),credentials:'omit',redirect:'error',cache:'no-store'});
      status=response.status;body=response.ok?await response.json():null;
    }
  } catch { throw Error('连接失败：请检查网络、接口地址及跨域设置'); }
  if (status!==200) throw Error(status===429?'请求限流，请延长刷新间隔':status===401||status===403?'API Key 无效或无行情权限':`行情请求失败（${status}）`);
  return parseLive(body,symbol,config.provider);
}
// Intraday prices are a view overlay only: never enter daily history or backups.
export function withLive(data: Ledger, live: Map<string,LiveQuote>): Ledger {
  const quotes = new Map(data.quotes.map(q=>[q.symbol,q]));
  for (const [symbol,value] of live) {
    const old=quotes.get(symbol);
    if (old && (old.date>value.quote.date || (old.date===value.quote.date && old.source!=='yahoo-close'))) continue;
    quotes.set(symbol,value.quote);
  }
  return {...data,quotes:[...quotes.values()]};
}
