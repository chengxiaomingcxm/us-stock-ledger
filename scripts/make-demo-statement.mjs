// Regenerates tests/fixtures/hsbc-investment-statement-demo.pdf
//
// 这份结单**完全虚构**：账户、姓名、日期、股票、数量、价格、金额、费用与分红全部是编造的，
// 与任何真实账户或真实交易无关，只用于 Demo 展示与回归测试。文件本身被标记为
// SAMPLE / DEMONSTRATION ONLY。不要用真实结单替换它。
//
// 为什么要用脚本而不是直接放一个 PDF：结单文本必须能被审阅（diff 里能看清每个字段），
// 且改一个数字后可以重新生成、重新自检，不靠手工编辑二进制。
//
// 用法：node scripts/make-demo-statement.mjs
//
// 自检：脚本写完文件后会**重新从字节里抽回文本层**，并按 `HSBCStatement.parse` 的判定条件
// 重放一遍（账户唯一、charges 段落计数等式、逐行成交校验、分红/费用关联、编号消费完整性）。
// 本机没有 Swift 工具链，这一层是推 CI 之前唯一能本地跑的核对；真正的 Parser 断言在
// tests/native/NativeTests.swift。任何一项不符就以非 0 退出。
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const target = resolve(root, 'tests/fixtures/hsbc-investment-statement-demo.pdf');

// 结单文本：一行一条，`''` 为空行。字段口径对齐 HSBCStatement.swift 的正则要求：
// 图表头 + INVSTM0011 + A/C no 必须存在；成交行是「成交日 交收日 币种 单价 数量[符号] 币种 交收额」，
// 费用通过 OUR REFERENCE 与成交行的 Reference 关联；分红行是「日期 CASH DIVIDEND <代码> … PAID BENEFITS 币种 净额」。
const STATEMENT = [
  'HSBC Investment services - composite statement INVSTM0011',
  'SAMPLE / DEMONSTRATION ONLY',
  'Fictional data - not a real bank statement',
  '',
  'Statement period: 01SEP2026 to 30SEP2026',
  'A/C no : 123-456789-001',
  'Account holder: SAMPLE INVESTOR (fictional)',
  'Reporting currency: USD',
  '',
  'Transaction summary',
  'Securities Securities description',
  'ID Transaction date Unit price Quantity Settlement amount',
  '/Settlement date',
  '',
  'FOREIGN SHARES',
  'AAPL SAMPLE APPLE INC (SHS)',
  '14SEP2026 16SEP2026 USD 198.40000 25 USD 4,961.00',
  'Reference: DEMO001AAPL Type: PUR',
  '21SEP2026 23SEP2026 USD 210.75000 10- USD 2,106.50',
  'Reference: DEMO003AAPL Type: SAL',
  'NVDA SAMPLE NVIDIA CORP (SHS)',
  '15SEP2026 17SEP2026 USD 174.30000 12 USD 2,091.60',
  'Reference: DEMO002NVDA Type: PUR',
  '',
  'UNIT TRUSTS',
  'DEMOETF SAMPLE HONG KONG INDEX FUND (UNT)',
  '15SEP2026 17SEP2026 HKD 40.00000 30 HKD 1,200.00',
  'Reference: DEMO004FUND Type: PUR',
  '',
  'Charges and income summary',
  'Date Charges/income description Charges amount Income amount',
  '',
  '14SEP2026 PURCHASE SAMPLE APPLE INC (SHS)',
  'OUR REFERENCE:DEMO001AAPL',
  'XACT CHARGE USD 1.00',
  '',
  '21SEP2026 SALE SAMPLE APPLE INC (SHS)',
  'OUR REFERENCE:DEMO003AAPL',
  'XACT CHARGE USD 1.00',
  '',
  '16SEP2026 CASH DIVIDEND AAPL',
  'SAMPLE APPLE INC (SHS)',
  'OUR REFERENCE:DEMO005DIV',
  'PAID BENEFITS USD 24.50',
  '',
  '28SEP2026 CASH DIVIDEND MSFT',
  'SAMPLE MICROSOFT CORP (SHS)',
  'OUR REFERENCE:DEMO006DIV',
  'PAID BENEFITS USD 12.20',
  '',
  'Total charges and income USD 2.00 USD 36.70',
  'Exchange rate against HKD : USD 7.8000000',
  '',
  'SAMPLE / DEMONSTRATION ONLY - fictional data, not a real bank statement',
];

// 期望值：改动上面任何一行都必须让它们重新成立。
const EXPECTED = {
  rows: 6,          // 4 笔成交 + 2 笔分红
  selected: 5,      // 非美元基金那一行会被排除
  trades: 4,        // AAPL 买入、AAPL 卖出、NVDA 买入、HKD 基金买入
  usdTrades: 3,
  dividends: 2,
  fees: 2,          // 两条 XACT CHARGE，各关联一笔成交
};

const escape = (text) => text.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');

function buildPdf(lines) {
  const x = 42;
  const top = 800;
  // A4 高 842pt：行距必须让最后一行仍在页面内。行距远大于 3pt 是为了让 PDFKit 的
  // selectionsByLine() 把每一行分开（低于 3pt 会被合进同一行）。
  const leading = 14;
  if (top - (lines.length - 1) * leading < 20) {
    throw new Error('buildPdf: statement no longer fits on one page');
  }
  const content = lines
    .map((line, index) => `BT /F1 10 Tf 1 0 0 1 ${x} ${(top - index * leading).toFixed(2)} Tm (${escape(line)}) Tj ET`)
    .join('\n');

  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      + '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(content, 'latin1')} >>\nstream\n${content}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Title (SAMPLE demo statement fixture - fictional data) '
      + '/Subject (Synthetic HSBC-format statement for demo and regression tests) '
      + '/Keywords (SAMPLE, DEMONSTRATION ONLY, fictional) /Creator (stock-ledger) '
      + '/Producer (scripts/make-demo-statement.mjs) /CreationDate (D:20260920000000Z) >>',
  ];

  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objects.forEach((body, index) => {
    offsets.push(Buffer.byteLength(pdf, 'latin1'));
    pdf += `${index + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = Buffer.byteLength(pdf, 'latin1');
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Info 6 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

// 只认自己写出去的那种内容流：一行一个 Tm/Tj。既能确认文字确实以文本层存在（不是图片），
// 也能确认行的 y 间距够 PDFKit 的 selectionsByLine() 分开。
function extractLines(bytes) {
  const raw = bytes.toString('latin1');
  const start = raw.indexOf('stream\n') + 'stream\n'.length;
  const end = raw.indexOf('\nendstream');
  if (start <= 0 || end < 0) throw new Error('extract: content stream not found');
  const pattern = /1 0 0 1 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) Tm \(((?:[^()\\]|\\.)*)\) Tj/g;
  const found = [];
  for (const match of raw.slice(start, end).matchAll(pattern)) {
    found.push({ x: Number(match[1]), y: Number(match[2]), text: match[3].replace(/\\([()\\])/g, '$1') });
  }
  // PDFKit 按 midY 从大到小、同线内按 minX 拼接。坐标拒绝负值：排序错误曾让末尾几行落到
  // 页面外（y 为负）、静默少抽几行，而自检恰好没被覆盖到——这里把它变成硬错误。
  for (const line of found) {
    if (!(line.x >= 0) || !(line.y >= 0)) throw new Error(`extract: text placed outside the page at y=${line.y}`);
  }
  return found.sort((a, b) => b.y - a.y || a.x - b.x).map((line) => line.text);
}

const RE = {
  account: /A\/C\s*no[^\d\r\n]{0,40}(\d{3}-\d{6}-\d{3})/gi,
  charge: /OUR\s+REFERENCE\s*:\s*([A-Z0-9]+)\s+XACT\s+CHARGE\s+([A-Z]{3})\s+([\d,.]+)/gi,
  dividend: /(\d{2}[A-Z]{3}\d{4})\s+CASH\s+DIVIDEND\s+([A-Z][A-Z0-9.\-]*)\s+.*?OUR\s+REFERENCE\s*:\s*([A-Z0-9]+)\s+PAID\s+BENEFITS\s+([A-Z]{3})\s+([\d,.]+)/gi,
  symbol: /^\s*([A-Z][A-Z0-9.\-]{0,14})[ \t]+[^\r\n]*?\((SHS|UNT)\)/gm,
  symbolCursor: /^\s*([A-Z][A-Z0-9.\-]{0,14})[ \t]+[^\r\n]*?\((SHS|UNT)\)/m,
  record: /(\d{2}[A-Z]{3}\d{4})\s+(\d{2}[A-Z]{3}\d{4})\s+([A-Z]{3})\s+([\d,.]+)\s+([\d,.]+)\s*(-?)\s+([A-Z]{3})\s+([\d,.]+)\s+Reference\s*:\s*([A-Z0-9]+)\s+Type\s*:\s*(PUR|SAL)\b/gi,
  reference: /Reference\s*:\s*([A-Z0-9]+)\s+Type\s*:/gi,
  datedRow: /\d{2}[A-Z]{3}\d{4}\s+\d{2}[A-Z]{3}\d{4}\s+[A-Z]{3}/gi,
  entry: /\b[A-Z]{3}\s+[\d,]+\.\d{2}\b/gi,
  known: /(?:PAID\s+BENEFITS|XACT\s+CHARGE)\s+[A-Z]{3}\s+[\d,]+\.\d{2}\b/gi,
  totals: /Total\s+charges\s+and\s+income\s+[A-Z]{3}\s+[\d,]+\.\d{2}\s+[A-Z]{3}\s+[\d,]+\.\d{2}/gi,
};

const matches = (pattern, text) => [...text.matchAll(pattern)].map((match) => [...match]);
const collapse = (text) => text.replace(/\s+/g, ' ');
const money = (text) => Number(text.replace(/,/g, ''));
const date = (text) => {
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  const month = months.indexOf(text.slice(2, 5).toUpperCase()) + 1;
  if (month === 0) throw new Error(`date: bad month in ${text}`);
  return `${text.slice(5)}-${String(month).padStart(2, '0')}-${text.slice(0, 2)}`;
};

// 按 HSBCStatement.parse 的判定顺序重放。任何一条不成立都说明 fixture 与 Parser 脱节。
function verify(pages) {
  const problems = [];
  const expect = (condition, message) => { if (!condition) problems.push(message); };

  expect(pages.length === 1, `expected a single page, got ${pages.length}`);
  const whole = pages.join('\n');
  expect(whole.includes('HSBC') && whole.includes('INVSTM0011'), 'header gate: HSBC + INVSTM0011');
  expect(whole.includes('SAMPLE / DEMONSTRATION ONLY'), 'demo marking must be present');

  const accounts = matches(RE.account, whole).map((match) => match[1]);
  expect(accounts.length > 0 && new Set(accounts).size === 1, `exactly one account, got ${JSON.stringify(accounts)}`);

  const flat = collapse(whole);

  // 每一页的 Charges and income summary 都必须满足 entries == known + totals * 2。
  for (const page of pages) {
    const section = page.split('Charges and income summary').slice(1)[0];
    if (section === undefined) continue;
    const text = collapse(section);
    const entries = matches(RE.entry, text).length;
    const known = matches(RE.known, text).length;
    const totals = matches(RE.totals, text).length;
    expect(entries === known + totals * 2, `charges section: entries ${entries} != known ${known} + totals ${totals} * 2`);
  }

  const charges = matches(RE.charge, flat);
  const feeByReference = new Map();
  for (const charge of charges) {
    const key = charge[1].toUpperCase();
    expect(!feeByReference.has(key), `duplicate charge reference ${key}`);
    if (charge[2].toUpperCase() !== 'USD') continue;
    feeByReference.set(key, money(charge[3]));
  }

  const consumed = new Set();
  const seen = new Set();
  const rows = [];
  for (const page of pages) {
    const sections = page.split('Transaction summary').slice(1);
    for (const section of sections) {
      const body = section.split('Charges and income summary')[0];
      const symbols = matches(RE.symbol, body);
      let remaining = body;
      for (const symbol of symbols) {
        const at = remaining.indexOf(symbol[0]);
        if (at < 0) continue;
        remaining = remaining.slice(at + symbol[0].length);
        const next = remaining.search(RE.symbolCursor);
        const block = collapse(next < 0 ? remaining : remaining.slice(0, next));
        for (const record of matches(RE.record, block)) {
          const reference = record[9].toUpperCase();
          const id = `hsbc:<hash>:${reference}`;
          expect(!seen.has(id), `duplicate trade reference ${reference}`);
          seen.add(id);
          const side = record[10].toUpperCase() === 'PUR' ? 'buy' : 'sell';
          expect((side === 'sell') === (record[6] === '-'), `${reference}: quantity sign does not match ${side}`);
          expect(record[3] === record[7], `${reference}: currencies differ`);
          const tradeDate = date(record[1]);
          const settlementDate = date(record[2]);
          expect(settlementDate >= tradeDate, `${reference}: settlement ${settlementDate} before trade ${tradeDate}`);
          const price = money(record[4]);
          const quantity = money(record[5]);
          const settlement = money(record[8]);
          expect(price > 0 && quantity > 0 && settlement > 0, `${reference}: non-positive price/quantity/settlement`);
          const fee = feeByReference.get(reference) ?? 0;
          const expected = side === 'buy' ? price * quantity + fee : price * quantity - fee;
          expect(Math.abs(expected - settlement) <= 0.005,
            `${reference}: ${price} x ${quantity} ${side} ${fee} = ${expected.toFixed(2)} != settlement ${settlement}`);
          consumed.add(reference);
          rows.push({ id, kind: 'trade', symbol: symbol[1].toUpperCase(), side, fee,
            currency: record[3].toUpperCase(), unit: symbol[2].toUpperCase(), tradeDate, settlementDate, quantity, price, settlement });
        }
      }
      const references = matches(RE.reference, body).map((match) => match[1].toUpperCase());
      const datedRows = matches(RE.datedRow, body).length;
      expect(datedRows === references.length, `transaction section: ${datedRows} dated rows vs ${references.length} references`);
      references.forEach((reference) => expect(consumed.has(reference), `reference ${reference} was not parsed as a trade`));
    }
  }

  const dividends = matches(RE.dividend, flat);
  for (const dividend of dividends) {
    const id = `hsbc:<hash>:${dividend[3].toUpperCase()}`;
    expect(!seen.has(id), `duplicate dividend reference ${dividend[3]}`);
    seen.add(id);
    const net = money(dividend[5]);
    expect(net > 0, `${dividend[3]}: net ${net} must be positive`);
    rows.push({ id, kind: 'dividend', symbol: dividend[2].toUpperCase(), amount: net, currency: dividend[4].toUpperCase() });
  }

  expect(matches(/CASH\s+DIVIDEND/gi, flat).length === dividends.length, 'every CASH DIVIDEND line must be parsed');
  expect(matches(/XACT\s+CHARGE/gi, flat).length === charges.length, 'every XACT CHARGE line must be parsed');
  [...feeByReference.keys()].forEach((key) => expect(consumed.has(key), `charge ${key} is not linked to a trade`));

  for (const row of rows) {
    row.excluded = row.kind === 'trade'
      ? row.currency !== 'USD' || row.unit !== 'SHS'
      : row.currency !== 'USD';
    row.selected = !row.excluded;
  }
  const selected = rows.filter((row) => row.selected);
  const usdTrades = selected.filter((row) => row.kind === 'trade');
  const selectedDividends = selected.filter((row) => row.kind === 'dividend');

  expect(rows.length === EXPECTED.rows, `rows ${rows.length} != ${EXPECTED.rows}`);
  expect(selected.length === EXPECTED.selected, `selected ${selected.length} != ${EXPECTED.selected}`);
  expect(rows.filter((row) => row.kind === 'trade').length === EXPECTED.trades, 'trade count');
  expect(usdTrades.length === EXPECTED.usdTrades, 'usd trade count');
  expect(selectedDividends.length === EXPECTED.dividends, 'dividend count');
  expect(feeByReference.size === EXPECTED.fees, 'linked fee count');

  return { rows, selected, usdTrades, selectedDividends, accounts, feeByReference };
}

const bytes = buildPdf(STATEMENT);
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, bytes);

const extracted = extractLines(readFileSync(target));
const result = verify([extracted.join('\n')]);
if (extracted.length !== STATEMENT.length) {
  throw new Error(`extract: ${extracted.length} lines recovered, statement has ${STATEMENT.length}`);
}
if (extracted[extracted.length - 1] !== STATEMENT[STATEMENT.length - 1]) {
  throw new Error('extract: last line does not round-trip');
}

console.log(`wrote ${target} (${bytes.length} bytes, ${extracted.length} text lines)`);
console.log(`parsed: rows=${result.rows.length} selected=${result.selected.length} `
  + `trades=${result.usdTrades.length} dividends=${result.selectedDividends.length} fees=${result.feeByReference.size}`);
console.log(`account in fixture: ${result.accounts[0]} (fictional)`);
console.log('--- extracted text layer ---');
console.log(extracted.join('\n'));
console.log('--- self-check against HSBCStatement.parse rules ---');
console.log('FIXTURE SELF-CHECK PASSED');
