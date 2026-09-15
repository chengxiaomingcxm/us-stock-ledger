import { describe,it,expect } from 'vitest';
import { D,emptyLedger,calculate,validateLedger,saveTrade,deleteTrade,backupText,parseBackup,type Trade } from '../src/ledger';
import { LedgerStore, type KV } from '../src/storage';
const trade=(values:Partial<Trade>={}):Trade=>({id:'buy1',sequence:0,symbol:'AAPL',side:'buy',date:'2025-01-01',quantity:'10',price:'100',fee:'1',note:'',...values});
describe('交易成本和收益',()=>{
 it('包含买卖手续费，并保留部分卖出的剩余成本',()=>{let d=saveTrade(emptyLedger(),trade());d=saveTrade(d,trade({id:'sell1',sequence:1,side:'sell',quantity:'4',price:'120',fee:'2'}));const s=calculate(d);expect(s.cost.toString()).toBe('600.6');expect(s.realized.toString()).toBe('77.6');expect(s.open[0].quantity.toString()).toBe('6');expect(s.open[0].average.toString()).toBe('100.1');});
 it('多次买入使用移动平均成本，清仓无残余',()=>{const d=validateLedger({...emptyLedger(),trades:[trade({quantity:'3',fee:'0'}),trade({id:'b2',sequence:1,quantity:'2',price:'150',fee:'0'}),trade({id:'s1',sequence:2,side:'sell',quantity:'2',price:'160',fee:'1'}),trade({id:'s2',sequence:3,side:'sell',quantity:'3',price:'140',fee:'1'})]});const s=calculate(d);expect(s.cost.toString()).toBe('0');expect(s.open.length).toBe(0);expect(s.realized.toString()).toBe('138');});
 it('支持碎股，0.1 + 0.2 精确清仓',()=>{let d=saveTrade(emptyLedger(),trade({quantity:'0.1',price:'0.1',fee:'0'}));d=saveTrade(d,trade({id:'b2',sequence:1,quantity:'0.2',price:'0.1',fee:'0'}));d=saveTrade(d,trade({id:'s',sequence:2,side:'sell',quantity:'0.3',price:'0.2',fee:'0'}));expect(calculate(d).realized.eq('0.03')).toBe(true);expect(calculate(d).cost.eq(0)).toBe(true);});
 it('修改旧买入后重算收益',()=>{let d=saveTrade(emptyLedger(),trade());d=saveTrade(d,trade({id:'s',sequence:1,side:'sell',quantity:'4',price:'120',fee:'2'}));d=saveTrade(d,trade({price:'90'}));expect(calculate(d).realized.toString()).toBe('117.6');expect(calculate(d).cost.toString()).toBe('540.6');});
 it('拒绝删除会造成历史超卖的买入，原账本保持不变',()=>{let d=saveTrade(emptyLedger(),trade());d=saveTrade(d,trade({id:'s',sequence:1,side:'sell',quantity:'4'}));expect(()=>deleteTrade(d,'buy1')).toThrow('超过当时持仓');expect(d.trades).toHaveLength(2);});
 it('历史卖出不能靠未来买入填补',()=>{expect(()=>validateLedger({...emptyLedger(),trades:[trade({date:'2025-02-01'}),trade({id:'s',sequence:1,side:'sell',date:'2025-01-01',quantity:'1'})]})).toThrow('超过当时持仓');});
 it('同日顺序稳定，不受备份数组顺序影响',()=>{const d=validateLedger({...emptyLedger(),trades:[trade({id:'s',sequence:1,side:'sell',quantity:'1'}),trade()]});expect(calculate(d).open[0].quantity.toString()).toBe('9');});
 it('缺少报价时不生成虚假的浮亏，填入报价后正确计算',()=>{let d=saveTrade(emptyLedger(),trade());expect(calculate(d).unrealized).toBeUndefined();d.quotes=[{symbol:'AAPL',price:'120',date:'2025-01-02'}];const s=calculate(d);expect(s.value?.toString()).toBe('1200');expect(s.unrealized?.toString()).toBe('199');});
 it('支持零价格和负净卖出收入（手续费大于成交额）',()=>{let d=saveTrade(emptyLedger(),trade({quantity:'1',price:'1',fee:'0'}));d.quotes=[{symbol:'AAPL',price:'0',date:'2025-01-01'}];expect(calculate(d).unrealized?.eq(-1)).toBe(true);d=saveTrade(d,trade({id:'s',sequence:1,side:'sell',quantity:'1',price:'1',fee:'2'}));expect(calculate(d).realized.eq(-2)).toBe(true);});
 it('拆分卖出和一次卖出具有相同收益',()=>{let a=saveTrade(emptyLedger(),trade({quantity:'3',price:'0.33333333',fee:'0.01'}));let b=a;for(let i=0;i<3;i++)a=saveTrade(a,trade({id:`s${i}`,sequence:i+1,side:'sell',quantity:'1',price:'1',fee:'0'}));b=saveTrade(b,trade({id:'all',sequence:1,side:'sell',quantity:'3',price:'1',fee:'0'}));expect(calculate(a).realized.minus(calculate(b).realized).abs().lt('1e-30')).toBe(true);expect(calculate(a).cost.eq(0)).toBe(true);});
});
describe('数据校验与备份',()=>{
 it('备份往返保留全部信息',()=>{const d=saveTrade(emptyLedger(),trade({note:'长期持有\n中文备注'}));expect(parseBackup(backupText(d))).toEqual(d);});
 it.each(['-1','NaN','Infinity','1e8','0.000000001','1,000',''])('拒绝无效股数 %s',v=>expect(()=>saveTrade(emptyLedger(),trade({quantity:v}))).toThrow());
 it.each(['2025-02-30','9999-01-01','2025-13-01'])('拒绝无效日期 %s',date=>expect(()=>saveTrade(emptyLedger(),trade({date}))).toThrow());
 it('拒绝重复 ID / 顺序以及损坏格式',()=>{expect(()=>validateLedger({...emptyLedger(),trades:[trade(),trade()]})).toThrow();expect(()=>parseBackup('{}')).toThrow();expect(()=>parseBackup('{bad')).toThrow();});
 it('拒绝错误币种和计算方法',()=>{expect(()=>validateLedger({...emptyLedger(),currency:'CNY'})).toThrow();expect(()=>validateLedger({...emptyLedger(),method:'fifo'})).toThrow();});
});
describe('保存、失败与恢复',()=>{
 const memory=()=>{const map=new Map<string,string>();const kv:KV={get:async k=>map.get(k)??null,set:async(k,v)=>{map.set(k,v);}};return {map,kv};};
 it('重启后读取最新保存的账本',async()=>{const {kv}=memory();const s=new LedgerStore(kv);await s.load();const d=saveTrade(emptyLedger(),trade());await s.save(d);const another=new LedgerStore(kv);expect((await another.load()).data).toEqual(d);});
 it('最新副本损坏时回退到完整旧副本',async()=>{const {kv,map}=memory();const s=new LedgerStore(kv);await s.load();const d=saveTrade(emptyLedger(),trade());await s.save(d);await s.save(saveTrade(d,trade({price:'200'})));map.set('stock-ledger-v1-1','{partial');const loaded=await new LedgerStore(kv).load();expect(loaded.data).toEqual(d);expect(loaded.recovered).toBe(true);});
 it('全部副本损坏时不静默创建空账本',async()=>{const {kv,map}=memory();map.set('stock-ledger-v1-0','bad');const s=new LedgerStore(kv);await expect(s.load()).rejects.toThrow('本机账本无法读取');await expect(s.save(emptyLedger())).rejects.toThrow();expect(map.get('stock-ledger-v1-0')).toBe('bad');});
 it('写入失败不会破坏先前保存的数据',async()=>{const {kv}=memory();const s=new LedgerStore(kv);await s.load();const d=saveTrade(emptyLedger(),trade());await s.save(d);kv.set=async()=>{throw Error('disk full');};await expect(s.save(emptyLedger())).rejects.toThrow('disk full');expect((await new LedgerStore(kv).load()).data).toEqual(d);});
});
