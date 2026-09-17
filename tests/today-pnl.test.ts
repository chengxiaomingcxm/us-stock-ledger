import {it,expect,vi,beforeEach,afterEach} from 'vitest';
import {emptyLedger,validateLedger,type Trade,type Ledger} from '../src/ledger';
import {mergeHistory} from '../src/history';
import {todayPnl} from '../src/today-pnl';

const trade=(v:Partial<Trade>={}):Trade=>({id:'b',sequence:0,symbol:'AAPL',date:'2026-09-08',side:'buy',quantity:'10',price:'100',fee:'1',note:'',...v});
const base=(trades:Trade[]=[trade()],closes:{symbol:string;date:string;price:string}[]=[],sessions:string[]=[]):Ledger=>validateLedger({...emptyLedger(),trades,history:mergeHistory(undefined,closes,sessions,[])});
const close=(symbol:string,date:string,price:string)=>({symbol,date,price});
const seq=(t:Trade,n:number)=>({...t,sequence:n});
// 美东周三盘中（2026-09-16 12:00 EDT），周六（2026-09-12）休市。
const WED=Date.parse('2026-09-16T16:00:00Z'),SAT=Date.parse('2026-09-12T16:00:00Z');
beforeEach(()=>{vi.useFakeTimers();vi.setSystemTime(new Date('2026-09-16T22:00:00Z'));});
afterEach(()=>vi.useRealTimers());

it('上一收盘与当日报价齐全时，今日盈亏含涨跌、当天买卖与手续费',()=>{
 const d=base(
  [trade(),seq(trade({id:'b2',date:'2026-09-16',quantity:'5',price:'110',fee:'1'}),1),seq(trade({id:'s1',date:'2026-09-16',side:'sell',quantity:'3',price:'112',fee:'1'}),2)],
  [close('AAPL','2026-09-15','100')],['2026-09-15']);
 d.quotes=[{symbol:'AAPL',price:'115',date:'2026-09-16'}];
 const p=todayPnl(d,WED);
 expect(p.prevCloseDate).toBe('2026-09-15');expect(p.closed).toBe(false);expect(p.nonTrading).toBe(false);
 expect(p.tradedToday).toBe(2);expect(p.missing).toEqual([]);
 // 12×115 − 10×100 − (550+1) + (336−1) = 164
 expect(p.pnl!.toString()).toBe('164');expect(p.basis!.toString()).toBe('1000');expect(p.pct!.toFixed(2)).toBe('16.40');
});
it('无交易日（周六）按最近收盘比较，没有今日涨跌',()=>{
 const d=base([trade()],[close('AAPL','2026-09-11','110')],['2026-09-11']);
 d.quotes=[{symbol:'AAPL',price:'110',date:'2026-09-11',source:'yahoo-close'}];
 const p=todayPnl(d,SAT);
 expect(p.nonTrading).toBe(true);expect(p.pnl!.toString()).toBe('0');expect(p.missing).toEqual([]);
});
it('全部卖出当天不需要当日报价，手续费计入盈亏',()=>{
 const d=base([trade(),seq(trade({id:'s1',date:'2026-09-16',side:'sell',quantity:'10',price:'112',fee:'1'}),1)],[close('AAPL','2026-09-15','100')],['2026-09-15']);
 const p=todayPnl(d,WED);
 // 0 − 1000 + (1120−1) = 119
 expect(p.pnl!.toString()).toBe('119');expect(p.missing).toEqual([]);
});
it('部分卖出按卖出价实现、剩余持仓按现价浮动',()=>{
 const d=base([trade(),seq(trade({id:'s1',date:'2026-09-16',side:'sell',quantity:'3',price:'112',fee:'1'}),1)],[close('AAPL','2026-09-15','100')],['2026-09-15']);
 d.quotes=[{symbol:'AAPL',price:'115',date:'2026-09-16'}];
 // 7×115 − 10×100 + (336−1) = 140
 expect(todayPnl(d,WED).pnl!.toString()).toBe('140');
});
it('当日买入缺少当日报价时显示待补全',()=>{
 const d=base([seq(trade({id:'b2',date:'2026-09-16',quantity:'5',price:'110',fee:'1'}),0)],[],['2026-09-15']);
 let p=todayPnl(d,WED);expect(p.pnl).toBeUndefined();expect(p.missing.join()).toContain('AAPL');
 d.quotes=[{symbol:'AAPL',price:'100',date:'2026-09-15'}];
 p=todayPnl(d,WED);expect(p.pnl).toBeUndefined();expect(p.missing.join()).toContain('盘中尚未取得当日报价');
});
it('缺少上一交易日收盘价显示待补全，不以零代替',()=>{
 const d=base([trade()],[],['2026-09-15']);
 d.quotes=[{symbol:'AAPL',price:'115',date:'2026-09-16'}];
 const p=todayPnl(d,WED);
 expect(p.pnl).toBeUndefined();expect(p.missing.join()).toContain('缺少 2026-09-15 收盘价');
});
it('休市日只用已确认收盘，即使估值报价较旧也不制造涨跌',()=>{
 const d=base([trade()],[close('AAPL','2026-09-11','110')],['2026-09-11']);
 d.quotes=[{symbol:'AAPL',price:'105',date:'2026-09-10'}];
 const p=todayPnl(d,SAT);
 expect(p.nonTrading).toBe(true);expect(p.pnl!.toString()).toBe('0');expect(p.missing).toEqual([]);
});

it('旧日历不能把多日涨跌或昨天报价算作今日收益',()=>{
 const d=base([trade()],[close('AAPL','2026-09-11','100')],['2026-09-11']);
 for(const date of ['2026-09-15','2026-09-16']){
  d.quotes=[{symbol:'AAPL',price:'115',date}];
  const p=todayPnl(d,WED);expect(p.pnl).toBeUndefined();expect(p.prevCloseDate).toBeUndefined();expect(p.missing.join()).toContain('2026-09-15');
 }
});
it('市场已收盘但个股收盘价缺失时不回退到旧报价或盘中报价',()=>{
 const d=base([trade()],[close('AAPL','2026-09-15','100')],['2026-09-15','2026-09-16']);
 for(const date of ['2026-09-15','2026-09-16']){
  d.quotes=[{symbol:'AAPL',price:'115',date}];
  const p=todayPnl(d,WED);expect(p.closed).toBe(true);expect(p.pnl).toBeUndefined();expect(p.missing.join()).toContain('缺少 2026-09-16 收盘价');
 }
});
it('拆股阻止误算，且不改写账本',()=>{
 const d=base([trade()],[close('AAPL','2026-09-15','100'),close('AAPL','2026-09-16','50')],['2026-09-15','2026-09-16']);
 d.history!.splits=[{symbol:'AAPL',date:'2026-09-16'}];d.quotes=[{symbol:'AAPL',price:'50',date:'2026-09-16'}];
 const original=JSON.stringify(d),p=todayPnl(d,WED);expect(p.pnl).toBeUndefined();expect(p.missing.join()).toContain('拆股');expect(JSON.stringify(d)).toBe(original);
});
it('休市日不把盘后报价变化计为今日收益',()=>{
 const d=base([trade()],[close('AAPL','2026-09-11','110')],['2026-09-11']);
 d.quotes=[{symbol:'AAPL',price:'112',date:'2026-09-11'}];expect(todayPnl(d,SAT).pnl!.toString()).toBe('0');
 d.history!.closes=[];expect(todayPnl(d,SAT).pnl).toBeUndefined();
});
it('周一和假日后使用最近交易日，而不是自然日昨天',()=>{
 const monday=base([trade()],[close('AAPL','2026-09-11','100')],['2026-09-11']);
 monday.quotes=[{symbol:'AAPL',price:'110',date:'2026-09-14'}];expect(todayPnl(monday,Date.parse('2026-09-14T16:00:00Z')).pnl!.toString()).toBe('100');
 const holiday=base([trade({date:'2026-09-01'})],[close('AAPL','2026-09-04','100')],['2026-09-04']);
 holiday.quotes=[{symbol:'AAPL',price:'110',date:'2026-09-08'}];expect(todayPnl(holiday,Date.parse('2026-09-08T16:00:00Z')).pnl!.toString()).toBe('100');
});
it('休市录入和跨时区旧记录提示核对，不自动改日期或算零',()=>{
 const d=base([trade({date:'2026-09-16'})]);
 expect(todayPnl(d,Date.parse('2026-09-15T21:00:00Z')).missing.join()).toContain('交易日期');
 expect(todayPnl(d,Date.parse('2026-09-15T21:00:00Z')).pnl).toBeUndefined();
 const weekend=base([trade({date:'2026-09-12'})],[close('AAPL','2026-09-11','100')],['2026-09-11']);
 expect(todayPnl(weekend,SAT).missing.join()).toContain('休市日存在交易');
 expect(todayPnl(weekend,Date.parse('2026-09-14T16:00:00Z')).missing.join()).toContain('交易日期');
 expect(weekend.trades[0].date).toBe('2026-09-12');
});
it('正常美东日期的新交易包含手续费；不接受未来或昨天报价',()=>{
 const d=base([trade({date:'2026-09-15'})]);
 d.quotes=[{symbol:'AAPL',price:'100',date:'2026-09-15'}];
 expect(todayPnl(d,Date.parse('2026-09-15T21:00:00Z')).pnl!.toString()).toBe('-1');
 for(const date of ['2026-09-14','2026-09-16']){d.quotes[0].date=date;expect(todayPnl(d,Date.parse('2026-09-15T21:00:00Z')).pnl).toBeUndefined();}
});
it('部分股票缺失时不把已完整部分合计冒充总收益',()=>{
 const d=base([trade(),seq(trade({id:'msft',symbol:'MSFT'}),1)],[close('AAPL','2026-09-15','100'),close('MSFT','2026-09-15','100')],['2026-09-15']);
 d.quotes=[{symbol:'AAPL',price:'110',date:'2026-09-16'}];const p=todayPnl(d,WED);
 expect(p.rows.find(r=>r.symbol==='AAPL')!.pnl!.toString()).toBe('100');expect(p.pnl).toBeUndefined();expect(p.missing.join()).toContain('MSFT');
});
it('今日收盘已确认时用当日收盘价计算',()=>{
 const d=base([trade()],[close('AAPL','2026-09-15','100'),close('AAPL','2026-09-16','116')],['2026-09-15','2026-09-16']);
 d.quotes=[{symbol:'AAPL',price:'116',date:'2026-09-16',source:'yahoo-close'}];
 const p=todayPnl(d,WED);
 expect(p.closed).toBe(true);expect(p.prevCloseDate).toBe('2026-09-15');expect(p.pnl!.toString()).toBe('160');
});
it('同日开仓清仓不需要任何行情',()=>{
 const d=base([seq(trade({id:'b2',date:'2026-09-16',quantity:'10',price:'110',fee:'1'}),0),seq(trade({id:'s1',date:'2026-09-16',side:'sell',quantity:'10',price:'120',fee:'0.5'}),1)]);
 const p=todayPnl(d,WED);
 // (1200−0.5) − (1100+1) = 98.5
 expect(p.pnl!.toString()).toBe('98.5');expect(p.missing).toEqual([]);
});
it('缺少交易日历时整体待补全',()=>{
 const d=base([trade()]);
 d.quotes=[{symbol:'AAPL',price:'115',date:'2026-09-16'}];
 const p=todayPnl(d,WED);
 expect(p.hasCalendar).toBe(false);expect(p.pnl).toBeUndefined();expect(p.missing).toHaveLength(1);
});
it('纯当日开仓的百分比无分母，不报错',()=>{
 const d=base([seq(trade({id:'b2',date:'2026-09-16',quantity:'5',price:'110',fee:'1'}),0)],[],['2026-09-15']);
 d.quotes=[{symbol:'AAPL',price:'115',date:'2026-09-16'}];
 const p=todayPnl(d,WED);
 // 5×115 − (550+1) = 24
 expect(p.pnl!.toString()).toBe('24');expect(p.pct).toBeUndefined();
});
