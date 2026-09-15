import { Preferences } from '@capacitor/preferences';
import { emptyLedger, parseBackup, validateLedger, type Ledger } from './ledger';
export interface KV { get(key:string):Promise<string|null>; set(key:string,value:string):Promise<void> }
export class LedgerStore {
  constructor(private kv:KV) {}
  private revision=0; private slot=-1; private ready=false;
  async load():Promise<{data:Ledger; recovered:boolean}> {
    const values=await Promise.all([0,1].map(i=>this.kv.get(`stock-ledger-v1-${i}`)));
    const valid: {data:Ledger;revision:number;slot:number}[]=[]; let invalid=false;
    for(let i=0;i<2;i++){ if(values[i]===null)continue; try { const e=JSON.parse(values[i]!); if(!Number.isSafeInteger(e.revision)||e.revision<1)throw Error(); valid.push({data:parseBackup(JSON.stringify(e.data)),revision:e.revision,slot:i}); } catch { invalid=true; } }
    valid.sort((a,b)=>b.revision-a.revision);
    if(!valid.length && invalid)throw new Error('本机账本无法读取。原数据已保留，请导入之前导出的备份恢复。');
    const latest=valid[0]; this.revision=latest?.revision??0;this.slot=latest?.slot??-1;this.ready=true;
    return {data:latest?.data??emptyLedger(),recovered:invalid};
  }
  async save(data:Ledger) {
    if(!this.ready)throw new Error('本机存储尚未正常打开，不能写入。');
    const clean=validateLedger(data), slot=this.slot===0?1:0, revision=this.revision+1;
    const payload=JSON.stringify({revision,data:clean});
    await this.kv.set(`stock-ledger-v1-${slot}`,payload);
    this.revision=revision; this.slot=slot;
  }
  async recover(data:Ledger){validateLedger(data);this.ready=true; await this.save(data);}
}
export const store = new LedgerStore({get:async key=>(await Preferences.get({key})).value,set:async(key,value)=>{await Preferences.set({key,value});}});
