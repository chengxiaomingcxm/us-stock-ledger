// Frozen original ledger implementation, source: e06032994ca92d78bd343275accb1f66cb92cb80
import Decimal from 'decimal.js';
Decimal.set({ precision: 40, rounding: Decimal.ROUND_HALF_UP });
export const D = (v: Decimal.Value) => new Decimal(v);
export interface Trade { id: string; sequence: number; symbol: string; side: 'buy' | 'sell'; date: string; quantity: string; price: string; fee: string; note: string }
export interface Quote { symbol: string; price: string; date: string }
export interface Ledger { version: 1; currency: 'USD'; method: 'moving-average'; trades: Trade[]; quotes: Quote[] }
export interface Position { symbol: string; quantity: Decimal; cost: Decimal; realized: Decimal; average: Decimal; quote?: Quote; value?: Decimal; unrealized?: Decimal }
export const emptyLedger = (): Ledger => ({ version: 1, currency: 'USD', method: 'moving-average', trades: [], quotes: [] });
export function today() { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; }
const isRecord = (x: unknown): x is Record<string, unknown> => !!x && typeof x === 'object' && !Array.isArray(x);
export function numberText(v: unknown, label: string, positive = false): string {
  if (typeof v !== 'string' || !/^\d{1,12}(\.\d{1,8})?$/.test(v)) throw new Error(`${label}请填写有效数字，最多 8 位小数。`);
  const d = D(v); if (positive && !d.gt(0)) throw new Error(`${label}必须大于 0。`); return d.toFixed();
}
function validDate(v: unknown): string {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v) || !Number.isFinite(Date.parse(v+'T00:00:00Z')) || new Date(v+'T00:00:00Z').toISOString().slice(0,10)!==v || v<'1900-01-01' || v>today()) throw new Error('日期必须是真实日期，且不能晚于今天。');
  return v;
}
function symbolText(v: unknown) { if (typeof v !== 'string' || !/^[A-Z][A-Z0-9.\-]{0,14}$/.test(v)) throw new Error('股票代码须为 1–15 位大写字母、数字、点或连字符。'); return v; }
export function validateLedger(raw: unknown): Ledger {
  if (!isRecord(raw) || raw.version!==1 || raw.currency!=='USD' || raw.method!=='moving-average' || !Array.isArray(raw.trades) || !Array.isArray(raw.quotes)) throw new Error('文件不是受支持的持仓账本备份（版本 1 / 美元 / 移动平均成本）。');
  if (raw.trades.length>5000 || raw.quotes.length>5000) throw new Error('此版本最多支持 5,000 笔交易和 5,000 个报价。');
  const ids = new Set<string>(); const seqs = new Set<number>(); const quoteSymbols = new Set<string>();
  const trades: Trade[] = raw.trades.map(t => {
    if (!isRecord(t) || typeof t.id!=='string' || !/^[\w-]{1,80}$/.test(t.id) || ids.has(t.id) || !Number.isSafeInteger(t.sequence) || (t.sequence as number)<0 || seqs.has(t.sequence as number) || !['buy','sell'].includes(t.side as string) || typeof t.note!=='string' || t.note.length>500) throw new Error('交易记录格式错误，或存在重复记录编号。');
    ids.add(t.id); seqs.add(t.sequence as number);
    return { id:t.id, sequence:t.sequence as number, symbol:symbolText(t.symbol), side:t.side as 'buy'|'sell', date:validDate(t.date), quantity:numberText(t.quantity,'股数',true), price:numberText(t.price,'成交单价',true), fee:numberText(t.fee,'手续费'), note:t.note };
  });
  const quotes: Quote[] = raw.quotes.map(q => {
    if (!isRecord(q)) throw new Error('股价格式错误。'); const symbol=symbolText(q.symbol);
    if (quoteSymbols.has(symbol)) throw new Error('存在重复股价。'); quoteSymbols.add(symbol);
    return {symbol, price:numberText(q.price,'最新股价'),date:validDate(q.date)};
  });
  const data: Ledger = {version:1,currency:'USD',method:'moving-average',trades,quotes}; calculate(data); return data;
}
export function orderedTrades(trades: Trade[]) { return [...trades].sort((a,b)=>a.date.localeCompare(b.date)||a.sequence-b.sequence); }
export function calculate(data: Ledger) {
  const map = new Map<string,Position>(); const gains = new Map<string,Decimal>(); let fees=D(0), buyTotal=D(0), sellTotal=D(0);
  for (const t of orderedTrades(data.trades)) {
    const p = map.get(t.symbol) ?? { symbol:t.symbol,quantity:D(0),cost:D(0),realized:D(0),average:D(0) };
    const q=D(t.quantity), gross=q.mul(t.price), fee=D(t.fee); fees=fees.plus(fee);
    if (t.side==='buy') { p.cost=p.cost.plus(gross).plus(fee); p.quantity=p.quantity.plus(q); buyTotal=buyTotal.plus(gross).plus(fee); }
    else {
      if (q.gt(p.quantity)) throw new Error(`${t.date} 的 ${t.symbol} 卖出 ${q.toFixed()} 股，超过当时持仓 ${p.quantity.toFixed()} 股。请先修正相关交易。`);
      const removed=q.eq(p.quantity)?p.cost:p.cost.mul(q).div(p.quantity);
      const profit=gross.minus(fee).minus(removed); p.realized=p.realized.plus(profit); gains.set(t.id,profit);
      p.cost=p.cost.minus(removed); p.quantity=p.quantity.minus(q); sellTotal=sellTotal.plus(gross).minus(fee);
    }
    p.average=p.quantity.gt(0)?p.cost.div(p.quantity):D(0); map.set(t.symbol,p);
  }
  const quotes=new Map(data.quotes.map(q=>[q.symbol,q]));
  const positions=[...map.values()].sort((a,b)=>a.symbol.localeCompare(b.symbol));
  for(const p of positions) { p.quote=quotes.get(p.symbol); if(p.quote) {p.value=p.quantity.mul(p.quote.price);p.unrealized=p.value.minus(p.cost);} }
  const open=positions.filter(p=>p.quantity.gt(0)); const missing=open.filter(p=>!p.quote);
  const sum=(xs:Decimal[])=>xs.reduce((a,b)=>a.plus(b),D(0));
  const cost=sum(open.map(p=>p.cost)); const realized=sum(positions.map(p=>p.realized));
  const value=missing.length?undefined:sum(open.map(p=>p.value!)); const unrealized=value?.minus(cost);
  return {positions,open,missing,cost,realized,value,unrealized,totalProfit:unrealized?.plus(realized),gains,fees,buyTotal,sellTotal};
}
export function saveTrade(data: Ledger, trade: Trade) { return validateLedger({...data,trades:[...data.trades.filter(t=>t.id!==trade.id),trade]}); }
export function deleteTrade(data: Ledger,id:string) { return validateLedger({...data,trades:data.trades.filter(t=>t.id!==id)}); }
export function parseBackup(text:string): Ledger { if(text.length>8_000_000) throw new Error('备份文件过大。'); let raw; try {raw=JSON.parse(text);} catch {throw new Error('文件内容不是有效的 JSON 备份。');} return validateLedger(raw); }
export function backupText(data:Ledger) {return JSON.stringify(validateLedger(data),null,2);}
export function money(v:Decimal.Value|undefined) { if(v===undefined)return '—'; const d=D(v); const [whole,frac]=d.abs().toFixed(2).split('.'); return `${d.lt(0)?'−':''}$${whole.replace(/\B(?=(\d{3})+(?!\d))/g,',')}.${frac}`; }
export function signedMoney(v:Decimal.Value|undefined) { return v===undefined?'—':`${D(v).gt(0)?'+':''}${money(v)}`; }
export function quantity(v:Decimal.Value) {return D(v).toDecimalPlaces(8).toFixed();}
export function demoLedger(): Ledger { return validateLedger({ ...emptyLedger(),trades:[
  {id:'demo-aapl-buy',sequence:0,symbol:'AAPL',side:'buy',date:'2025-01-10',quantity:'20',price:'180',fee:'1',note:'分批建仓'},
  {id:'demo-msft-buy',sequence:1,symbol:'MSFT',side:'buy',date:'2025-02-12',quantity:'8',price:'390',fee:'1',note:'长期持有'},
  {id:'demo-nvda-buy',sequence:2,symbol:'NVDA',side:'buy',date:'2025-03-03',quantity:'30',price:'110',fee:'1',note:''},
  {id:'demo-aapl-sell',sequence:3,symbol:'AAPL',side:'sell',date:'2025-04-08',quantity:'5',price:'215',fee:'1',note:'部分止盈'}
],quotes:[{symbol:'AAPL',price:'225',date:'2025-04-09'},{symbol:'MSFT',price:'420',date:'2025-04-09'},{symbol:'NVDA',price:'125',date:'2025-04-09'}]}); }

