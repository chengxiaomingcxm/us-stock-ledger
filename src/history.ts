import { D, orderedTrades, type Ledger, type History, type Close } from './ledger';

export const emptyHistory=():History=>({version:1,closes:[],sessions:[],splits:[]});
export function mergeHistory(old:History|undefined, closes:Close[], sessions:string[], splits:History['splits'], checkedAt?:string):History {
  const base=old??emptyHistory(), map=new Map(base.closes.map(c=>[c.symbol+'|'+c.date,c]));
  for(const c of closes)map.set(c.symbol+'|'+c.date,{symbol:c.symbol,date:c.date,price:c.price});
  const days=[...new Set([...base.sessions,...sessions])].sort().slice(-4000);
  const all=[...map.values()].sort((a,b)=>a.date.localeCompare(b.date)||a.symbol.localeCompare(b.symbol));
  // Evict whole oldest dates, never a random subset of a trading day.
  while(all.length>25000){const date=all[0].date;const end=all.findIndex(c=>c.date!==date);all.splice(0,end<0?all.length:end);}
  const actions=new Map([...base.splits,...splits].map(s=>[s.symbol+s.date,s]));
  return {version:1,closes:all,sessions:days,splits:[...actions.values()].slice(-5000),...(checkedAt||base.checkedAt?{checkedAt:checkedAt??base.checkedAt}:{})};
}
type Amount=ReturnType<typeof D>;
export interface Contribution {symbol:string; profit?:Amount; reason?:string}
export interface DayReturn {date:string; previous?:string; profit?:Amount; cumulative?:Amount; contributions:Contribution[]; missing:string[]}

/** P&L = ending stock value - opening stock value + net sales - purchases.
 * Replays the current ledger, so edited historical trades cannot leave stale profits. */
export function dailyReturns(data:Ledger):DayReturn[] {
  const history=data.history;if(!history?.sessions.length||!data.trades.length)return [];
  const trades=orderedTrades(data.trades), prices=new Map(history.closes.map(c=>[c.symbol+'|'+c.date,D(c.price)]));
  const dates=history.sessions, qty=new Map<string,Amount>(), output:DayReturn[]=[];
  const first=new Map<string,string>();for(const t of trades)if(!first.has(t.symbol))first.set(t.symbol,t.date);
  const splitSymbols=new Set(history.splits.filter(s=>first.has(s.symbol)&&s.date>=first.get(s.symbol)!).map(s=>s.symbol));
  let index=0,cash=D(0);
  const apply=(t:Ledger['trades'][number])=>{const net=t.side==='buy'?D(t.quantity).mul(t.price).plus(t.fee).neg():D(t.quantity).mul(t.price).minus(t.fee);qty.set(t.symbol,(qty.get(t.symbol)??D(0)).plus(D(t.quantity).mul(t.side==='buy'?1:-1)));cash=cash.plus(net);return net;};
  for(let i=0;i<dates.length;i++){
    const date=dates[i],previous=dates[i-1];
    if(date<trades[0].date)continue;
    const straySymbols=new Set<string>();
    while(index<trades.length&&trades[index].date<date){const t=trades[index++];if(previous&&t.date>previous)straySymbols.add(t.symbol);apply(t);}
    let gap=false;
    if(previous){for(let ms=Date.parse(previous)+86400000;ms<Date.parse(date);ms+=86400000){if(!knownClosed(new Date(ms).toISOString().slice(0,10))){gap=true;break;}}}
    const opening=new Map(qty), flows=new Map<string,Amount>();
    while(index<trades.length&&trades[index].date===date){const t=trades[index++];flows.set(t.symbol,(flows.get(t.symbol)??D(0)).plus(apply(t)));}
    const symbols=[...new Set([...opening.keys(),...qty.keys(),...flows.keys()])].filter(s=>(opening.get(s)??D(0)).gt(0)||(qty.get(s)??D(0)).gt(0)||flows.has(s));
    let sum=D(0),value=D(0),endComplete=true;
    const missing:string[]=[], contributions:Contribution[]=[];
    for(const symbol of symbols){
      const start=opening.get(symbol)??D(0),end=qty.get(symbol)??D(0),before=previous?prices.get(symbol+'|'+previous):undefined,after=prices.get(symbol+'|'+date);
      // Yahoo can revise old bars for splits; v1.2 has no split bookkeeping.
      // Flag affected symbols instead of manufacturing a daily return.
      const split=splitSymbols.has(symbol);
      const stray=straySymbols.has(symbol);
      let reason:string|undefined;
      if(split)reason='发现拆股，需先核对股数与成本';
      else if(stray)reason='相邻交易日之间有交易记录，请核对美东交易日期';
      else if(gap&&start.gt(0))reason='相邻收盘记录之间有未确认日期';
      else if(start.gt(0)&&before===undefined)reason=`缺少 ${previous??'前一交易日'} 收盘价`;
      else if(end.gt(0)&&after===undefined)reason=`缺少 ${date} 收盘价`;
      if(end.gt(0)&&after!==undefined&&!split)value=value.plus(end.mul(after));else if(end.gt(0))endComplete=false;
      if(split)endComplete=false;
      if(reason){missing.push(`${symbol}：${reason}`);contributions.push({symbol,reason});}
      else {const profit=(end.gt(0)?end.mul(after!):D(0)).minus(start.gt(0)?start.mul(before!):D(0)).plus(flows.get(symbol)??D(0));sum=sum.plus(profit);contributions.push({symbol,profit});}
    }
    if([...splitSymbols].some(s=>first.get(s)!<=date))endComplete=false;
    output.push({date,previous,profit:missing.length?undefined:sum,cumulative:endComplete?value.plus(cash):undefined,contributions,missing});
  }
  return output;
}

// Confirmed NYSE holiday dates, 2026–2028. Unknown weekdays are never called holidays.
// https://www.nyse.com/trade/hours-calendars (checked 2026-09-15)
const holidays=new Set(['2026-01-01','2026-01-19','2026-02-16','2026-04-03','2026-05-25','2026-06-19','2026-07-03','2026-09-07','2026-11-26','2026-12-25','2027-01-01','2027-01-18','2027-02-15','2027-03-26','2027-05-31','2027-06-18','2027-07-05','2027-09-06','2027-11-25','2027-12-24','2028-01-17','2028-02-21','2028-04-14','2028-05-29','2028-06-19','2028-07-04','2028-09-04','2028-11-23','2028-12-25']);
export function knownClosed(date:string){const weekday=new Date(date+'T12:00:00Z').getUTCDay();return weekday===0||weekday===6||holidays.has(date);}
export function monthStats(days:DayReturn[],month:string){const rows=days.filter(d=>d.date.startsWith(month)),complete=rows.filter(d=>d.profit!==undefined);return {rows,complete,missing:rows.length-complete.length,profit:complete.reduce((a,d)=>a.plus(d.profit!),D(0))};}
