import { test, expect } from '@playwright/test';
test.beforeEach(async({page})=>{await page.route('https://query2.finance.yahoo.com/**',r=>r.abort());await page.route('https://financialmodelingprep.com/**',r=>r.abort());});
test('首页金额隐藏、详情、筛选排序及帮助文档',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'先看看示例账本',exact:true}).click();
 await expect(page.getByTestId('unrealized')).toHaveText('+$1,362.25');
 await page.getByRole('button',{name:'隐藏首页金额',exact:true}).click();
 for(const id of ['unrealized','market-value','cost','realized'])await expect(page.getByTestId(id)).toHaveText('••••');
 await expect(page.locator('.compact-holdings')).not.toContainText('$');
 await page.getByRole('button',{name:'查看 AAPL 持仓详情',exact:true}).click();await expect(page.getByRole('dialog')).not.toContainText('$');await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.getByRole('button',{name:'显示首页金额',exact:true}).click();
 await page.getByRole('combobox',{name:'持仓排序',exact:true}).selectOption('value');
 await expect(page.locator('.holding-name>strong').first()).toHaveText('NVDA');
 await page.getByRole('button',{name:'待报价',exact:true}).click();await expect(page.getByText('没有符合条件的持仓')).toBeVisible();
 await page.getByRole('button',{name:'全部 3',exact:true}).click();await expect(page.locator('.holding-card')).toHaveCount(3);
 await page.getByRole('button',{name:'查看 AAPL 持仓详情',exact:true}).click();await expect(page.getByRole('dialog')).toContainText('平均成本');await page.getByRole('button',{name:'更新股价',exact:true}).click();await expect(page.getByRole('dialog')).toContainText('更新 AAPL 股价');await page.getByRole('button',{name:'关闭',exact:true}).click();
 await page.locator('.bottom-nav').getByRole('button',{name:'设置',exact:true}).click();
 await expect(page.getByText('移动平均成本',{exact:true})).toHaveCount(0);
 await page.getByRole('button',{name:/帮助文档/}).click();await expect(page.getByRole('heading',{name:'帮助文档',exact:true})).toBeVisible();await expect(page.locator('#help-home')).toHaveAttribute('open','');
 await page.getByText('备份、恢复与升级',{exact:true}).click();await expect(page.locator('#help-backup')).toContainText('不先卸载旧版');
 await page.getByRole('button',{name:'返回设置',exact:true}).click();await expect(page.getByRole('heading',{name:'设置',exact:true})).toBeVisible();
 await page.locator('.bottom-nav').getByRole('button',{name:'持仓',exact:true}).click();await page.getByRole('button',{name:'查看行情状态',exact:true}).click();await page.getByRole('button',{name:/更换行情来源/}).click();await page.getByRole('button',{name:'配置帮助',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);await expect(page.locator('#help-api')).toHaveAttribute('open','');
});
test('首页小屏与手机尺寸布局',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'先看看示例账本',exact:true}).click();
 for(const width of [320,402,430,1280]){await page.setViewportSize({width,height:874});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);}
 await page.setViewportSize({width:402,height:874});await page.screenshot({path:'artifacts/v122-home.png',fullPage:true});
 await page.locator('.bottom-nav').getByRole('button',{name:'设置',exact:true}).click();await page.screenshot({path:'artifacts/v122-settings.png',fullPage:true});
});
test('底栏中央记一笔在各页可用，首页没有长说明',async({page})=>{
 await page.goto('/');const bar=page.locator('.bottom-nav');
 await expect(bar.getByRole('button')).toHaveText(['持仓','交易','记一笔','收益','设置']);
 await expect(page.locator('header').getByRole('button',{name:'记一笔',exact:true})).toHaveCount(0);
 await expect(page.locator('main .sync-panel')).toHaveCount(0);
 await expect(page.getByText('实际延迟取决于数据源',{exact:false})).toHaveCount(0);
 for(const name of ['持仓','交易','收益','设置']){
  await bar.getByRole('button',{name,exact:true}).click();
  await bar.getByRole('button',{name:'记一笔',exact:true}).click();
  await expect(page.getByRole('dialog',{name:'记录交易',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'关闭',exact:true}).click();
 }
 await page.setViewportSize({width:320,height:740});
 const center=await bar.getByRole('button',{name:'记一笔',exact:true}).boundingBox();
 expect(center!.width).toBeGreaterThanOrEqual(44);expect(center!.height).toBeGreaterThanOrEqual(44);
 const rect=await bar.boundingBox();expect(Math.abs(center!.x+center!.width/2-(rect!.x+rect!.width/2))).toBeLessThan(1);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

