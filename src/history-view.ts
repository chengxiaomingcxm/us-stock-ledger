import { D, signedMoney, type Ledger } from './ledger';
import { dailyReturns, knownClosed, monthStats, type DayReturn } from './history';
import { marketDate } from './market';
const esc=(v:string)=>v.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const tone=(v:ReturnType<typeof D>|undefined)=>v===undefined?'muted':v.gt(0)?'positive':v.lt(0)?'negative':'neutral';
let cached:Ledger|undefined, days:DayReturn[]=[];
export function historyDays(data:Ledger){if(cached!==data){cached=data;days=dailyReturns(data);}return days;}
export function historyPanel(data:Ledger,month:string){
 const all=historyDays(data), stats=monthStats(all,month), byDate=new Map(all.map(d=>[d.date,d]));
 const today=marketDate(Date.now()),firstTrade=data.trades.map(t=>t.date).sort()[0];
 const [year,m]=month.split('-').map(Number),length=new Date(Date.UTC(year,m,0)).getUTCDate(),offset=(new Date(month+'-01T12:00:00Z').getUTCDay()+6)%7;
 const latest=all.at(-1);
 const cells=Array.from({length},(_,i)=>{const date=month+'-'+String(i+1).padStart(2,'0'),day=byDate.get(date);
  const text=day?(day.profit===undefined?'待补全':signedMoney(day.profit)):date>today?'—':knownClosed(date)?'休市':!firstTrade||date<firstTrade?'未建仓':'未确认';
  const compact=day?.profit!==undefined?(day.profit.abs().gte(10000)?`${day.profit.gt(0)?'+':''}${day.profit.div(1000).toFixed(1)}k`:text.replace('$','')):text;
  return `<button class="calendar-day ${tone(day?.profit)}" data-day="${date}" aria-label="${date} ${text}"><span>${i+1}</span><b>${compact}</b></button>`;
 }).join('');
 const valued=stats.rows.filter(d=>d.cumulative!==undefined), values=valued.map(d=>d.cumulative!.toNumber());
 const min=Math.min(0,...values),max=Math.max(0,...values),range=max-min||1;
 const x=(date:string)=>30+(Number(date.slice(-2))-1)/Math.max(1,length-1)*540;
 const y=(value:number)=>170-(value-min)/range*140;
 let path='',connected=false;
 for(const row of stats.rows){if(row.cumulative===undefined){connected=false;continue;}path+=`${connected?' L':' M'}${x(row.date).toFixed(1)},${y(row.cumulative.toNumber()).toFixed(1)}`;connected=true;}
 return `<section class="panel" aria-label="每日收益"><div class="section-heading"><h2>每日收益</h2><span class="caption">美东交易日 · USD</span></div>
 <div class="daily-latest"><span>${latest?`${latest.date} 最近已记录交易日`:'等待首次收盘同步'}</span><strong class="${tone(latest?.profit)}" data-testid="daily-profit">${latest?signedMoney(latest.profit):'—'}</strong></div>
 <div class="month-navigation"><button class="secondary" data-month="-1" aria-label="上个月">‹</button><label>月份 <input id="history-month" type="month" value="${month}" min="1900-01" max="${today.slice(0,7)}"></label><button class="secondary" data-month="1" aria-label="下个月" ${month>=today.slice(0,7)?'disabled':''}>›</button></div>
 <div class="month-summary"><span>本月已记录收益 <strong class="${tone(stats.profit)}">${stats.complete.length?signedMoney(stats.profit):'—'}</strong></span><small>${stats.complete.length} 个完整交易日${stats.missing?` · ${stats.missing} 日待补全`:''}；未确认日期不计入合计。</small></div>
 <div class="calendar-week">${['一','二','三','四','五','六','日'].map(d=>`<span>${d}</span>`).join('')}</div><div class="profit-calendar">${'<span></span>'.repeat(offset)}${cells}</div>
 <p class="panel-footnote">点选日期查看准确金额与各股票贡献，k 表示千美元。每日收益 = 期末市值 − 期初市值 + 卖出净收入 − 买入含费支出。缺失行情不按零收益计算。</p>
 <h3 class="chart-title">收盘累计收益曲线</h3>${valued.length?`<svg class="profit-chart" viewBox="0 0 600 205" role="img" aria-label="${month} 收盘累计收益曲线，最低 ${min.toFixed(2)} 美元，最高 ${max.toFixed(2)} 美元"><line x1="30" x2="570" y1="${y(0)}" y2="${y(0)}" stroke="#d7dfe6"/><path d="${path}" fill="none" stroke="#17786d" stroke-width="3"/>${valued.map(d=>`<circle cx="${x(d.date)}" cy="${y(d.cumulative!.toNumber())}" r="3" fill="#17786d"><title>${d.date}: ${signedMoney(d.cumulative)}</title></circle>`).join('')}<text x="30" y="198">${month}-01</text><text x="490" y="198">${month}-${length}</text></svg><div class="chart-range"><span>低 ${signedMoney(D(min))}</span><span>高 ${signedMoney(D(max))}</span></div>`:'<p class="small-empty">同步行情后显示曲线。历史数据不足的日期留空。</p>'}
 <p class="panel-footnote">曲线按各日收盘价计算累计投资收益，可能与手动报价计算的当前收益不同。首次尝试补齐近三个月行情，以后保留已同步历史；不含分红和拆股调整。</p></section>`;
}
export function dayDetails(data:Ledger,date:string){const d=historyDays(data).find(d=>d.date===date);return d?`<p class="summary-number ${tone(d.profit)}">${signedMoney(d.profit)}</p><p class="dialog-copy">${d.previous?`与 ${d.previous} 收盘比较`:'首个已记录交易日'} · 已计入当天买卖及手续费</p>${d.contributions.map(c=>`<div class="realized-row"><b>${esc(c.symbol)}</b><span class="${tone(c.profit)}">${c.reason?esc(c.reason):signedMoney(c.profit)}</span></div>`).join('')||'<p>当天无持仓和交易。</p>'}`:`<p class="dialog-copy">${knownClosed(date)?'此日期休市，没有每日收益记录。':'此日期尚无已确认的收益记录。请更新行情；较早的历史数据可能不在本次服务返回范围内。'}</p>`;}
