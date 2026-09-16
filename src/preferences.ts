import { Preferences } from '@capacitor/preferences';
import { Capacitor, registerPlugin } from '@capacitor/core';
const native=registerPlugin<{setTheme(options:{theme:string}):Promise<void>}>('LedgerSecrets');
export interface Appearance { theme:'system'|'light'|'dark'; colors:'green-up'|'red-up'; reminderDays:0|7|30; lastExport:number }
export const defaults:Appearance={theme:'system',colors:'green-up',reminderDays:7,lastExport:0};
export function parseAppearance(raw:unknown):Appearance {
 const x=raw as Partial<Appearance>|null;
 return {theme:x&&['system','light','dark'].includes(x.theme!)?x.theme!:defaults.theme,
 colors:x&&['green-up','red-up'].includes(x.colors!)?x.colors!:defaults.colors,
 reminderDays:x&&[0,7,30].includes(x.reminderDays!)?x.reminderDays!:7,
 lastExport:x&&Number.isFinite(x.lastExport)&&x.lastExport!>=0?x.lastExport!:0};
}
export async function loadAppearance(){const {value}=await Preferences.get({key:'stock-ledger-appearance-v1'});return value?parseAppearance(JSON.parse(value)):{...defaults};}
export async function saveAppearance(value:Appearance){await Preferences.set({key:'stock-ledger-appearance-v1',value:JSON.stringify(value)});}
export function backupDue(p:Appearance,hasTrades:boolean,now=Date.now()){return hasTrades&&p.reminderDays>0&&now-p.lastExport>=p.reminderDays*86400000;}
export function applyAppearance(p:Appearance){document.documentElement.dataset.theme=p.theme;document.documentElement.dataset.colors=p.colors;if(Capacitor.getPlatform()==='ios')void native.setTheme({theme:p.theme}).catch(()=>{});}
