import { test, expect } from '@playwright/test';
test.use({timezoneId:'Asia/Ho_Chi_Minh'});
// 1.25：今日盈亏、交易区间汇总、行情状态明细与未保存表单提醒。
// Monday follows Friday. Keep fixtures independent of the machine date and timezone.
const marketToday = '2026-09-14';
const marketPrev = '2026-09-11';
const ledger = {
  version: 1, currency: 'USD', method: 'moving-average',
  trades: [
    { id: 'b', sequence: 0, symbol: 'AAPL', date: '2025-06-01', side: 'buy', quantity: '10', price: '100', fee: '1', note: '建仓' },
    { id: 's', sequence: 1, symbol: 'AAPL', date: '2025-08-01', side: 'sell', quantity: '2', price: '120', fee: '1', note: '部分止盈' },
  ],
  quotes: [{ symbol: 'AAPL', price: '110', date: marketToday }],
  history: { version: 1, closes: [{ symbol: 'AAPL', price: '100', date: marketPrev }], sessions: [marketPrev], splits: [] },
};
test.beforeEach(async ({ page }) => {
  await page.clock.install({time:new Date('2026-09-14T16:00:00Z')});
  await page.addInitScript(data => {
    if (!localStorage.getItem('v125-seeded')) {
      localStorage.setItem('CapacitorStorage.stock-ledger-v1-0', JSON.stringify({ revision: 1, data }));
      localStorage.setItem('v125-seeded', 'yes');
    }
  }, ledger);
  await page.route('https://query2.finance.yahoo.com/**', r => r.abort());
  await page.route('https://financialmodelingprep.com/**', r => r.abort());
});
test('今日盈亏结合上一收盘与当日报价，持有收益分开显示', async ({ page }) => {
  await page.goto('/');
  // 今日开盘 8 股：8×(110−100)=80；80/800=10%
  await expect(page.getByTestId('today-pnl')).toHaveText('+$80.00');
  await expect(page.locator('.valuation-percent')).toHaveText('+10.00%');
  await expect(page.locator('.valuation-card p')).toContainText(`对比 ${marketPrev} 收盘`);
  // 持有收益 = 8×110 − 800.8 = 79.2
  await expect(page.getByTestId('unrealized')).toHaveText('+$79.20');
  await expect(page.getByTestId('cost')).toHaveText('$800.80');
});
test('交易页日期区间筛选并汇总手续费与已实现收益', async ({ page }) => {
  await page.goto('/');
  await page.locator('.bottom-nav').getByRole('button', { name: '交易', exact: true }).click();
  await expect(page.locator('.trade-summary')).toContainText('2 笔');
  await page.getByLabel('起始日期').fill('2025-08-01');
  await page.getByLabel('结束日期').fill('2025-08-01');
  await expect(page.locator('.trade-summary')).toContainText('1 笔');
  await expect(page.locator('.trade-summary')).toContainText('+$38.80');
  await expect(page.locator('.trade-summary')).toContainText('手续费 $1.00');
  // 起始晚于结束会自动交换
  await page.getByLabel('起始日期').fill('2025-08-02');
  await page.getByLabel('结束日期').fill('2025-08-01');
  await expect(page.locator('.trade-summary')).toContainText('1 笔');
  await page.getByRole('button', { name: '清除筛选' }).click();
  await expect(page.locator('.trade-summary')).toContainText('2 笔');
});
test('行情状态面板逐只显示报价时间与来源，休市与过期分开', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '查看行情状态', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toContainText('各股票报价');
  await expect(dialog).toContainText('手动报价');
  await expect(dialog).toContainText(marketToday);
  await expect(dialog).toContainText(`今日 ${marketToday} ·`);
  await page.getByRole('button', { name: '关闭', exact: true }).click();
});
test('退出未保存的交易表单会提醒，可继续编辑或放弃', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '记一笔', exact: true }).click();
  await page.getByLabel('股票代码', { exact: true }).fill('AAPL');
  await page.getByRole('button', { name: '关闭', exact: true }).click();
  await expect(page.getByText('放弃未保存的修改？')).toBeVisible();
  await expect(page.locator('.modal-backdrop:not(.discard-layer)')).toHaveAttribute('inert','');
  await page.getByRole('button', { name: '继续编辑', exact: true }).focus();
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button',{name:'关闭提醒',exact:true})).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(page.getByRole('button',{name:'继续编辑',exact:true})).toBeFocused();
  await page.getByRole('button', { name: '继续编辑', exact: true }).click();
  await expect(page.getByLabel('股票代码', { exact: true })).toHaveValue('AAPL');
  await expect(page.locator('.modal-backdrop')).not.toHaveAttribute('inert','');
  await page.getByRole('button', { name: '关闭', exact: true }).click();
  await page.getByRole('button', { name: '放弃修改', exact: true }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByTestId('cost')).toHaveText('$800.80');
});

test('持仓详情记一笔带入当前股票且空表单可直接关闭',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'查看 AAPL 持仓详情',exact:true}).click();
 await page.getByRole('dialog').getByRole('button',{name:'记一笔',exact:true}).click();
 await expect(page.getByLabel('股票代码',{exact:true})).toHaveValue('AAPL');
 await page.getByRole('button',{name:'关闭',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);
});

test('越南凌晨新增交易和手动报价默认美东日期，手续费计入今日盈亏',async({page})=>{
 await page.clock.setFixedTime(new Date('2026-09-15T21:00:00Z'));
 const fixture={...ledger,quotes:[{symbol:'AAPL',price:'100',date:'2026-09-15'}],history:{version:1,closes:[{symbol:'AAPL',price:'100',date:'2026-09-14'}],sessions:['2026-09-14'],splits:[]}};
 await page.addInitScript(data=>localStorage.setItem('CapacitorStorage.stock-ledger-v1-0',JSON.stringify({revision:1,data})),fixture);
 await page.goto('/');await expect(page.getByTestId('today-pnl')).toHaveText('$0.00');
 await page.getByRole('button',{name:'记一笔',exact:true}).click();
 await expect(page.getByLabel('交易日期（美东）',{exact:true})).toHaveValue('2026-09-15');
 await page.getByLabel('股票代码',{exact:true}).fill('AAPL');await page.getByLabel('成交股数',{exact:true}).fill('1');await page.getByLabel('成交单价（美元）',{exact:true}).fill('100');await page.getByLabel('手续费（美元）',{exact:true}).fill('1');
 await page.getByRole('button',{name:'保存交易',exact:true}).click();await expect(page.getByTestId('today-pnl')).toHaveText('−$1.00');
 await page.getByRole('button',{name:'更新 AAPL 股价',exact:true}).click();await expect(page.getByLabel('报价日期（美东）',{exact:true})).toHaveValue('2026-09-15');
});

test('最新报价的日期和时分统一显示美东时区',async({page})=>{
 await page.clock.setFixedTime(new Date('2026-09-15T21:00:00Z'));
 await page.addInitScript(()=>localStorage.setItem('CapacitorStorage.stock-ledger-market-settings-v1',JSON.stringify({provider:'finnhub',key:'TEST_ONLY',url:'',interval:0})));
 await page.route('https://finnhub.io/api/v1/quote?*',r=>r.fulfill({json:{c:111,t:Date.parse('2026-09-15T21:00:00Z')/1000}}));
 await page.goto('/');await expect(page.getByTestId('cost')).toHaveText('$800.80');
 // Saving the source starts an isolated live refresh after the initial history check.
 await page.getByRole('button',{name:'查看行情状态',exact:true}).click();
 await page.getByRole('button',{name:'更换行情来源',exact:true}).click();
 await page.getByRole('button',{name:'保存设置',exact:true}).click();
 await expect(page.locator('.compact-holding .quote-date')).toContainText('2026-09-15 17:00 美东');
});
