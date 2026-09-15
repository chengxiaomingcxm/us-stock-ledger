import { Preferences } from '@capacitor/preferences';
import { emptyLedger, parseBackup, validateLedger, type Ledger } from './ledger';
export interface KV { get(key:string):Promise<string|null>; set(key:string,value:string):Promise<void> }
export interface Recovery {id:string;createdAt:string;reason:string;data:Ledger}
const recoveryKey='stock-ledger-recovery-v1';
export class LedgerStore {
  constructor(private kv:KV) {}
  private revision=0; private slot=-1; private ready=false;
  private current:Ledger|undefined; private writing=false;
  async listRecovery():Promise<Recovery[]> {
    const raw=await this.kv.get(recoveryKey);if(raw===null)return [];
    try {const rows=JSON.parse(raw);if(!Array.isArray(rows)||rows.length>5)throw Error();return rows.map(r=>{
      if(typeof r.id!=='string'||typeof r.reason!=='string'||typeof r.createdAt!=='string'||!Number.isFinite(Date.parse(r.createdAt)))throw Error();
      return {id:r.id,reason:r.reason,createdAt:r.createdAt,data:validateLedger(r.data)};
    });}catch{throw Error('本机恢复记录无法读取，原记录已保留。请先导出完整备份。');}
  }
  async load():Promise<{data:Ledger; recovered:boolean}> {
    const values=await Promise.all([0,1].map(i=>this.kv.get(`stock-ledger-v1-${i}`)));
    const valid: {data:Ledger;revision:number;slot:number}[]=[]; let invalid=false;
    for(let i=0;i<2;i++){ if(values[i]===null)continue; try { const e=JSON.parse(values[i]!); if(!Number.isSafeInteger(e.revision)||e.revision<1)throw Error(); valid.push({data:parseBackup(JSON.stringify(e.data)),revision:e.revision,slot:i}); } catch { invalid=true; } }
    valid.sort((a,b)=>b.revision-a.revision);
    if(!valid.length && invalid)throw new Error('本机账本无法读取。原数据已保留，请导入之前导出的备份恢复。');
    const latest=valid[0]; this.revision=latest?.revision??0;this.slot=latest?.slot??-1;this.ready=true;
    this.current=latest?.data??emptyLedger();return {data:this.current,recovered:invalid};
  }
  async save(data:Ledger,reason?:string) {
    if(!this.ready)throw new Error('本机存储尚未正常打开，不能写入。');
    if(this.writing)throw Error('正在保存，请稍后再试。');this.writing=true;
    try {
    const clean=validateLedger(data), slot=this.slot===0?1:0, revision=this.revision+1;
    if(reason&&this.current){
      const rows=[{id:crypto.randomUUID(),createdAt:new Date().toISOString(),reason,data:this.current},...await this.listRecovery()].slice(0,5);
      while(rows.length>1&&new TextEncoder().encode(JSON.stringify(rows)).length>8_000_000)rows.pop();
      if(new TextEncoder().encode(JSON.stringify(rows)).length>8_000_000)throw Error('恢复记录过大，无法安全保存此次修改。');
      await this.kv.set(recoveryKey,JSON.stringify(rows));
    }
    const payload=JSON.stringify({revision,data:clean});
    await this.kv.set(`stock-ledger-v1-${slot}`,payload);
    this.revision=revision; this.slot=slot;this.current=clean;
    }finally{this.writing=false;}
  }
  async recover(data:Ledger){validateLedger(data);this.ready=true; await this.save(data);}
}
export const store = new LedgerStore({get:async key=>(await Preferences.get({key})).value,set:async(key,value)=>{await Preferences.set({key,value});}});
