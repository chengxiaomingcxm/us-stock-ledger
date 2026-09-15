import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
const ledger={version:1,currency:'USD',method:'moving-average',trades:[{id:'b',sequence:0,symbol:'AAPL',date:'2026-09-09',side:'buy',quantity:'10',price:'100',fee:'1',note:'保留备注'}],quotes:[]};
test('收益日历、历史重算、两种备份导出与本机恢复',async({page})=>{
 await page.addInitScript(data=>{if(!localStorage.getItem('seeded')){localStorage.setItem('CapacitorStorage.stock-ledger-v1-0',JSON.stringify({revision:1,data}));localStorage.setItem('seeded','yes');}},ledger);
 await page.route('https://financialmodelingprep.com/**',r=>r.abort());
 await page.route('https://query2.finance.yahoo.com/**',r=>{const symbol=r.request().url().includes('/SPY?')?'SPY':'AAPL';return r.fulfill({contentType:'application/json',body:JSON.stringify({chart:{result:[{meta:{symbol,currency:'USD',instrumentType:'EQUITY',exchangeTimezoneName:'America/New_York',priceHint:2},timestamp:['2026-09-08','2026-09-09','2026-09-10','2026-09-11'].map(d=>Date.parse(d+'T13:30:00Z')/1000),indicators:{quote:[{close:[100,110,120,130]}]}}]}})});});
 await page.goto('/');await expect(page.getByTestId('sync-status')).toContainText('1 只取得');
 const nav=page.locator('.bottom-nav');await nav.getByRole('button',{name:'收益',exact:true}).click();
 await page.locator('#history-month').fill('2026-09');
 await expect(page.getByTestId('daily-profit')).toHaveText('+$100.00');
 await expect(page.locator('[data-day="2026-09-09"]')).toContainText('+99.00');
 await page.locator('[data-day="2026-09-09"]').click();await expect(page.getByRole('dialog')).toContainText('AAPL');await expect(page.getByRole('dialog')).toContainText('+$99.00');await page.getByRole('button',{name:'关闭',exact:true}).click();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:'artifacts/v12-calendar-iphone.png',fullPage:true});
 await page.setViewportSize({width:1280,height:900});await page.screenshot({path:'artifacts/v12-calendar-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:844});
 await nav.getByRole('button',{name:'交易',exact:true}).click();await page.getByRole('button',{name:'编辑',exact:true}).click();await page.getByLabel('成交单价（美元）',{exact:true}).fill('90');await page.getByRole('button',{name:'保存修改',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);
 await nav.getByRole('button',{name:'收益',exact:true}).click();await expect(page.locator('[data-day="2026-09-09"]')).toContainText('+199.00');
 await nav.getByRole('button',{name:'备份',exact:true}).click();
 for(const [id,history] of [['export',true],['export-compatible',false]] as const){const event=page.waitForEvent('download');await page.locator('#'+id).click();const download=await event;const data=JSON.parse(readFileSync((await download.path())!,'utf8'));expect(!!data.history).toBe(history);expect(data.trades[0].note).toBe('保留备注');expect(data.version).toBe(1);}
 await page.getByRole('button',{name:'本机恢复记录'}).click();await page.getByRole('button',{name:'编辑交易前'}).click();await page.getByRole('button',{name:'确认恢复',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);
 await nav.getByRole('button',{name:'收益',exact:true}).click();await expect(page.locator('[data-day="2026-09-09"]')).toContainText('+99.00');await page.reload();await expect(page.getByTestId('cost')).toHaveText('$1,001.00');
});
