import { test, expect } from '@playwright/test';
import fs from 'node:fs';
test.use({ timezoneId: 'Asia/Ho_Chi_Minh' });
// 1.26：现金账本（期初余额、入金出金、分红税费）、券商 CSV 导入（映射、错误行、疑似重复）与备份包含现金。
const ledger = {
  version: 1, currency: 'USD', method: 'moving-average',
  trades: [{ id: 'b', sequence: 0, symbol: 'AAPL', date: '2025-06-01', side: 'buy', quantity: '10', price: '100', fee: '1', note: '建仓' }],
  quotes: [],
};
test.beforeEach(async ({ page }) => {
  await page.clock.install({ time: new Date('2026-09-14T16:00:00Z') });
  await page.addInitScript(data => {
    if (!localStorage.getItem('v126-seeded')) {
      localStorage.setItem('CapacitorStorage.stock-ledger-v1-0', JSON.stringify({ revision: 1, data }));
      localStorage.setItem('v126-seeded', 'yes');
    }
  }, ledger);
  await page.route('https://query2.finance.yahoo.com/**', r => r.abort());
  await page.route('https://financialmodelingprep.com/**', r => r.abort());
});
test('现金账本：设置期初余额后记录入金、分红与费用，入金出金不计盈亏', async ({ page }) => {
  await page.goto('/');
  await page.locator('.bottom-nav').getByRole('button', { name: '收益', exact: true }).click();
  await expect(page.getByTestId('cash-balance')).toHaveText('待设置期初');
  await page.getByRole('button', { name: '设置期初余额', exact: true }).click();
  await page.getByLabel('日期（美东）').fill('2025-01-01');
  await page.getByLabel('金额（美元）').fill('10000');
  await page.getByRole('button', { name: '保存记录', exact: true }).click();
  await expect(page.getByTestId('cash-balance')).toHaveText('$10,000.00');
  // 入金
  await page.getByRole('button', { name: '入金', exact: true }).click();
  await page.getByLabel('金额（美元）').fill('2000');
  await page.getByRole('button', { name: '保存记录', exact: true }).click();
  await expect(page.getByTestId('cash-balance')).toHaveText('$12,000.00');
  await expect(page.getByTestId('cash-deposit')).toHaveText('$2,000.00');
  // 分红（毛额 120 − 预扣税 12）
  await page.getByRole('button', { name: '分红', exact: true }).click();
  await page.getByLabel('金额（美元）').fill('120');
  await page.getByLabel('预扣税费（选填）').fill('12');
  await page.getByLabel('股票代码（选填）').fill('AAPL');
  await page.getByRole('button', { name: '保存记录', exact: true }).click();
  await expect(page.getByTestId('cash-balance')).toHaveText('$12,108.00');
  await expect(page.getByTestId('cash-dividend')).toHaveText('$108.00');
  await expect(page.getByTestId('cash-tax')).toHaveText('−$12.00');
  await expect(page.getByTestId('cash-external')).toHaveText('+$12,000.00');
  await expect(page.getByTestId('cash-invest')).toHaveText('+$108.00');
  // 账户费用，再删除
  await page.getByRole('button', { name: '费用', exact: true }).click();
  await page.getByLabel('金额（美元）').fill('5');
  await page.getByRole('button', { name: '保存记录', exact: true }).click();
  await expect(page.getByTestId('cash-balance')).toHaveText('$12,103.00');
  await page.locator('.cash-record', { hasText: '账户费用' }).getByRole('button', { name: '删除', exact: true }).click();
  await page.getByRole('button', { name: '确认删除', exact: true }).click();
  await expect(page.getByTestId('cash-balance')).toHaveText('$12,108.00');
  // 入金出金不进入投资收益
  await expect(page.locator('.profit-summary .summary-number')).toHaveText('—');
});
test('CSV 交易导入：自动映射、疑似重复默认跳过、确认后写入', async ({ page }) => {
  await page.goto('/');
  await page.locator('.bottom-nav').getByRole('button', { name: '收益', exact: true }).click();
  await page.getByRole('button', { name: '导入 CSV', exact: true }).click();
  const csv = ['Date,Symbol,Side,Quantity,Price,Fee,Note',
    '2025-06-01,AAPL,BUY,10,100,1,重复行',
    '2026-09-10,MSFT,BUY,2,300,1,新买入',
    '2026-09-11,AAPL,SELL,3,120,2,部分卖出'].join('\n');
  await page.locator('#csv-file').setInputFiles({ name: 'trades.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) });
  await expect(page.getByTestId('import-summary')).toContainText('共 3 行');
  await expect(page.getByTestId('import-summary')).toContainText('可导入 2');
  await expect(page.getByTestId('import-summary')).toContainText('疑似重复 1');
  await expect(page.getByTestId('import-summary')).toContainText('错误 0');
  await expect(page.locator('.csv-row.csv-dup input')).not.toBeChecked();
  await expect(page.locator('.csv-row:not(.csv-dup) input')).toHaveCount(2);
  await expect(page.getByRole('button', { name: '确认导入 2 笔', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '确认导入 2 笔', exact: true }).click();
  await page.locator('.bottom-nav').getByRole('button', { name: '交易', exact: true }).click();
  await expect(page.locator('.trade-summary')).toContainText('3 笔');
  await expect(page.locator('.trade-list .badge.csv')).toHaveCount(2);
  await expect(page.locator('.trade-list')).toContainText('新买入');
});
test('CSV 资金导入：错误行单独列出，仅写入勾选的有效行', async ({ page }) => {
  await page.goto('/');
  await page.locator('.bottom-nav').getByRole('button', { name: '收益', exact: true }).click();
  await page.getByRole('button', { name: '设置期初余额', exact: true }).click();
  await page.getByLabel('日期（美东）').fill('2025-01-01');
  await page.getByLabel('金额（美元）').fill('1000');
  await page.getByRole('button', { name: '保存记录', exact: true }).click();
  await page.getByRole('button', { name: '导入 CSV', exact: true }).click();
  await page.getByRole('radio', { name: '资金记录' }).check();
  const csv = ['Date,Type,Symbol,Amount,Tax,Note',
    '2026-09-10,DEPOSIT,,500,,工资转入',
    '2026-09-11,DIVIDEND,AAPL,120,12,季度分红',
    '2026-09-12,WITHDRAW,,200,,取出',
    'bad-date,FEE,,5,,坏行'].join('\n');
  await page.locator('#csv-file').setInputFiles({ name: 'cash.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) });
  await expect(page.getByTestId('import-summary')).toContainText('共 4 行');
  await expect(page.getByTestId('import-summary')).toContainText('可导入 3');
  await expect(page.getByTestId('import-summary')).toContainText('错误 1');
  await expect(page.locator('.csv-error-row')).toContainText('第 5 行');
  await expect(page.getByRole('button', { name: '确认导入 3 笔', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '确认导入 3 笔', exact: true }).click();
  // 余额 = 1000 + 500 + 108 − 200
  await expect(page.getByTestId('cash-balance')).toHaveText('$1,408.00');
  await expect(page.getByTestId('cash-records')).toContainText('季度分红');
  await expect(page.getByTestId('cash-records')).not.toContainText('坏行');
});
test('导出完整备份包含现金记录，通用备份剔除现金', async ({ page }) => {
  const withCash = {
    ...ledger,
    history: { version: 1, closes: [{ symbol: 'AAPL', price: '100', date: '2025-06-02' }], sessions: ['2025-06-02'], splits: [] },
    cash: {
      opening: { amount: '5000', date: '2025-01-01', note: '期初' },
      records: [{ id: 'c1', sequence: 0, date: '2025-03-01', kind: 'deposit', amount: '1000', note: '', source: 'manual' }],
    },
  };
  await page.addInitScript(data => localStorage.setItem('CapacitorStorage.stock-ledger-v1-0', JSON.stringify({ revision: 1, data })), withCash);
  await page.goto('/');
  await page.locator('.bottom-nav').getByRole('button', { name: '设置', exact: true }).click();
  const dl1 = page.waitForEvent('download');
  await page.getByRole('button', { name: '导出完整备份', exact: true }).click();
  const full = await (await dl1).createReadStream();
  let text = '';
  for await (const chunk of full) text += chunk;
  const parsed = JSON.parse(text);
  expect(parsed.cash?.opening?.amount).toBe('5000');
  expect(parsed.cash?.records).toHaveLength(1);
  const dl2 = page.waitForEvent('download');
  await page.getByRole('button', { name: '导出各版本通用备份', exact: true }).click();
  const compat = JSON.parse(fs.readFileSync(await (await dl2).path(), 'utf-8'));
  expect(compat.cash).toBeUndefined();
  expect(compat.history).toBeUndefined();
});
