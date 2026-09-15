import { Capacitor, CapacitorHttp } from '@capacitor/core';
import { D, calculate, validateLedger, type Ledger, type Quote } from './ledger';
import { mergeHistory } from './history';

const ny = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' });
export function marketDate(time: number) {
  const parts = ny.formatToParts(new Date(time));
  const get = (type: string) => parts.find(p => p.type === type)!.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
export const providerSymbol = (symbol: string) => symbol.replaceAll('.', '-');
export const logoUrl = (symbol: string) => `https://financialmodelingprep.com/image-stock/${encodeURIComponent(providerSymbol(symbol))}.png`;
const record = (x: unknown): x is Record<string, any> => !!x && typeof x === 'object' && !Array.isArray(x);

/** Only unadjusted daily closes from completed US regular sessions are eligible. */
export function parseDailySeries(raw: unknown, symbol: string, now = Date.now()) {
  if (!record(raw) || !record(raw.chart) || raw.chart.error || !Array.isArray(raw.chart.result)) throw Error('行情服务未返回有效数据');
  const r = raw.chart.result[0], meta = r?.meta;
  if (!record(meta) || meta.symbol !== providerSymbol(symbol) || meta.currency !== 'USD' || meta.exchangeTimezoneName !== 'America/New_York' || !['EQUITY', 'ETF'].includes(meta.instrumentType)) throw Error('未找到匹配的美元美股或 ETF');
  const times = r.timestamp, closes = r.indicators?.quote?.[0]?.close;
  if (!Array.isArray(times) || !Array.isArray(closes) || times.length !== closes.length) throw Error('行情数据不完整');
  const today = marketDate(now), regular = meta.currentTradingPeriod?.regular;
  const candidates: Quote[] = [];
  for (let i = 0; i < times.length; i++) {
    if (typeof times[i] !== 'number' || !Number.isFinite(times[i]) || typeof closes[i] !== 'number' || !Number.isFinite(closes[i]) || closes[i] <= 0) continue;
    const time = times[i] * 1000;
    if (time > now || time < 0) continue;
    const date = marketDate(time);
    // Same-day bars are usable only after the provider's session end + 15 min.
    // The provider supplies early closes and DST offsets; do not assume 16:00 UTC.
    const endedToday = record(regular) && Number.isFinite(regular.start) && Number.isFinite(regular.end) && regular.end > regular.start && marketDate(regular.start * 1000) === date && marketDate(regular.end * 1000) === date && now >= regular.end * 1000 + 15 * 60_000;
    if (date > today || (date === today && !endedToday)) continue;
    const precision = Number.isInteger(meta.priceHint) && meta.priceHint >= 0 && meta.priceHint <= 8 ? meta.priceHint : 8;
    candidates.push({ symbol, price: D(closes[i]).toDecimalPlaces(precision).toFixed(), date, source: 'yahoo-close', fetchedAt: new Date(now).toISOString() });
  }
  candidates.sort((a, b) => b.date.localeCompare(a.date));
  const quote = candidates[0];
  if (!quote) throw Error('暂时没有已完成交易日的收盘价');
  if (D(quote.price).gte('1000000000000') || !D(quote.price).gt(0)) throw Error('股价超出支持范围');
  const splits: {symbol:string;date:string}[] = Object.values(r.events?.splits ?? {}).flatMap((e:any)=>Number.isFinite(e.date)&&e.date*1000<=now?[{symbol,date:marketDate(e.date*1000)}]:[]);
  return { quotes:candidates.filter(q=>D(q.price).gt(0)&&D(q.price).lt('1000000000000')), splits };
}
export function parseDailyClose(raw:unknown,symbol:string,now=Date.now()):Quote {return parseDailySeries(raw,symbol,now).quotes[0];}

export async function fetchSeries(symbol: string) {
  const url = `https://query2.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(providerSymbol(symbol))}?interval=1d&range=3mo&includePrePost=false&events=splits`;
  let body: unknown;
  if (Capacitor.isNativePlatform()) {
    const response = await CapacitorHttp.get({ url, responseType: 'json', connectTimeout: 12_000, readTimeout: 12_000, headers: { 'User-Agent': 'StockLedger/1.2 (personal portfolio)' } });
    if (response.status !== 200) throw Error(response.status === 429 ? '行情服务繁忙，请稍后再试' : `行情请求失败（${response.status}）`);
    body = typeof response.data === 'string' ? JSON.parse(response.data) : response.data;
  } else {
    const response = await fetch(url, { signal: AbortSignal.timeout(15_000), credentials: 'omit' });
    if (!response.ok) throw Error(response.status === 429 ? '行情服务繁忙，请稍后再试' : `行情请求失败（${response.status}）`);
    body = await response.json();
  }
  return parseDailySeries(body, symbol);
}
export async function fetchClose(symbol:string):Promise<Quote>{return (await fetchSeries(symbol)).quotes[0];}

export async function syncHistory(data:Ledger,fetcher=fetchSeries) {
  const symbols=new Set(calculate(data).open.map(p=>p.symbol));
  const cutoff=marketDate(Date.now()-100*86400000);
  data.trades.filter(t=>t.date>=cutoff).forEach(t=>symbols.add(t.symbol));
  const pending=[...new Set([...symbols,'SPY'])], closes:Quote[]=[], latest:Quote[]=[], splits:{symbol:string;date:string}[]=[], sessions:string[]=[], errors:SyncResult['errors']=[];
  let next=0,checkedAt:string|undefined;
  await Promise.all([0,1].map(async()=>{while(next<pending.length){const symbol=pending[next++];try{
    const series=await fetcher(symbol);
    if(symbol==='SPY'){sessions.push(...series.quotes.map(q=>q.date));checkedAt=new Date().toISOString();}
    if(symbols.has(symbol)){closes.push(...series.quotes);latest.push(series.quotes[0]);splits.push(...series.splits);}
  }catch(e){errors.push({symbol:symbol==='SPY'?'SPY / 交易日历':symbol,reason:e instanceof Error?e.message:'网络连接失败'});}}}));
  const merged=mergeCloses(data,latest);
  return {...merged,data:validateLedger({...merged.data,history:mergeHistory(data.history,closes,sessions,splits,checkedAt)}),errors};
}

export interface SyncResult { quotes: Quote[]; errors: { symbol: string; reason: string }[] }
export async function collectCloses(symbols: string[], fetcher = fetchClose): Promise<SyncResult> {
  const pending = [...new Set(symbols)], result: SyncResult = { quotes: [], errors: [] };
  let next = 0;
  // Two requests at a time; one failed symbol never clears other prices.
  await Promise.all([0, 1].map(async () => {
    while (next < pending.length) {
      const symbol = pending[next++];
      try { result.quotes.push(await fetcher(symbol)); }
      catch (e) { result.errors.push({ symbol, reason: e instanceof Error ? e.message : '网络连接失败' }); }
    }
  }));
  return result;
}

export function mergeCloses(data: Ledger, quotes: Quote[]) {
  const open = new Set(calculate(data).open.map(p => p.symbol));
  const map = new Map(data.quotes.map(q => [q.symbol, q]));
  let updated = 0, retained = 0;
  for (const quote of quotes) {
    if (!open.has(quote.symbol)) continue;
    const existing = map.get(quote.symbol);
    // Never replace a newer quote. A manual quote wins on the same date.
    if (existing && (existing.date > quote.date || (existing.date === quote.date && existing.source !== 'yahoo-close'))) { retained++; continue; }
    map.set(quote.symbol, quote); updated++;
  }
  return { data: validateLedger({ ...data, quotes: [...map.values()] }), updated, retained };
}

export function quoteAgeWarning(quote: Quote, now = Date.now()) {
  return Date.parse(marketDate(now)) - Date.parse(quote.date) > 4 * 86_400_000;
}
