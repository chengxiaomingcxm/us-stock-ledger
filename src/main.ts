import './style.css';
import './home.css';
import './appearance.css';
import './v125.css';
import { defaults, loadAppearance, saveAppearance, applyAppearance, backupDue, type Appearance } from './preferences';
import { helpPage } from './help';
import { defaultApi, loadApi, saveApi, validateApi, fetchLive, withLive, type ApiSettings, type LiveQuote } from './quote-api';
import { createIcons, Wallet, ArrowUpRight, ArrowDownLeft, Plus, X, ChartNoAxesCombined, List, Settings, Download, Upload, ShieldCheck, ChevronRight, Search, Pencil, Trash2, RefreshCw, CircleHelp, ArrowLeft, Check, FileJson, Eye, EyeOff } from 'lucide';
import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { fetchClose, syncHistory, marketDate, logoUrl, quoteAgeWarning } from './market';
import { Filesystem, Directory, Encoding } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { D, emptyLedger, calculate, today, saveTrade, deleteTrade, validateLedger, parseBackup, backupText, demoLedger, money, signedMoney, quantity, orderedTrades, type Ledger, type Trade, type Quote } from './ledger';
import { knownClosed } from './history';
import { todayPnl } from './today-pnl';
import { rangeStats } from './trade-range';
import { store } from './storage';
import { historyPanel, dayDetails } from './history-view';
let historyMonth=marketDate(Date.now()).slice(0,7);
const icons={Wallet,ArrowUpRight,ArrowDownLeft,Plus,X,ChartNoAxesCombined,List,Settings,Download,Upload,ShieldCheck,ChevronRight,Search,Pencil,Trash2,RefreshCw,CircleHelp,ArrowLeft,Check,FileJson,Eye,EyeOff};
const app=document.querySelector<HTMLDivElement>('#app')!, modalRoot=document.querySelector<HTMLDivElement>('#modal-root')!;
let data=emptyLedger(), realData=data, tab='holdings', filter='', sideFilter='all', tradeFrom='', tradeTo='', demo=false, blocked=false, busy=false;
let modalGuard:(()=>boolean)|undefined;
let syncSummary='行情状态';
let syncing=false, syncMessage='打开时自动检查收盘价，也可随时手动更新。', syncErrors: {symbol:string;reason:string}[]=[], lastAttempt=0;
let api:ApiSettings={...defaultApi}, live=new Map<string,LiveQuote>(), liveSyncing=false, lastLiveAttempt=0, liveStatus='';
let appearance:Appearance={...defaults};
let undoTrade:string|undefined;
let liveFailures=0;
let amountsHidden=false, holdingFilter='all', holdingSort='symbol';
const homeMoney=(v:Parameters<typeof money>[0])=>amountsHidden?'••••':money(v);
const homeSigned=(v:Parameters<typeof signedMoney>[0])=>amountsHidden?'••••':signedMoney(v);
const homePercent=(profit:ReturnType<typeof D>|undefined,cost:ReturnType<typeof D>)=>amountsHidden?'••••':profit===undefined||!cost.gt(0)?'—':`${profit.gt(0)?'+':''}${profit.div(cost).mul(100).toFixed(2)}%`;
const displayLedger=()=>demo?data:withLive(data,live);
const failedLogos=new Set<string>();
const esc=(v:unknown)=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const icon=(name:string)=>`<i data-lucide="${name}" aria-hidden="true"></i>`;
const tone=(v:ReturnType<typeof D>|undefined)=>v===undefined?'muted':v.gt(0)?'positive':v.lt(0)?'negative':'neutral';
function refreshIcons(){createIcons({icons,attrs:{'stroke-width':1.7}});}
function toast(text:string){const el=document.querySelector<HTMLDivElement>('#toast')!;el.textContent=text;el.classList.add('visible');setTimeout(()=>el.classList.remove('visible'),4000);}
function nav(){return [{id:'holdings',name:'持仓',icon:'wallet'},{id:'trades',name:'交易',icon:'list'},{id:'add',name:'记一笔',icon:'plus'},{id:'insights',name:'收益',icon:'chart-no-axes-combined'},{id:'settings',name:'设置',icon:'settings'}].map(x=>x.id==='add'?`<button class="nav-item nav-add" data-action="add" aria-label="记一笔"><span class="nav-add-icon">${icon('plus')}</span><span>记一笔</span></button>`:`<button class="nav-item ${(tab===x.id||(tab==='help'&&x.id==='settings'))?'active':''}" data-tab="${x.id}" ${(tab===x.id||(tab==='help'&&x.id==='settings'))?'aria-current="page"':''}>${icon(x.icon)}<span>${x.name}</span></button>`).join('');}
function empty(title:string,text:string,actions=true){return `<div class="empty">${icon('wallet')}<h3>${title}</h3><p>${text}</p>${actions?`<button class="primary" data-action="add">${icon('plus')}记录第一笔交易</button><button class="text-button" data-action="demo">先看看示例账本 ${icon('arrow-up-right')}</button>`:''}</div>`;}
function companyLogo(symbol:string){
 return `<span aria-hidden="true">${esc(symbol.slice(0,1))}</span>${failedLogos.has(symbol)?'':`<img class="company-logo" data-symbol="${esc(symbol)}" src="${logoUrl(symbol)}" alt="${esc(symbol)} Logo" referrerpolicy="no-referrer" loading="lazy">`}`;
}
function marketPhase(){
 if(demo)return '示例行情';
 const t=marketDate(Date.now());
 if(knownClosed(t))return '美股休市';
 if(data.history?.sessions.includes(t))return '今日收盘已确认';
 return '交易日 · 等待当日收盘';
}
function quoteMeta(q:Quote){
 const item=isLive(q)?live.get(q.symbol)!:undefined;
 const time=item?new Date(item.timestamp).toLocaleTimeString('zh-CN',{timeZone:'America/New_York',hour:'2-digit',minute:'2-digit'})+' 美东':undefined;
 const label=item?`最新报价 · ${api.provider==='finnhub'?'Finnhub':'自定义 API'}`:q.source==='yahoo-close'?'美股收盘':'手动报价';
 const last=data.history?.sessions.at(-1),today=marketDate(Date.now());
 let note='';
 if(item&&Date.now()-item.timestamp>15*60_000)note=' · 超过 15 分钟，较早报价（休市时正常）';
 else if(!item&&last&&q.date<last)note=' · 早于最近交易日，待同步';
 else if(knownClosed(today)&&last===q.date)note=' · 休市中，按最近收盘';
 else if(quoteAgeWarning(q))note=' · 日期较早，请核对';
 return {time,label,note};
}
function marketStatus(){
 const quotes=calculate(displayLedger()).open.flatMap(p=>p.quote?[p.quote]:[]);
 const stale=quotes.some(q=>isLive(q)?Date.now()-live.get(q.symbol)!.timestamp>15*60_000:!!quoteAgeWarning(q));
 const count=quotes.filter(isLive).length;
 const text=demo?'示例行情':syncing||liveSyncing?'正在读取行情…':api.provider==='yahoo'?`${marketPhase()} · 收盘行情 · ${syncSummary}`:!lastLiveAttempt?`${marketPhase()} · 等待最新报价`:liveFailures?`${marketPhase()} · 最新价更新失败 ${liveFailures} 项 · 保留原报价`:`${marketPhase()} · ${count} 只最新价`+(stale?' · 含较早报价':'');
 return '<button class="market-status '+(liveFailures||syncErrors.length||stale?'sync-warning':'')+'" data-market-status aria-label="查看行情状态">'+icon('refresh-cw')+'<span data-testid="sync-status">'+esc(text)+'</span>'+icon('chevron-right')+'</button>';
}
function quoteList(){
 const open=calculate(displayLedger()).open;
 if(!open.length)return '';
 const rows=open.map(p=>{
  if(!p.quote)return `<div class="quote-row"><div><b>${esc(p.symbol)}</b><small>暂无报价 · 点“更新股价”填写</small></div><strong class="muted">待报价</strong></div>`;
  const meta=quoteMeta(p.quote);
  return `<div class="quote-row"><div><b>${esc(p.symbol)}</b><small>${esc(p.quote.date)}${meta.time?` ${meta.time}`:''} · ${esc(meta.label)}${esc(meta.note)}</small></div><strong>${homeMoney(p.quote.price)}</strong></div>`;
 }).join('');
 const last=data.history?.sessions.at(-1);
 return `<section class="panel quote-list" aria-label="各股票报价"><div class="section-heading"><h2>各股票报价</h2><span class="caption">${last?`最近已确认交易日 ${last}`:'尚未确认交易日历'}</span></div>${rows}</section>`;
}
function syncPanel(showButton=true){
 const source=`<button class="setting-row sync-source" data-api-source aria-label="更换行情来源"><span class="setting-icon">${icon('refresh-cw')}</span><span><b>更换行情来源</b><small>${api.provider==='yahoo'?'Yahoo Finance 收盘价':api.provider==='finnhub'?'Finnhub 最新报价':'自定义 HTTPS 接口'}</small></span>${icon('chevron-right')}</button>`;
 if(demo)return `<div class="sync-panel"><div><b>示例报价</b><small>虚构价格，不进行行情同步。</small></div></div>${source}`;
 const open=calculate(displayLedger()).open, dates=[...new Set(open.flatMap(p=>p.quote?[p.quote.date]:[]))].sort();
 const datesText=dates.length?(dates.length===1?`当前报价日期：${dates[0]}`:`当前报价跨多个日期：${dates[0]} 至 ${dates.at(-1)}`):'当前暂无报价';
 const checked=data.history?.checkedAt?`最近确认：${new Date(data.history.checkedAt).toLocaleString('zh-CN')} · 已记录至 ${data.history.sessions.at(-1)??'—'}`:'尚未确认交易日历';
 const old=open.some(p=>p.quote&&quoteAgeWarning(p.quote));
 const phaseText=`今日 ${marketDate(Date.now())} · ${marketPhase()}`;
 return `<section class="sync-panel" aria-label="行情同步"><div><b>${api.provider==='yahoo'?'收盘行情':'最新行情 · '+(api.provider==='finnhub'?'Finnhub':'自定义 API')}</b><small>${esc(phaseText)}</small>${api.provider!=='yahoo'?`<p role="status">${esc(liveStatus||'等待获取最新报价')}</p><small>自动刷新：${api.interval?api.interval+' 秒（仅前台）':'关闭'} · 实际延迟取决于数据源</small>`:''}<small>${esc(datesText)}<br>${esc(checked)}${old?' · 含较早报价，请核对':''}</small><p role="status" data-testid="sync-detail">${esc(syncing?'正在读取收盘价…':syncMessage)}</p>${syncErrors.length?`<details><summary>${syncErrors.length} 只未更新，查看原因</summary>${syncErrors.map(e=>`<p>${esc(e.symbol)}：${esc(e.reason)}</p>`).join('')}</details>`:''}</div>${showButton?`<button class="secondary" data-sync ${syncing||blocked||!data.trades.length?'disabled':''}>${icon('refresh-cw')}<span>${syncing?'更新中':'更新收益'}</span></button>`:''}</section>${quoteList()}${source}`;
}
async function syncPrices(manual=false){
 if(syncing||demo||blocked||busy||modalRoot.children.length||(!manual&&Date.now()-lastAttempt<15*60_000))return;
 const snapshot=data;
 if(!snapshot.trades.length)return;
 syncing=true;lastAttempt=Date.now();syncErrors=[];render();
 try {
  const result=await syncHistory(snapshot);
  // A transaction, import or manual edit during the request invalidates this batch.
  // This also prevents asynchronous work from replacing a newer saved ledger.
  if(demo||data!==snapshot||busy||modalRoot.children.length){syncSummary='更新已取消，请重试';syncMessage='账本正在编辑或已改变，本次报价未写入，请再次更新。';lastAttempt=0;return;}
  const merged=result;
  if(merged.updated||merged.data.history?.closes.length||merged.data.history?.sessions.length){busy=true;try{await commit(merged.data);}finally{busy=false;}}
  syncErrors=result.errors;syncSummary=result.errors.length?`${result.errors.length} 项更新失败`:`${merged.updated} 只更新`;
  const checkedAt=new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'});
  syncMessage=`${checkedAt} 检查：${merged.updated} 只取得收盘报价${merged.retained?`，${merged.retained} 只保留同日手动或较新报价`:''}${result.errors.length?`，${result.errors.length} 只更新失败，保留原报价`:''}。报价日期见下方各股票。`;
 }catch(e){syncSummary='行情更新失败';syncMessage=`未完成更新，原账本已保留：${e instanceof Error?e.message:'请检查网络后重试'}`;}
 finally {syncing=false;render();if(manual)toast(syncSummary);}
}
function render(){
 const openHelp=[...app.querySelectorAll<HTMLDetailsElement>('.help-chapter[open]')].map(el=>el.id);

 const s=calculate(displayLedger()); const titles:Record<string,string>={holdings:'持仓账本',trades:'交易记录',insights:'收益分析',settings:'设置',help:'帮助文档'};
 app.innerHTML=`<aside class="sidebar"><div class="brand"><span class="brand-icon">${icon('chart-no-axes-combined')}</span><div>持仓账本<small>STOCK LEDGER</small></div></div><nav>${nav()}</nav><div class="sidebar-foot">${icon('shield-check')}数据保存在本机<small>个人美股账本 · v1.25</small></div></aside>
 <div class="workspace ${tab==='holdings'?'home-workspace':''}">${demo?`<div class="demo-banner">${icon('eye')}示例模式 · 虚构交易与价格<button data-action="exit-demo">退出示例</button></div>`:''}
<header class="app-header">${tab==='help'?`<button class="icon-button header-back" data-tab="settings" aria-label="返回设置">${icon('arrow-left')}</button>`:''}<h1>${titles[tab]}</h1><div class="header-actions">${tab==='holdings'||tab==='insights'?`<button class="refresh-button" data-sync aria-label="更新收益" ${syncing||blocked||demo||!data.trades.length?'disabled':''}>${icon('refresh-cw')}</button>`:''}</div></header>

 ${undoTrade?`<div class="undo-bar" role="status">交易已保存<button class="text-button" id="undo-trade">撤销新增</button></div>`:''}
 ${blocked?`<div class="warning">本机账本无法读取，写入已暂停。请在备份页导入有效备份恢复。</div>`:''}
 <main>${tab==='holdings'?holdings(s):tab==='trades'?trades():tab==='insights'?insights(s):tab==='help'?helpPage():settings()}</main></div><nav class="bottom-nav">${nav()}</nav>`;
 app.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.tab!;filter='';render();window.scrollTo(0,0);});
 app.querySelectorAll<HTMLButtonElement>('[data-action="add"]').forEach(b=>{b.disabled=blocked;b.onclick=()=>tradeModal();});
 app.querySelectorAll<HTMLButtonElement>('[data-action="demo"]').forEach(b=>b.onclick=()=>{if(busy)return;realData=data;demo=true;undoTrade=undefined;data=demoLedger();tab='holdings';render();window.scrollTo(0,0);});
 app.querySelectorAll<HTMLButtonElement>('[data-action="exit-demo"]').forEach(b=>b.onclick=()=>{if(busy)return;demo=false;undoTrade=undefined;data=realData;render();window.scrollTo(0,0);});
 app.querySelectorAll<HTMLButtonElement>('[data-quote]').forEach(b=>b.onclick=()=>quoteModal(b.dataset.quote!));
 app.querySelectorAll<HTMLButtonElement>('[data-edit]').forEach(b=>b.onclick=()=>tradeModal(data.trades.find(t=>t.id===b.dataset.edit)!));
 app.querySelectorAll<HTMLButtonElement>('[data-delete]').forEach(b=>b.onclick=()=>deleteModal(data.trades.find(t=>t.id===b.dataset.delete)!));
 const search=app.querySelector<HTMLInputElement>('#search');if(search)search.oninput=()=>{const pos=search.selectionStart;filter=search.value;render();const n=app.querySelector<HTMLInputElement>('#search')!;n.focus();n.setSelectionRange(pos,pos);};
 const rangeFrom=app.querySelector<HTMLInputElement>('#trade-from');if(rangeFrom)rangeFrom.onchange=()=>{tradeFrom=rangeFrom.value;if(tradeFrom&&tradeTo&&tradeFrom>tradeTo){const x=tradeFrom;tradeFrom=tradeTo;tradeTo=x;}render();};
 const rangeTo=app.querySelector<HTMLInputElement>('#trade-to');if(rangeTo)rangeTo.onchange=()=>{tradeTo=rangeTo.value;if(tradeFrom&&tradeTo&&tradeFrom>tradeTo){const x=tradeFrom;tradeFrom=tradeTo;tradeTo=x;}render();};
 const clearTrade=app.querySelector<HTMLButtonElement>('#clear-trade-filters');if(clearTrade)clearTrade.onclick=()=>{filter='';sideFilter='all';tradeFrom='';tradeTo='';render();};
 app.querySelectorAll<HTMLButtonElement>('[data-side-filter]').forEach(b=>b.onclick=()=>{sideFilter=b.dataset.sideFilter!;render();});
 app.querySelectorAll<HTMLButtonElement>('[data-market-status]').forEach(b=>b.onclick=()=>{modal('行情状态',syncPanel(false));modalRoot.querySelector<HTMLButtonElement>('[data-api-source]')?.addEventListener('click',()=>apiModal());});
 const ex=app.querySelector<HTMLButtonElement>('#export');if(ex)ex.onclick=()=>void exportBackup();
 const im=app.querySelector<HTMLInputElement>('#import');if(im)im.onchange=()=>void importFile(im.files?.[0]);
 app.querySelectorAll<HTMLButtonElement>('[data-sync]').forEach(b=>b.onclick=()=>{void syncLivePrices(true);void syncPrices(true);});
 app.querySelectorAll<HTMLImageElement>('.company-logo').forEach(img=>{const failed=()=>{failedLogos.add(img.dataset.symbol!);img.remove();};img.onerror=failed;if(img.complete&&img.naturalWidth===0)failed();});
 const compat=app.querySelector<HTMLButtonElement>('#export-compatible');if(compat)compat.onclick=()=>void exportBackup(true);
 const recovery=app.querySelector<HTMLButtonElement>('#recovery');if(recovery)recovery.onclick=()=>void showRecovery();
 app.querySelectorAll<HTMLButtonElement>('[data-day]').forEach(b=>b.onclick=()=>modal(`${b.dataset.day} 收益明细`,dayDetails(data,b.dataset.day!)));
 app.querySelectorAll<HTMLButtonElement>('[data-month]').forEach(b=>b.onclick=()=>{const d=new Date(historyMonth+'-01T12:00:00Z');d.setUTCMonth(d.getUTCMonth()+Number(b.dataset.month));const next=d.toISOString().slice(0,7);if(next>='1900-01'&&next<=marketDate(Date.now()).slice(0,7)){historyMonth=next;render();}});
 const month=app.querySelector<HTMLInputElement>('#history-month');if(month)month.onchange=()=>{if(/^\d{4}-\d{2}$/.test(month.value)&&month.validity.valid){historyMonth=month.value;render();}};
 app.querySelectorAll<HTMLButtonElement>('[data-position]').forEach(b=>b.onclick=()=>positionModal(b.dataset.position!));
 const eye=app.querySelector<HTMLButtonElement>('#hide-amounts');if(eye)eye.onclick=()=>{amountsHidden=!amountsHidden;render();app.querySelector<HTMLButtonElement>('#hide-amounts')?.focus();};
 app.querySelectorAll<HTMLButtonElement>('[data-holding-filter]').forEach(b=>b.onclick=()=>{holdingFilter=b.dataset.holdingFilter!;render();});
 const sort=app.querySelector<HTMLSelectElement>('#holding-sort');if(sort)sort.onchange=()=>{holdingSort=sort.value;render();};
 for(const id of openHelp){const el=document.getElementById(id);if(el instanceof HTMLDetailsElement)el.open=true;}

 const undo=app.querySelector<HTMLButtonElement>('#undo-trade');if(undo)undo.onclick=()=>{const id=undoTrade;if(!id)return;modal('撤销刚才新增的交易？','<p class="dialog-copy">将删除这笔交易并重新计算收益。</p><p id="form-error" role="alert"></p><button class="primary full" id="confirm-undo">确认撤销</button>');modalRoot.querySelector<HTMLButtonElement>('#confirm-undo')!.onclick=()=>void submit(async()=>{await commit(deleteTrade(data,id),'撤销新增交易前');undoTrade=undefined;});};
 app.querySelectorAll<HTMLSelectElement>('[data-preference]').forEach(el=>{el.value=String(appearance[el.dataset.preference as keyof Appearance]);el.onchange=async()=>{const field=el.dataset.preference as 'theme'|'colors'|'reminderDays';const next={...appearance,[field]:field==='reminderDays'?Number(el.value):el.value} as Appearance;el.disabled=true;try{await saveAppearance(next);appearance=next;applyAppearance(appearance);render();}catch{toast('设置保存失败，请重试');el.value=String(appearance[field]);}finally{el.disabled=false;}};});
 const backup=app.querySelector<HTMLButtonElement>('#backup-reminder');if(backup)backup.onclick=()=>{tab='settings';render();};
 refreshIcons();
}
function todayCard(s:ReturnType<typeof calculate>){
 const p=todayPnl(displayLedger());
 const caption=!s.open.length&&!p.tradedToday
  ?'暂无持仓 · 记一笔后计算今日盈亏'
  :p.pnl===undefined
  ?`${p.missing[0]?p.missing[0]:'缺少必要行情'}${p.missing.length>1?` 等 ${p.missing.length} 项`:' · 待补全'}`.replace('：',' · ')
  :p.closed?`美东 ${p.today} · 已确认收盘${p.prevCloseDate?' · 对比 '+p.prevCloseDate:''}`
  :p.nonTrading?`美东 ${p.today} · 今日休市${p.prevCloseDate?' · 按 '+p.prevCloseDate+' 收盘':''}`
  :`美东 ${p.today} · ${p.prevCloseDate?'对比 '+p.prevCloseDate+' 收盘':'当日交易盈亏'}`;
 const coverage=`报价覆盖 ${s.open.length-s.missing.length}/${s.open.length} 只`;
 return `<section class="valuation-card" aria-label="今日盈亏与持仓估值"><div class="valuation-top"><div><h2>今日盈亏 <span>USD</span></h2><p>${esc(caption)}</p></div><button class="privacy-button" id="hide-amounts" aria-label="${amountsHidden?'显示首页金额':'隐藏首页金额'}" aria-pressed="${amountsHidden}">${icon(amountsHidden?'eye-off':'eye')}</button></div><div class="valuation-profit ${amountsHidden||p.pnl===undefined?'neutral':tone(p.pnl)}" data-testid="today-pnl">${p.pnl===undefined?'待补全':homeSigned(p.pnl)}</div><div class="valuation-percent ${amountsHidden||p.pnl===undefined?'neutral':tone(p.pnl)}">${p.pnl===undefined?'':homePercent(p.pnl,p.basis??D(0))}</div><div class="valuation-bottom"><span>${icon('chart-no-axes-combined')}持仓市值</span><strong data-testid="market-value">${homeMoney(s.value)}</strong></div><div class="valuation-coverage">${esc(coverage)}${p.tradedToday?` · 今日 ${p.tradedToday} 笔交易已计入`:''}</div></section>`;
}
function holdings(s:ReturnType<typeof calculate>){
 const list=s.open.filter(p=>holdingFilter==='all'||holdingFilter==='gain'&&p.unrealized?.gt(0)||holdingFilter==='loss'&&p.unrealized?.lt(0)||holdingFilter==='missing'&&!p.quote).sort((a,b)=>holdingSort==='value'?(b.value??D(-1)).cmp(a.value??D(-1)):holdingSort==='profit'?(b.unrealized??D('-1e30')).cmp(a.unrealized??D('-1e30')):a.symbol.localeCompare(b.symbol));

 return `${!demo&&!blocked&&backupDue(appearance,!!data.trades.length)?'<button class="backup-reminder" id="backup-reminder">该备份账本了 <span>前往设置 ›</span></button>':''}${todayCard(s)}
 <section class="return-card"><button class="return-heading" data-tab="insights"><h2>持有收益</h2>${icon('chevron-right')}</button><div class="gain-line"><span>浮动收益（市值 − 持仓成本）</span><strong class="${amountsHidden?'neutral':tone(s.unrealized)}" data-testid="unrealized">${homeSigned(s.unrealized)}</strong></div><dl><div><dt>持仓成本</dt><dd data-testid="cost">${homeMoney(s.cost)}</dd></div><div><dt>已实现收益</dt><dd class="${amountsHidden?'neutral':tone(s.realized)}" data-testid="realized">${homeSigned(s.realized)}</dd></div><div><dt>累计投资收益</dt><dd class="${amountsHidden?'neutral':tone(s.totalProfit)}">${homeSigned(s.totalProfit)}</dd></div></dl></section>
 ${marketStatus()}
 ${s.missing.length?`<div class="notice">${icon('circle-help')}<span>${s.missing.length} 只持仓待报价</span><button class="text-button" data-quote="${esc(s.missing[0].symbol)}">去更新</button></div>`:''}
 <section class="holdings-section"><div class="holdings-heading"><h2>我的持仓</h2><label class="holding-sort"><span class="visually-hidden">持仓排序</span><select id="holding-sort" aria-label="持仓排序"><option value="symbol" ${holdingSort==='symbol'?'selected':''}>代码排序</option><option value="value" ${holdingSort==='value'?'selected':''}>市值优先</option><option value="profit" ${holdingSort==='profit'?'selected':''}>收益优先</option></select></label></div>
 <div class="holding-filters" aria-label="持仓筛选">${[['all',`全部 ${s.open.length}`],['gain','盈利'],['loss','亏损'],['missing','待报价']].map(([id,label])=>`<button data-holding-filter="${id}" class="${holdingFilter===id?'selected':''}" aria-pressed="${holdingFilter===id}">${label}</button>`).join('')}</div>
 ${!s.open.length?empty(data.trades.length?'当前没有持仓':'从第一笔投资开始',data.trades.length?'已平仓收益保留在收益页。':'记录第一笔买入，开始管理持仓。'):!list.length?empty('没有符合条件的持仓','试试其他筛选条件。',false):`<div class="compact-holdings">${list.map((p,i)=>{const meta=p.quote?quoteMeta(p.quote):undefined;return `<article class="holding-card compact-holding"><button class="holding-open" data-position="${esc(p.symbol)}" aria-label="查看 ${esc(p.symbol)} 持仓详情"><span class="ticker-icon color-${i%4}">${companyLogo(p.symbol)}</span><span class="holding-name"><strong>${esc(p.symbol)}</strong><small>${amountsHidden?'••••':quantity(p.quantity)} 股 · 市值 ${homeMoney(p.value)}</small></span><span class="holding-return ${amountsHidden?'neutral':tone(p.unrealized)}"><span class="quote-badge">${!p.quote?'待报价':isLive(p.quote)?'最新价':p.quote.source==='yahoo-close'?'收盘价':'手动'}</span><b>${homePercent(p.unrealized,p.cost)}</b><strong>${homeSigned(p.unrealized)}</strong></span>${icon('chevron-right')}</button><button class="quote-date" aria-label="更新 ${esc(p.symbol)} 股价" data-quote="${esc(p.symbol)}">${p.quote?`${esc(p.quote.date)}${meta?.time?` ${meta.time}`:''} · ${esc(meta!.label)}${esc(meta!.note)}`:'填写股价'}${icon('pencil')}</button></article>`;}).join('')}</div>`}</section>`;
}
function positionModal(symbol:string){
 const view=displayLedger(), p=calculate(view).open.find(p=>p.symbol===symbol);if(!p)return;
 const todayRow=todayPnl(view).rows.find(r=>r.symbol===symbol);
 const meta=p.quote?quoteMeta(p.quote):undefined;
 const related=orderedTrades(data.trades).filter(t=>t.symbol===symbol).reverse().slice(0,12);
 modal(`${esc(symbol)} 持仓详情`,`<div class="position-summary ${amountsHidden?'neutral':tone(p.unrealized)}">${homeSigned(p.unrealized)}<small>${homePercent(p.unrealized,p.cost)} · 持有收益</small></div>
 <div class="position-today ${amountsHidden?'neutral':todayRow&&todayRow.pnl===undefined?'':tone(todayRow?.pnl)}"><span>今日盈亏</span><strong>${todayRow?todayRow.pnl===undefined?'待补全':homeSigned(todayRow.pnl):'—'}</strong></div>
 <dl class="position-facts"><div><dt>持有股数</dt><dd>${amountsHidden?'••••':quantity(p.quantity)}</dd></div><div><dt>持仓市值</dt><dd>${homeMoney(p.value)}</dd></div><div><dt>平均成本</dt><dd>${homeMoney(p.average)}</dd></div><div><dt>持仓成本</dt><dd>${homeMoney(p.cost)}</dd></div><div><dt>参考股价</dt><dd>${p.quote?homeMoney(p.quote.price):'待报价'}</dd></div><div><dt>报价状态</dt><dd class="position-quote-state">${p.quote?`${esc(p.quote.date)}${meta?.time?` ${meta.time}`:''} · ${esc(meta!.label)}${esc(meta!.note)}`:'暂无报价，请先填写或更新'}</dd></div></dl>
 <div class="position-trades"><h3>相关交易 ${related.length?`<small>最近 ${related.length} 笔</small>`:''}</h3>${related.length?related.map(t=>`<div class="related-trade"><span>${esc(t.date)} · ${t.side==='buy'?'买入':'卖出'} ${amountsHidden?'••••':quantity(t.quantity)} 股</span><strong>${homeMoney(D(t.quantity).mul(t.price))}</strong></div>`).join(''):'<p class="small-empty">暂无该股票的交易记录。</p>'}</div>
 <div class="position-actions"><button class="secondary" id="position-quote">更新股价</button><button class="secondary" data-position-edit="${esc(p.quote?p.quote.symbol:symbol)}">${icon('plus')}记一笔</button></div>`);
 modalRoot.querySelector<HTMLButtonElement>('#position-quote')!.onclick=()=>quoteModal(symbol);
 modalRoot.querySelector<HTMLButtonElement>('[data-position-edit]')!.onclick=()=>{doClose();tradeModal(undefined,symbol);};
}
function trades(){const r=rangeStats(data,{from:tradeFrom,to:tradeTo,side:sideFilter as 'all'|'buy'|'sell',query:filter});const gains=calculate(displayLedger()).gains;const hasRange=!!(tradeFrom||tradeTo||sideFilter!=='all'||filter);return `<section class="panel"><div class="section-heading"><h2>全部交易 <span>${data.trades.length}</span></h2></div><div class="tools"><div class="segmented">${[['all','全部'],['buy','买入'],['sell','卖出']].map(([id,text])=>`<button data-side-filter="${id}" class="${id===sideFilter?'selected':''}">${text}</button>`).join('')}</div><label class="search">${icon('search')}<input id="search" value="${esc(filter)}" placeholder="搜索代码或备注" aria-label="搜索交易"></label></div><div class="trade-range"><label>从<input id="trade-from" type="date" min="1900-01-01" max="${today()}" value="${esc(tradeFrom)}" aria-label="起始日期"></label><label>至<input id="trade-to" type="date" min="1900-01-01" max="${today()}" value="${esc(tradeTo)}" aria-label="结束日期"></label>${hasRange?'<button class="text-button" id="clear-trade-filters">清除筛选</button>':''}</div>
 <div class="trade-summary" role="status">${tradeFrom&&tradeTo&&tradeFrom>tradeTo?`起始日期晚于结束日期，请调整。`:`范围内 ${r.count} 笔 · 买入 ${quantity(r.buyQty)} 股 · 卖出 ${quantity(r.sellQty)} 股 · 手续费 ${money(r.fees)} · 已实现收益 ${r.hasRealized?signedMoney(r.realized):'—'}`}</div>
 ${!data.trades.length?empty('还没有交易记录','添加买卖记录后，持仓和收益会自动更新。'):!r.list.length?empty('没有找到交易','试试其他股票代码、日期区间或筛选条件。',false):`<div class="trade-list">${r.list.map(t=>{const gross=D(t.quantity).mul(t.price),net=t.side==='buy'?gross.plus(t.fee):gross.minus(t.fee);return `<article class="trade-row"><div class="trade-top"><span class="trade-icon ${t.side}">${icon(t.side==='buy'?'arrow-down-left':'arrow-up-right')}</span><div class="trade-name"><h3>${esc(t.symbol)} <span class="badge ${t.side}">${t.side==='buy'?'买入':'卖出'}</span></h3><small>${t.date} · 顺序 ${t.sequence+1}</small></div><div class="trade-amount"><strong>${money(gross)}</strong><small>成交金额</small></div></div><div class="trade-detail"><span>${quantity(t.quantity)} 股 × ${money(t.price)}</span><span>手续费 ${money(t.fee)}</span></div><div class="trade-detail"><span>${t.side==='buy'?'实际支出':'实际收入'} ${money(net)}</span>${t.side==='sell'?`<span class="${tone(gains.get(t.id))}">已实现 ${signedMoney(gains.get(t.id))}</span>`:''}</div>${t.note?`<p class="trade-note">${esc(t.note)}</p>`:''}<div class="trade-actions"><button class="text-button" data-edit="${esc(t.id)}">${icon('pencil')}编辑</button><button class="text-button delete" data-delete="${esc(t.id)}">${icon('trash-2')}删除</button></div></article>`;}).join('')}</div>`}</section>`;}
function insights(s:ReturnType<typeof calculate>){return `${marketStatus()}${historyPanel(data,historyMonth)}<section class="panel profit-summary"><div class="eyebrow">INVESTMENT RETURN</div><h2>累计投资收益</h2><div class="summary-number ${tone(s.totalProfit)}">${signedMoney(s.totalProfit)}</div><p>已实现收益 + 当前持仓浮动收益</p><div class="summary-split"><div><span>已实现收益</span><strong class="${tone(s.realized)}">${signedMoney(s.realized)}</strong></div><div><span>浮动收益</span><strong class="${tone(s.unrealized)}">${signedMoney(s.unrealized)}</strong></div></div>${s.missing.length?'<p class="notice-inline">部分股票缺少股价，累计收益暂未计算。</p>':''}</section><div class="two-columns"><section class="panel"><div class="section-heading"><h2>持仓成本分布</h2><span class="caption">按成本占比</span></div>${!s.open.length?'<p class="small-empty">暂无持仓</p>':s.open.map((p,i)=>{const pc=p.cost.div(s.cost).mul(100).toFixed(1);return `<div class="allocation"><div><b>${esc(p.symbol)}</b><span>${pc}% <small>${money(p.cost)}</small></span></div><div class="bar"><div class="color-${i%4}" style="width:${pc}%"></div></div></div>`;}).join('')}</section><section class="panel"><div class="section-heading"><h2>资金记录</h2></div><dl class="totals"><div><dt>累计买入支出</dt><dd>${money(s.buyTotal)}</dd></div><div><dt>累计卖出收入</dt><dd>${money(s.sellTotal)}</dd></div><div><dt>累计手续费</dt><dd>${money(s.fees)}</dd></div><div><dt>交易笔数</dt><dd>${data.trades.length} 笔</dd></div></dl></section></div><section class="panel"><div class="section-heading"><h2>各股票已实现收益</h2></div>${!s.positions.length?'<p class="small-empty">卖出后可在这里查看收益</p>':s.positions.map(p=>`<div class="realized-row"><b>${esc(p.symbol)} <small>${p.quantity.eq(0)?'已平仓':'持仓中'}</small></b><strong class="${tone(p.realized)}">${signedMoney(p.realized)}</strong></div>`).join('')}</section>`;}
function settings(){return `<section class="panel settings-panel"><div class="section-heading"><h2>持仓账本 <span>1.25</span></h2></div><button class="setting-row" data-help="home"><span class="setting-icon">${icon('circle-help')}</span><span><b>帮助文档</b><small>使用指南、计算规则与常见问题</small></span>${icon('chevron-right')}</button></section><section class="panel settings-panel"><div class="section-heading"><h2>显示与提醒</h2></div><label class="preference-row">外观<select data-preference="theme" aria-label="外观"><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></label><label class="preference-row">涨跌颜色<select data-preference="colors" aria-label="涨跌颜色"><option value="green-up">绿涨红跌</option><option value="red-up">红涨绿跌</option></select></label><div class="color-preview"><span class="positive">+$12.34 / +1.23%</span><span class="negative">−$12.34 / −1.23%</span></div><label class="preference-row">备份提醒<select data-preference="reminderDays" aria-label="备份提醒"><option value="7">每 7 天</option><option value="30">每 30 天</option><option value="0">关闭</option></select></label><p class="form-hint">应用内提醒 · ${appearance.lastExport?'上次导出 '+new Date(appearance.lastExport).toLocaleDateString('zh-CN'):'尚未导出备份'}</p></section><section class="panel settings-panel"><div class="section-heading"><h2>备份与恢复</h2><span class="backup-count"><span>${data.trades.length} 笔交易</span></span></div><button class="setting-row" id="export" ${blocked||demo?'disabled':''}><span class="setting-icon">${icon('download')}</span><span><b>导出完整备份</b></span>${icon('chevron-right')}</button><button class="setting-row" id="export-compatible" ${blocked||demo?'disabled':''}><span class="setting-icon">${icon('file-json')}</span><span><b>导出各版本通用备份</b></span>${icon('chevron-right')}</button><button class="setting-row" id="recovery" ${blocked||demo?'disabled':''}><span class="setting-icon">${icon('shield-check')}</span><span><b>本机恢复记录</b></span>${icon('chevron-right')}</button><label class="setting-row ${demo?'disabled':''}" for="import"><span class="setting-icon">${icon('upload')}</span><span><b>从备份恢复</b></span>${icon('chevron-right')}<input id="import" type="file" accept=".json,.js,application/json,text/javascript" ${demo?'disabled':''} class="visually-hidden"></label></section>${demo?'':`<button class="secondary full" data-action="demo">${icon('eye')}查看示例账本</button>`}`;}
let previousFocus:HTMLElement|null=null;
let discardFocus:HTMLElement|null=null;
function isLive(q:Quote){return !demo&&live.get(q.symbol)?.quote===q;}
async function syncLivePrices(manual=false){
 if(api.provider==='yahoo'||liveSyncing||demo||blocked||busy||modalRoot.children.length||(!manual&&Date.now()-lastLiveAttempt<(api.interval||60)*1000))return;
 const snapshot=data, config=api, symbols=calculate(data).open.map(p=>p.symbol);if(!symbols.length)return;
 liveSyncing=true;lastLiveAttempt=Date.now();liveStatus='正在读取最新报价…';render();
 const results=new Map<string,LiveQuote>(),errors:string[]=[];let next=0;
 try {
  await Promise.all([0,1].map(async()=>{while(next<symbols.length){const symbol=symbols[next++];try{results.set(symbol,await fetchLive(symbol,config));}catch(e){errors.push(`${symbol}：${e instanceof Error?e.message:'请求失败'}`);}}}));
  if(data!==snapshot||api!==config||demo||busy||modalRoot.children.length){lastLiveAttempt=0;return;}
  for(const [symbol,q] of results){if(!live.has(symbol)||live.get(symbol)!.timestamp<=q.timestamp)live.set(symbol,q);}
  liveFailures=errors.length;
  liveStatus=`${new Date().toLocaleTimeString('zh-CN')} 检查：${results.size} 只返回报价。${errors.length?errors.join('；')+'；保留上次报价。':'报价时间见各股票；同日手动报价优先。'}`;
 }finally{liveSyncing=false;if(!modalRoot.children.length)render();}
}
function apiModal(){
 modal('行情来源',`<form id="api-form"><label class="note-field">数据源<select name="provider"><option value="yahoo">Yahoo Finance · 收盘价（默认）</option><option value="finnhub">Finnhub · 最新报价</option><option value="custom">自定义 API · 最新报价</option></select></label><label class="note-field" id="api-url-field">HTTPS 接口地址<input name="url" type="text" autocapitalize="off" spellcheck="false" placeholder="https://example.com/quote?symbol={symbol}" value="${esc(api.url)}"></label><label class="note-field" id="api-key-field">API Key<input name="key" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" value="${esc(api.key)}" placeholder="填写自己的行情服务密钥"></label><label class="note-field">前台自动刷新<select name="interval"><option value="60">每 60 秒</option><option value="300">每 5 分钟</option><option value="0">关闭，仅打开时及手动刷新</option></select></label><p class="form-hint">最新价用于估值；日历使用收盘价。<button type="button" class="text-button" data-help="api">配置帮助</button></p><p id="api-status" role="status" class="form-hint"></p><p id="form-error" class="form-error" role="alert"></p><div class="api-actions"><button type="button" class="secondary" id="test-api">测试连接（AAPL）</button><button type="submit" class="primary">保存设置</button></div></form>`);
 const f=modalRoot.querySelector<HTMLFormElement>('#api-form')!,provider=f.elements.namedItem('provider') as HTMLSelectElement,interval=f.elements.namedItem('interval') as HTMLSelectElement;
 provider.value=api.provider;interval.value=String(api.interval);
 const update=()=>{f.querySelector<HTMLElement>('#api-url-field')!.hidden=provider.value!=='custom';f.querySelector<HTMLElement>('#api-key-field')!.hidden=provider.value==='yahoo';interval.disabled=provider.value==='yahoo';};provider.onchange=()=>{(f.elements.namedItem('key') as HTMLInputElement).value='';update();};update();
 const read=()=>validateApi({provider:provider.value as ApiSettings['provider'],url:(f.elements.namedItem('url') as HTMLInputElement).value,key:(f.elements.namedItem('key') as HTMLInputElement).value,interval:Number(interval.value)});
 const error=f.querySelector<HTMLElement>('#form-error')!,status=f.querySelector<HTMLElement>('#api-status')!,test=f.querySelector<HTMLButtonElement>('#test-api')!;
 let testing=false;
 test.onclick=async()=>{if(testing)return;testing=true;test.disabled=true;error.textContent='';status.textContent='正在测试…';try{const config=read();if(config.provider==='yahoo'){const q=await fetchClose('AAPL');status.textContent=`连接成功：AAPL ${money(q.price)} · 收盘日 ${q.date}`;}else{const q=await fetchLive('AAPL',config);status.textContent=`连接成功：AAPL ${money(q.quote.price)} · 报价时间 ${new Date(q.timestamp).toLocaleString('zh-CN')}`;}}catch(e){status.textContent='';error.textContent=e instanceof Error?e.message:'测试失败';}finally{testing=false;test.disabled=false;}};
 f.onsubmit=async e=>{e.preventDefault();if(busy)return;busy=true;try{const next=read();await saveApi(next);api=next;live.clear();lastLiveAttempt=0;liveStatus='';liveFailures=0;busy=false;closeModal();render();toast('行情设置已保存');void syncLivePrices(true);}catch(e){error.textContent=e instanceof Error?e.message:'设置保存失败';}finally{busy=false;}};
}
function modal(title:string,body:string){previousFocus=document.activeElement as HTMLElement;modalGuard=undefined;modalRoot.innerHTML=`<div class="modal-backdrop"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="dialog-title" tabindex="-1"><div class="modal-head"><h2 id="dialog-title">${title}</h2><button class="icon-button" id="close-modal" aria-label="关闭">${icon('x')}</button></div>${body}</section></div>`;document.body.classList.add('modal-open');modalRoot.querySelector<HTMLButtonElement>('#close-modal')!.onclick=closeModal;const backdrop=modalRoot.querySelector<HTMLElement>('.modal-backdrop')!;backdrop.addEventListener('click',e=>{if(e.target===backdrop)closeModal();});modalRoot.querySelector<HTMLElement>('.modal')!.focus();refreshIcons();}
function doClose(){discardFocus=null;modalGuard=undefined;modalRoot.innerHTML='';document.body.classList.remove('modal-open');previousFocus?.focus();}
function removeDiscard(){
 modalRoot.querySelector('.discard-layer')?.remove();
 const underlying=modalRoot.querySelector<HTMLElement>('.modal-backdrop');
 if(underlying){underlying.inert=false;underlying.removeAttribute('aria-hidden');}
 if(discardFocus?.isConnected)discardFocus.focus();else modalRoot.querySelector<HTMLElement>('.modal')?.focus();
 discardFocus=null;
}
function showDiscard(){if(modalRoot.querySelector('.discard-layer'))return;discardFocus=document.activeElement as HTMLElement;modalRoot.insertAdjacentHTML('beforeend',`<div class="modal-backdrop discard-layer" role="alertdialog" aria-modal="true" aria-labelledby="discard-title"><section class="modal"><div class="modal-head"><h2 id="discard-title">放弃未保存的修改？</h2><button class="icon-button" id="discard-cancel" aria-label="关闭提醒">${icon('x')}</button></div><p class="dialog-copy">刚才填写的内容尚未保存，放弃后需要重新输入。</p><button class="primary full" id="discard-yes">放弃修改</button><button class="secondary full" id="discard-no">继续编辑</button></section></div>`);modalRoot.querySelector<HTMLButtonElement>('#discard-yes')!.onclick=doClose;modalRoot.querySelector<HTMLButtonElement>('#discard-no')!.onclick=removeDiscard;modalRoot.querySelector<HTMLButtonElement>('#discard-cancel')!.onclick=removeDiscard;refreshIcons();modalRoot.querySelector<HTMLElement>('#discard-no')!.focus();const underlying=modalRoot.querySelector<HTMLElement>('.modal-backdrop:not(.discard-layer)');if(underlying){underlying.inert=true;underlying.setAttribute('aria-hidden','true');}}
function closeModal(){if(busy)return;if(modalGuard?.()){showDiscard();return;}doClose();}
document.addEventListener('keydown',e=>{
 if(!modalRoot.children.length)return;
 if(e.key==='Escape'){e.preventDefault();if(modalRoot.querySelector('.discard-layer'))removeDiscard();else closeModal();return;}
 if(e.key!=='Tab')return;
 const scope=modalRoot.querySelector<HTMLElement>('.discard-layer')??modalRoot.querySelector<HTMLElement>('.modal')!;
 const items=[...scope.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select:not(:disabled),[tabindex="0"]')].filter(el=>el.getClientRects().length>0);
 const first=items[0],last=items[items.length-1];
 if(e.shiftKey&&(document.activeElement===first||document.activeElement===scope||!scope.contains(document.activeElement))){e.preventDefault();last?.focus();}
 else if(!e.shiftKey&&(document.activeElement===last||!scope.contains(document.activeElement))){e.preventDefault();first?.focus();}
});
async function commit(next:Ledger,reason?:string){if(undoTrade&&!next.trades.some(t=>t.id===undoTrade))undoTrade=undefined;if(demo){data=next;return;}await store.save(next,reason);if(reason)live.clear();data=next;realData=next;}
async function submit(work:()=>Promise<void>){if(busy)return;busy=true;modalRoot.querySelectorAll<HTMLButtonElement>('button').forEach(b=>b.disabled=true);const error=modalRoot.querySelector<HTMLElement>('#form-error');if(error)error.textContent='';try{await work();busy=false;doClose();render();toast(demo?'示例账本已更新，真实数据未改变':'已保存到本机');}catch(e){if(error)error.textContent=e instanceof Error?e.message:'保存失败，请重试。';else toast(String(e));}finally{busy=false;modalRoot.querySelectorAll<HTMLButtonElement>('button').forEach(b=>b.disabled=false);}}
function tradeModal(t?:Trade,prefillSymbol=''){if(blocked)return;const sequence=t?.sequence??(Math.max(-1,...data.trades.map(x=>x.sequence))+1);modal(t?'编辑交易':'记录交易',`<form id="trade-form"><div class="form-tabs"><label><input name="side" type="radio" value="buy" ${!t||t.side==='buy'?'checked':''}><span>买入</span></label><label><input name="side" type="radio" value="sell" ${t?.side==='sell'?'checked':''}><span>卖出</span></label></div><div class="form-grid"><label>股票代码<input name="symbol" list="recent-symbols" placeholder="例如 AAPL" maxlength="15" autocapitalize="characters" autocomplete="off" autofocus required value="${esc(t?.symbol??prefillSymbol)}"></label><datalist id="recent-symbols">${[...new Set(orderedTrades(data.trades).reverse().map(x=>x.symbol))].slice(0,20).map(symbol=>`<option value="${esc(symbol)}"></option>`).join('')}</datalist><label>交易日期（美东）<input name="date" type="date" min="1900-01-01" max="${t?.date&&t.date>marketDate(Date.now())?t.date:marketDate(Date.now())}" required value="${t?.date??marketDate(Date.now())}"></label><label>成交股数<input name="quantity" inputmode="decimal" placeholder="支持小数股" required value="${t?.quantity??''}"></label><label>成交单价（美元）<input name="price" inputmode="decimal" placeholder="0.00" required value="${t?.price??''}"></label><label class="full-field">手续费（美元）<input name="fee" inputmode="decimal" required value="${t?.fee??orderedTrades(data.trades).at(-1)?.fee??'0'}"></label></div><div id="sell-shortcuts" class="sell-shortcuts" hidden><span id="available-shares"></span><button type="button" class="secondary" data-fill="half">一半</button><button type="button" class="secondary" data-fill="all">全部</button></div><div class="calculation-preview"><div><span>成交金额</span><strong id="gross">—</strong></div><div><span id="net-label">实际支出</span><strong id="net">—</strong></div></div><label class="note-field">备注 <span>选填</span><textarea name="note" maxlength="500" rows="2" placeholder="记录这次交易的想法…">${esc(t?.note??'')}</textarea></label><p class="form-hint">日期按美东成交日；同日交易按录入顺序计算。</p><p id="form-error" class="form-error" role="alert"></p><div class="form-actions"><button class="primary full" type="submit">${icon('check')}${t?'保存修改':'保存交易'}</button></div></form>`);
 const form=modalRoot.querySelector<HTMLFormElement>('#trade-form')!;
 let dirty=false;const mark=()=>{dirty=true;};
 form.addEventListener('input',mark);form.addEventListener('change',mark);
 modalGuard=()=>dirty;
 const update=()=>{const f=new FormData(form);const shortcuts=form.querySelector<HTMLElement>('#sell-shortcuts')!;const symbol=String(f.get('symbol')).trim().toUpperCase();const available=calculate(data).open.find(p=>p.symbol===symbol)?.quantity??D(0);shortcuts.hidden=!!t||f.get('side')!=='sell'||String(f.get('date'))!==marketDate(Date.now());form.querySelector('#available-shares')!.textContent='当前可卖 '+quantity(available)+' 股';try{const gross=D(String(f.get('quantity'))).mul(String(f.get('price'))), fee=D(String(f.get('fee')));modalRoot.querySelector('#gross')!.textContent=money(gross);modalRoot.querySelector('#net')!.textContent=money(f.get('side')==='buy'?gross.plus(fee):gross.minus(fee));}catch{modalRoot.querySelector('#gross')!.textContent='—';modalRoot.querySelector('#net')!.textContent='—';}modalRoot.querySelector('#net-label')!.textContent=f.get('side')==='buy'?'实际支出（含费）':'实际收入（扣费后）';};
 form.oninput=update;form.querySelectorAll<HTMLButtonElement>('[data-fill]').forEach(b=>b.onclick=()=>{dirty=true;const symbol=(form.elements.namedItem('symbol') as HTMLInputElement).value.trim().toUpperCase();const available=calculate(data).open.find(p=>p.symbol===symbol)?.quantity??D(0);(form.elements.namedItem('quantity') as HTMLInputElement).value=(b.dataset.fill==='half'?available.div(2).toDecimalPlaces(8,1):available).toFixed();update();});update();form.onsubmit=e=>{e.preventDefault();void submit(async()=>{const f=new FormData(form),get=(k:string)=>String(f.get(k)??'').trim();const id=t?.id??crypto.randomUUID();const next=saveTrade(data,{id,sequence,symbol:get('symbol').toUpperCase(),side:get('side') as 'buy'|'sell',date:get('date'),quantity:get('quantity'),price:get('price'),fee:get('fee'),note:get('note')});await commit(next,t?'编辑交易前':undefined);if(!t)undoTrade=id;});};
 (form.elements.namedItem('symbol') as HTMLInputElement).focus();
}
function quoteModal(symbol:string){if(blocked)return;const q=data.quotes.find(q=>q.symbol===symbol);modal(`更新 ${esc(symbol)} 股价`,`<form id="quote-form"><p class="form-hint">同日手动报价优先；已取得的自动报价仍会保留。</p><label class="note-field">股价（美元）<input name="price" inputmode="decimal" autofocus required value="${q?.price??''}" placeholder="0.00"></label><label class="note-field">报价日期（美东）<input type="date" name="date" min="1900-01-01" max="${marketDate(Date.now())}" required value="${marketDate(Date.now())}"></label><p id="form-error" class="form-error" role="alert"></p><div class="form-actions"><button type="submit" class="primary full">保存股价</button></div></form>`);const f=modalRoot.querySelector<HTMLFormElement>('#quote-form')!;let dirty=false;const mark=()=>{dirty=true;};f.addEventListener('input',mark);f.addEventListener('change',mark);modalGuard=()=>dirty;f.onsubmit=e=>{e.preventDefault();void submit(async()=>{const fd=new FormData(f);const quote:Quote={symbol,price:String(fd.get('price')).trim(),date:String(fd.get('date'))};await commit(validateLedger({...data,quotes:[...data.quotes.filter(x=>x.symbol!==symbol),quote]}),'修改报价前');});};(f.elements.namedItem('price') as HTMLInputElement).focus();}
function deleteModal(t:Trade){modal('删除这笔交易？',`<p class="dialog-copy">${t.date} · ${esc(t.symbol)} · ${t.side==='buy'?'买入':'卖出'} ${quantity(t.quantity)} 股<br>删除后将重新计算全部持仓和收益。如果导致历史持仓不足，将无法删除。</p><p id="form-error" class="form-error" role="alert"></p><button class="danger full" id="confirm-delete">确认删除</button>`);modalRoot.querySelector<HTMLButtonElement>('#confirm-delete')!.onclick=()=>void submit(async()=>{await commit(deleteTrade(data,t.id),'删除交易前');});}
async function exportBackup(compatible=false){if(demo||blocked)return;const b=app.querySelector<HTMLButtonElement>('#export')!;b.disabled=true;try{const text=backupText(data,compatible),filename=`stock-ledger-${compatible?'compatible-':''}${today()}-${Date.now()}.json`;if(Capacitor.isNativePlatform()){const result=await Filesystem.writeFile({path:filename,data:text,directory:Directory.Cache,encoding:Encoding.UTF8});await Share.share({title:'持仓账本备份',files:[result.uri],dialogTitle:'保存账本备份'});}else{const url=URL.createObjectURL(new Blob([text],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}const next={...appearance,lastExport:Date.now()};await saveAppearance(next);appearance=next;render();toast('备份已导出，请确认已保存到文件或其他安全位置');}catch(e){toast(`未完成导出：${e instanceof Error?e.message:String(e)}`);}finally{b.disabled=false;}}
async function importFile(file?:File){if(!file||busy)return;try{if(file.size>8_000_000)throw Error('文件过大，请选择 8 MB 以内的 JSON 备份。');const next=parseBackup(await file.text());const s=calculate(next);modal('恢复这份备份？',`<div class="import-preview">${icon('file-json')}<b>${esc(file.name)}</b><p>${next.trades.length} 笔交易 · ${s.open.length} 只持仓 · ${next.quotes.length} 条报价</p><strong>持仓成本 ${money(s.cost)}</strong></div><p class="dialog-copy">确认后，此备份将替换当前的 ${data.trades.length} 笔交易。建议先导出当前账本。恢复前会自动保存当前账本到本机恢复记录。</p><p id="form-error" class="form-error" role="alert"></p><button class="primary full" id="confirm-import">确认替换并恢复</button>`);modalRoot.querySelector<HTMLButtonElement>('#confirm-import')!.onclick=()=>void submit(async()=>{if(blocked){await store.recover(next);blocked=false;data=next;realData=next;}else await commit(next,'导入备份前');});}catch(e){modal('无法导入备份',`<p class="form-error">${esc(e instanceof Error?e.message:String(e))}</p><p class="dialog-copy">当前账本未改变。</p>`);}finally{const i=app.querySelector<HTMLInputElement>('#import');if(i)i.value='';}}
async function start(){try{appearance=await loadAppearance();applyAppearance(appearance);}catch{toast('显示设置无法读取，已使用默认外观');}try{api=await loadApi();}catch{toast('行情设置无法读取，请在设置中重新保存；账本不受影响。');}try{const loaded=await store.load();data=loaded.data;realData=data;if(loaded.recovered)toast('已从上一份本机副本恢复，请核对最近交易并导出备份。');}catch(e){blocked=true;tab='settings';toast(e instanceof Error?e.message:'存储打开失败');}render();void syncPrices();void syncLivePrices();
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'){void syncPrices();void syncLivePrices();}});
 if(Capacitor.isNativePlatform()) await App.addListener('appStateChange',({isActive})=>{if(isActive){void syncPrices();void syncLivePrices();}});
 setInterval(()=>{if(document.visibilityState==='visible'&&api.interval)void syncLivePrices();},5000);
}void start();

async function showRecovery(){
 if(demo||busy||blocked)return;
 try{const rows=await store.listRecovery();modal('本机恢复记录',`<p class="dialog-copy">恢复前会保存当前账本。卸载应用会同时删除这些记录，请定期导出完整备份。</p>${rows.map((r,i)=>`<button class="setting-row" data-restore="${i}"><span><b>${esc(r.reason)}</b><small>${esc(new Date(r.createdAt).toLocaleString('zh-CN'))} · ${r.data.trades.length} 笔交易</small></span></button>`).join('')||'<p class="small-empty">暂无恢复记录。修改、删除交易或导入前会自动建立。</p>'}`);
 modalRoot.querySelectorAll<HTMLButtonElement>('[data-restore]').forEach(b=>b.onclick=()=>{const r=rows[Number(b.dataset.restore)];modal('恢复这份本机记录？',`<p class="dialog-copy">${esc(r.reason)} · ${r.data.trades.length} 笔交易<br>将替换当前账本，并重新计算持仓与收益。</p><p id="form-error" class="form-error" role="alert"></p><button class="primary full" id="confirm-restore">确认恢复</button>`);modalRoot.querySelector<HTMLButtonElement>('#confirm-restore')!.onclick=()=>void submit(async()=>{await commit(r.data,'恢复本机记录前');});});
 }catch(e){toast(e instanceof Error?e.message:'无法读取恢复记录');}
}

document.addEventListener('click',e=>{const b=(e.target as Element).closest<HTMLElement>('[data-help]');if(!b||busy)return;closeModal();tab='help';render();window.scrollTo(0,0);const target=document.getElementById('help-'+b.dataset.help);if(target instanceof HTMLDetailsElement){target.open=true;target.scrollIntoView({block:'start'});}});
