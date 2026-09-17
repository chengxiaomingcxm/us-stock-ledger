import {it,expect} from 'vitest';
import {emptyLedger,validateLedger,type Trade} from '../src/ledger';
import {rangeStats} from '../src/trade-range';

const trade=(v:Partial<Trade>={}):Trade=>({id:'b1',sequence:0,symbol:'AAPL',date:'2026-09-01',side:'buy',quantity:'10',price:'100',fee:'1',note:'',...v});
const ledger=validateLedger({...emptyLedger(),trades:[
 trade(),
 {...trade({id:'b2',sequence:1,symbol:'MSFT',date:'2026-09-02',quantity:'5',price:'200',fee:'2'})},
 {...trade({id:'s1',sequence:2,symbol:'AAPL',date:'2026-09-03',side:'sell',quantity:'4',price:'120',fee:'1'})},
 {...trade({id:'s2',sequence:3,symbol:'AAPL',date:'2026-09-04',side:'sell',quantity:'6',price:'130',fee:'2'})},
]});

it('不筛选时汇总全部手续费与已实现收益',()=>{
 const r=rangeStats(ledger);
 expect(r.count).toBe(4);expect(r.fees.toString()).toBe('6');
 // s1: 480−1−400.4=78.6；s2: 780−2−600.6=177.4；合计 256
 expect(r.realized.toString()).toBe('256');expect(r.buyQty.toString()).toBe('15');expect(r.sellQty.toString()).toBe('10');
});
it('按日期区间、买卖类型和关键字组合筛选',()=>{
 expect(rangeStats(ledger,{from:'2026-09-03'}).count).toBe(2);
 expect(rangeStats(ledger,{to:'2026-09-01'}).count).toBe(1);
 expect(rangeStats(ledger,{from:'2026-09-01',to:'2026-09-03'}).count).toBe(3);
 expect(rangeStats(ledger,{side:'buy'}).count).toBe(2);
 expect(rangeStats(ledger,{side:'buy'}).fees.toString()).toBe('3');
 expect(rangeStats(ledger,{query:'msft'}).count).toBe(1);
 expect(rangeStats(ledger,{query:'MSFT',side:'sell'}).count).toBe(0);
 expect(rangeStats(ledger,{from:'2026-09-03',to:'2026-09-04',side:'sell'}).realized.toString()).toBe('256');
});
it('区间内只有买入时已实现收益为零',()=>{
 const r=rangeStats(ledger,{to:'2026-09-02'});
 expect(r.realized.toString()).toBe('0');expect(r.sellQty.toString()).toBe('0');expect(r.list).toHaveLength(2);
});
it('列表按日期倒序，适合展示',()=>{
 const r=rangeStats(ledger);
 expect(r.list.map(t=>t.date)).toEqual(['2026-09-04','2026-09-03','2026-09-02','2026-09-01']);
});
