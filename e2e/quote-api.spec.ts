import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
const old=JSON.parse(readFileSync(new URL('../tests/fixtures/v1-backup.json',import.meta.url),'utf8'));
test.beforeEach(async({page})=>{await page.route('https://query2.finance.yahoo.com/**',r=>r.abort());});
test('API 设置校验、连接测试、重启保存与切回默认来源',async({page})=>{
 await page.route('https://quotes.example/**',r=>r.fulfill({json:{symbol:'AAPL',currency:'USD',price:'220',timestamp:new Date().toISOString()}}));
 await page.goto('/');await page.getByRole('button',{name:'查看行情状态',exact:true}).click();await page.getByRole('button',{name:/更换行情来源/}).click();
 await page.getByRole('combobox',{name:'数据源',exact:true}).selectOption('custom');await page.getByLabel('HTTPS 接口地址').fill('http://quotes.example/{symbol}');
 await page.getByRole('button',{name:'保存设置',exact:true}).click();await expect(page.locator('#form-error')).toContainText('HTTPS');
 await page.getByLabel('HTTPS 接口地址').fill('https://quotes.example/{symbol}');await page.getByLabel('API Key',{exact:true}).fill('TEST-ONLY-SECRET');
 await page.getByRole('button',{name:'测试连接（AAPL）'}).click();await expect(page.locator('#api-status')).toContainText('连接成功');
 await page.getByRole('combobox',{name:'前台自动刷新',exact:true}).selectOption('300');await page.getByRole('button',{name:'保存设置',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);
 await page.reload();await page.getByRole('button',{name:'查看行情状态',exact:true}).click();await page.getByRole('button',{name:/更换行情来源/}).click();
 await expect(page.getByRole('combobox',{name:'数据源',exact:true})).toHaveValue('custom');await expect(page.getByRole('combobox',{name:'前台自动刷新',exact:true})).toHaveValue('300');
 await page.getByRole('combobox',{name:'数据源',exact:true}).selectOption('yahoo');await page.getByRole('button',{name:'保存设置',exact:true}).click();await page.getByRole('button',{name:'查看行情状态',exact:true}).click();await expect(page.getByRole('button',{name:/更换行情来源/})).toContainText('Yahoo Finance');
});
test('盘中价更新估值，限流保留报价，备份不含盘中价格或密钥',async({page})=>{
 await page.addInitScript(({ledger})=>{
  localStorage.setItem('CapacitorStorage.stock-ledger-v1-0',JSON.stringify({revision:5,data:ledger}));
  localStorage.setItem('CapacitorStorage.stock-ledger-market-settings-v1',JSON.stringify({provider:'custom',url:'https://quotes.example/{symbol}',key:'TEST-ONLY-SECRET',interval:0}));
 },{ledger:old});
 let fail=false;await page.route('https://quotes.example/**',r=>r.fulfill({status:fail?429:200,json:{symbol:'AAPL',currency:'USD',price:'220',timestamp:new Date().toISOString()}}));
 await page.goto('/');await expect(page.getByTestId('market-value')).toHaveText('$1,320.00');await expect(page.locator('.quote-date')).toContainText('最新报价');
 fail=true;await expect(page.getByRole('button',{name:'更新收益',exact:true})).toBeEnabled();await page.getByRole('button',{name:'更新收益',exact:true}).click();
 await expect(page.getByTestId('sync-status')).toContainText('最新价更新失败');await page.getByRole('button',{name:'查看行情状态',exact:true}).click();await expect(page.getByRole('dialog')).toContainText('请求限流');await page.getByRole('button',{name:'关闭',exact:true}).click();await expect(page.getByTestId('market-value')).toHaveText('$1,320.00');
 await page.getByRole('button',{name:'设置',exact:true}).click();const event=page.waitForEvent('download');await page.getByRole('button',{name:/导出完整备份/}).click();const download=await event;const backup=await readFile((await download.path())!,'utf8');
 expect(backup).not.toContain('TEST-ONLY-SECRET');expect(JSON.parse(backup).quotes).toEqual(old.quotes);expect(JSON.parse(backup).trades).toEqual(old.trades);
});
test('手机尺寸下触控、弹窗和页面无横向溢出',async({page})=>{
 await page.setViewportSize({width:402,height:874});await page.goto('/');
 expect(await page.locator('html').evaluate(el=>getComputedStyle(el).touchAction)).toBe('manipulation');
 await page.getByRole('button',{name:'查看行情状态',exact:true}).click();await page.getByRole('button',{name:/更换行情来源/}).click();
 await page.getByRole('combobox',{name:'数据源',exact:true}).selectOption('custom');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 expect(await page.getByLabel('API Key',{exact:true}).evaluate(el=>getComputedStyle(el).fontSize)).toBe('16px');
 await page.getByRole('button',{name:'关闭',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);
});
