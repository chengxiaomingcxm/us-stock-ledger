import { it, expect, vi, beforeEach } from 'vitest';
const m=vi.hoisted(()=>({platform:'ios',read:vi.fn(),write:vi.fn(),get:vi.fn(),set:vi.fn(),remove:vi.fn()}));
vi.mock('@capacitor/core',()=>({Capacitor:{getPlatform:()=>m.platform},registerPlugin:()=>({read:m.read,write:m.write})}));
vi.mock('@capacitor/preferences',()=>({Preferences:{get:m.get,set:m.set,remove:m.remove}}));
import { readMarketSettings, writeMarketSettings } from '../src/secure-settings';
beforeEach(()=>{vi.resetAllMocks();m.platform='ios';});
it('migrates legacy credentials only after keychain roundtrip verification',async()=>{
 m.read.mockResolvedValueOnce({}).mockResolvedValueOnce({value:'legacy'});m.get.mockResolvedValue({value:'legacy'});
 expect(await readMarketSettings()).toBe('legacy');expect(m.write).toHaveBeenCalledWith({value:'legacy'});expect(m.remove).toHaveBeenCalledOnce();
 expect(m.remove.mock.invocationCallOrder[0]).toBeGreaterThan(m.read.mock.invocationCallOrder[1]);
});
it('does not remove existing preferences on failed keychain write or verification',async()=>{
 m.write.mockRejectedValueOnce(Error('locked'));await expect(writeMarketSettings('new')).rejects.toThrow();expect(m.remove).not.toHaveBeenCalled();
 m.read.mockResolvedValue({value:'old'});await expect(writeMarketSettings('new')).rejects.toThrow('校验');expect(m.remove).not.toHaveBeenCalled();
});
it('reads secure data first and removes residual legacy credentials',async()=>{
 m.read.mockResolvedValue({value:'secure'});expect(await readMarketSettings()).toBe('secure');expect(m.get).not.toHaveBeenCalled();expect(m.remove).toHaveBeenCalledOnce();
});
it('keeps browser preferences separate from the iOS keychain',async()=>{
 m.platform='web';m.get.mockResolvedValue({value:'web'});expect(await readMarketSettings()).toBe('web');await writeMarketSettings('next');expect(m.set).toHaveBeenCalledWith({key:'stock-ledger-market-settings-v1',value:'next'});expect(m.write).not.toHaveBeenCalled();
});
