import { it, expect } from 'vitest';
import { defaults, parseAppearance, backupDue } from '../src/preferences';
it('keeps defaults for malformed preferences without changing the ledger',()=>{
 expect(parseAppearance(null)).toEqual(defaults);
 expect(parseAppearance({theme:'bad',colors:'bad',lastExport:-1,reminderDays:2})).toEqual(defaults);
 expect(parseAppearance({theme:'dark',colors:'red-up',reminderDays:0,lastExport:12})).toEqual({theme:'dark',colors:'red-up',reminderDays:0,lastExport:12});
});
it('only reminds for populated ledgers, honors disabling and the export interval',()=>{
 const now=30*86400000;
 expect(backupDue(defaults,true,now)).toBe(true);
 expect(backupDue(defaults,false,now)).toBe(false);
 expect(backupDue({...defaults,reminderDays:0},true,now)).toBe(false);
 expect(backupDue({...defaults,lastExport:now-6*86400000},true,now)).toBe(false);
 expect(backupDue({...defaults,lastExport:now-7*86400000},true,now)).toBe(true);
});
