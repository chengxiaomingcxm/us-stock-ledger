import { Capacitor, registerPlugin } from '@capacitor/core';
import { Preferences } from '@capacitor/preferences';
const secure=registerPlugin<{read():Promise<{value?:string}>;write(options:{value:string}):Promise<void>}>('LedgerSecrets');
const key='stock-ledger-market-settings-v1';
// Save and read back the complete configuration before removing the legacy copy.
// A failed migration leaves the original available for a retry on the next launch.
export async function readMarketSettings():Promise<string|null>{
 if(Capacitor.getPlatform()!=='ios')return (await Preferences.get({key})).value;
 const saved=(await secure.read()).value;
 if(saved){await Preferences.remove({key});return saved;}
 const old=(await Preferences.get({key})).value;
 if(old!==null)await writeMarketSettings(old);
 return old;
}
export async function writeMarketSettings(value:string){
 if(Capacitor.getPlatform()!=='ios'){await Preferences.set({key,value});return;}
 await secure.write({value});
 if((await secure.read()).value!==value)throw Error('钥匙串保存校验失败，原设置已保留');
 await Preferences.remove({key});
}
