import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
test.beforeEach(async({page})=>{await page.route('https://query2.finance.yahoo.com/**',route=>route.abort());});
async function add(page:any,side='buy',q='10',price='100',fee='1'){
 await page.getByRole('button',{name:'记一笔',exact:true}).click();
 await page.getByRole('dialog').locator(`input[value="${side}"]`).check();
 await page.getByLabel('股票代码',{exact:true}).fill('AAPL');
 await page.getByLabel('成交股数',{exact:true}).fill(q);
 await page.getByLabel('成交单价（美元）',{exact:true}).fill(price);
 await page.getByLabel('手续费（美元）',{exact:true}).fill(fee);
 await page.getByRole('button',{name:'保存交易',exact:true}).click();
 await expect(page.getByRole('dialog')).toHaveCount(0);
}
test('完整记账流程、更新报价、重启、编辑、备份与恢复',async({page})=>{
 const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/'); await expect(page.getByText('从第一笔投资开始')).toBeVisible();
 await add(page);await expect(page.getByTestId('cost')).toHaveText('$1,001.00');await expect(page.getByTestId('unrealized')).toHaveText('—');
 await add(page,'sell','4','120','2');await expect(page.getByTestId('cost')).toHaveText('$600.60');await expect(page.getByTestId('realized')).toHaveText('+$77.60');
 await page.getByRole('button',{name:'更新 AAPL 股价',exact:true}).click();await page.getByLabel('股价（美元）',{exact:true}).fill('130');await page.getByRole('button',{name:'保存股价',exact:true}).click();
 await expect(page.getByTestId('market-value')).toHaveText('$780.00');await expect(page.getByTestId('unrealized')).toHaveText('+$179.40');
 await page.reload();await expect(page.getByTestId('cost')).toHaveText('$600.60');
 await page.locator('.bottom-nav').getByRole('button',{name:'交易',exact:true}).click();
 await page.locator('.trade-row').filter({has:page.locator('.badge.buy')}).getByRole('button',{name:'编辑',exact:true}).click();await page.getByLabel('成交单价（美元）',{exact:true}).fill('90');await page.getByRole('button',{name:'保存修改',exact:true}).click();
 await page.locator('.bottom-nav').getByRole('button',{name:'持仓',exact:true}).click();await expect(page.getByTestId('cost')).toHaveText('$540.60');await expect(page.getByTestId('realized')).toHaveText('+$117.60');
 await page.locator('.bottom-nav').getByRole('button',{name:'交易',exact:true}).click();await page.locator('.trade-row').filter({has:page.locator('.badge.buy')}).getByRole('button',{name:'删除',exact:true}).click();await page.getByRole('button',{name:'确认删除',exact:true}).click();await expect(page.locator('#form-error')).toContainText('超过当时持仓');await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.locator('.bottom-nav').getByRole('button',{name:'设置',exact:true}).click();
 const downloadEvent=page.waitForEvent('download');await page.getByRole('button',{name:/导出完整备份/}).click();const download=await downloadEvent;const path=await download.path();const backup=await readFile(path!,'utf8');expect(JSON.parse(backup).trades).toHaveLength(2);
 await page.locator('#import').setInputFiles({name:'invalid.json',mimeType:'application/json',buffer:Buffer.from('{}')});await expect(page.getByText('无法导入备份',{exact:true})).toBeVisible();await page.getByRole('button',{name:'关闭',exact:true}).click();
 const clean={version:1,currency:'USD',method:'moving-average',trades:[],quotes:[]};await page.locator('#import').setInputFiles({name:'empty.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(clean))});await page.getByRole('button',{name:'确认替换并恢复',exact:true}).click();await expect(page.locator('.backup-count')).toContainText('0 笔交易');
 await page.locator('#import').setInputFiles({name:'backup.json',mimeType:'application/json',buffer:Buffer.from(backup)});await expect(page.getByText('恢复这份备份？',{exact:true})).toBeVisible();await page.getByRole('button',{name:'确认替换并恢复',exact:true}).click();await expect(page.locator('.backup-count')).toContainText('2 笔交易');
 await page.locator('.bottom-nav').getByRole('button',{name:'持仓',exact:true}).click();await expect(page.getByTestId('cost')).toHaveText('$540.60');await page.reload();await expect(page.getByTestId('market-value')).toHaveText('$780.00');expect(errors).toEqual([]);
});
test('示例模式隔离、手机和桌面排版',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:/先看看示例账本/}).click();await expect(page.locator('.holding-card')).toHaveCount(3);await expect(page.locator('.demo-banner')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:'artifacts/iphone-preview.png',fullPage:false});
 await page.getByRole('button',{name:'记一笔',exact:true}).click();await page.screenshot({path:'artifacts/trade-form-preview.png',fullPage:false});await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.locator('.bottom-nav').getByRole('button',{name:'收益',exact:true}).click();await page.screenshot({path:'artifacts/returns-preview.png',fullPage:true});
 await page.setViewportSize({width:1280,height:900});await page.locator('.sidebar').getByRole('button',{name:'持仓',exact:true}).click();await page.screenshot({path:'artifacts/desktop-preview.png',fullPage:true});
 await page.getByRole('button',{name:'退出示例',exact:true}).click();await expect(page.getByText('从第一笔投资开始')).toBeVisible();await page.reload();await expect(page.getByText('从第一笔投资开始')).toBeVisible();
});
