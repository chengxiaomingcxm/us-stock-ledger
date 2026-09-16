import { test, expect } from '@playwright/test';
test.beforeEach(async({page})=>{await page.route('https://query2.finance.yahoo.com/**',r=>r.abort());await page.route('https://financialmodelingprep.com/**',r=>r.abort());});
const settings=async(page:any)=>page.locator('.bottom-nav').getByRole('button',{name:'设置',exact:true}).click();
test('配色保留符号，外观和提醒重启后保留，深浅色各页无溢出',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'先看看示例账本',exact:true}).click();await settings(page);
 await page.getByLabel('涨跌颜色',{exact:true}).selectOption('red-up');await expect(page.locator('html')).toHaveAttribute('data-colors','red-up');
 await expect(page.locator('.color-preview .positive')).toHaveText('+$12.34 / +1.23%');
 for(const theme of ['dark','light']){
  await page.getByLabel('外观',{exact:true}).selectOption(theme);await expect(page.locator('html')).toHaveAttribute('data-theme',theme);
  for(const name of ['持仓','交易','收益','设置']){
   await page.locator('.bottom-nav').getByRole('button',{name,exact:true}).click();
   for(const width of [320,402,430]){await page.setViewportSize({width,height:874});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),{message:`${name}页在 ${width}px 存在横向溢出`}).toBe(true);}
   if(name==='持仓'){await expect(page.getByTestId('unrealized')).toHaveText('+$1,362.25');await page.screenshot({path:`artifacts/v123-home-${theme}.png`,fullPage:true});}
   if(name==='设置')await page.screenshot({path:`artifacts/v123-settings-${theme}.png`,fullPage:true});
  }
 }
 await page.getByLabel('外观',{exact:true}).selectOption('dark');await page.getByLabel('备份提醒',{exact:true}).selectOption('30');await page.reload();await settings(page);
 await expect(page.getByLabel('涨跌颜色',{exact:true})).toHaveValue('red-up');await expect(page.getByLabel('外观',{exact:true})).toHaveValue('dark');await expect(page.getByLabel('备份提醒',{exact:true})).toHaveValue('30');
 await page.getByLabel('涨跌颜色',{exact:true}).selectOption('green-up');await expect(page.locator('.color-preview .positive')).toHaveCSS('color','rgb(81, 215, 129)');await expect(page.locator('.color-preview .negative')).toHaveCSS('color','rgb(255, 105, 117)');
 await page.getByLabel('外观',{exact:true}).selectOption('system');await page.emulateMedia({colorScheme:'dark'});await expect(page.locator('body')).toHaveCSS('background-color','rgb(0, 0, 0)');await page.emulateMedia({colorScheme:'light'});await expect(page.locator('body')).toHaveCSS('background-color','rgb(242, 242, 247)');
});
test('快捷卖出、手续费默认值、撤销新增和备份提醒不改变账本口径',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'记一笔',exact:true}).click();
 await page.getByLabel('股票代码',{exact:true}).fill('AAPL');await page.getByLabel('成交股数',{exact:true}).fill('3.5');await page.getByLabel('成交单价（美元）',{exact:true}).fill('100');await page.getByLabel('手续费（美元）',{exact:true}).fill('0.25');await page.getByRole('button',{name:'保存交易',exact:true}).click();
 await expect(page.getByTestId('cost')).toHaveText('$350.25');await expect(page.locator('#backup-reminder')).toBeVisible();
 await page.getByRole('button',{name:'记一笔',exact:true}).click();await expect(page.getByLabel('手续费（美元）',{exact:true})).toHaveValue('0.25');
 await page.getByLabel('卖出',{exact:true}).check();await page.getByLabel('股票代码',{exact:true}).fill('AAPL');await expect(page.locator('#available-shares')).toContainText('3.5');
 await page.getByRole('button',{name:'一半',exact:true}).click();await expect(page.getByLabel('成交股数',{exact:true})).toHaveValue('1.75');await page.getByRole('button',{name:'全部',exact:true}).click();await expect(page.getByLabel('成交股数',{exact:true})).toHaveValue('3.5');
 await page.getByLabel('成交单价（美元）',{exact:true}).fill('110');await page.getByRole('button',{name:'保存交易',exact:true}).click();await expect(page.getByTestId('realized')).toHaveText('+$34.50');
 await page.getByRole('button',{name:'撤销新增',exact:true}).click();await page.getByRole('button',{name:'确认撤销',exact:true}).click();await expect(page.getByTestId('cost')).toHaveText('$350.25');await expect(page.getByTestId('realized')).toHaveText('$0.00');
 await settings(page);await page.getByLabel('备份提醒',{exact:true}).selectOption('0');await page.locator('.bottom-nav').getByRole('button',{name:'持仓',exact:true}).click();await expect(page.locator('#backup-reminder')).toHaveCount(0);
});
