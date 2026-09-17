import { D, isSymbolText, validDate, validateLedger, type CashKind, type CashRecord, type Ledger, type Trade } from './ledger';

// 1.26：券商 CSV 导入。支持带表头的交易 / 资金流水 CSV，先字段映射、再预览、去重、确认写入。

export interface CsvTable { header: string[]; rows: string[][] }

const NORM = (s: string) => s.toLowerCase().replace(/[\s_\-()（）【】\[\].:：]+/g, '');
const cleanNum = (s: string) => s.trim().replace(/^usd\s*/i, '').replace(/[\s,$，]/g, '');
const normalizeText = (s: string) => s.trim().replace(/\s+/g, '').toLowerCase();

function parseDelimited(line: string, delim: string): string[] {
  const out: string[] = []; let cur = '', inQ = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQ) {
      if (c === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; } else inQ = false;
      } else cur += c;
    } else if (c === '"') inQ = true;
    else if (c === delim) { out.push(cur); cur = ''; }
    else cur += c;
  }
  if (inQ) throw new Error('引号未闭合，请检查 CSV 文件。');
  out.push(cur);
  return out.map(f => f.trim());
}

export function parseCsv(text: string): CsvTable {
  if (text.length > 2_000_000) throw new Error('文件过大，请选择 2 MB 以内的 CSV。');
  let body = text.replace(/^\uFEFF/, '');
  const lines = body.split(/\r\n|\r|\n/).filter(l => l.trim() !== '');
  if (!lines.length) throw new Error('文件没有内容。');
  let delim = ',';
  let best = 0;
  for (const line of lines.slice(0, 10)) {
    let inQ = false;
    const counts = [0, 0, 0];
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c === '"') { if (inQ && line[i + 1] === '"') i++; else inQ = !inQ; continue; }
      if (inQ) continue;
      if (c === ',') counts[0]++;
      else if (c === ';') counts[1]++;
      else if (c === '\t') counts[2]++;
    }
    const max = Math.max(...counts);
    if (max > best) {
      best = max;
      delim = counts[0] === max ? ',' : counts[1] === max ? ';' : '\t';
    }
  }
  if (best === 0) throw new Error('没有找到表头分隔符，请使用逗号、分号或制表符分隔的 CSV。');
  const header = parseDelimited(lines[0], delim);
  if (header.length < 2 || header.every(h => h === '')) throw new Error('缺少表头行。');
  const rows: string[][] = [];
  for (const line of lines.slice(1)) {
    if (rows.length >= 5000) throw new Error('最多导入 5,000 行，请拆分文件。');
    const fields = parseDelimited(line, delim);
    if (fields.length !== header.length) throw new Error(`第 ${rows.length + 2} 行列数与表头不一致（${fields.length} 列）。`);
    if (fields.every(f => f === '')) continue;
    rows.push(fields);
  }
  if (!rows.length) throw new Error('表头之外没有数据行。');
  return { header, rows };
}

export type TradeField = 'date' | 'symbol' | 'side' | 'quantity' | 'price' | 'fee' | 'note' | 'currency';
export type CashField = 'date' | 'type' | 'symbol' | 'amount' | 'tax' | 'note';
export type Mapping<T extends string> = Partial<Record<T, number>>;
export const tradeFieldLabels: Record<TradeField, string> = { date: '日期', symbol: '代码', side: '方向', quantity: '数量', price: '单价', fee: '手续费', note: '备注', currency: '币种' };
export const cashFieldLabels: Record<CashField, string> = { date: '日期', type: '类型', symbol: '代码', amount: '金额', tax: '税费', note: '备注' };
export const tradeFields = Object.keys(tradeFieldLabels) as TradeField[];
export const cashFields = Object.keys(cashFieldLabels) as CashField[];

export const TRADE_ALIASES: Record<TradeField, string[]> = {
  date: ['date', 'tradedate', '交易日期', '成交日期', '日期', '时间', 'time', 'datetime'],
  symbol: ['symbol', 'ticker', 'code', 'stockcode', '证券代码', '股票代码', '代码', '标的', '标的代码'],
  side: ['side', 'direction', 'action', 'buysell', '买卖', '方向', '交易方向', '操作', 'type', '交易类型'],
  quantity: ['quantity', 'qty', 'shares', '成交数量', '数量', '股数', '成交股数'],
  price: ['price', 'tradeprice', '成交价', '成交价格', '成交单价', '价格', '均价', 'avgprice'],
  fee: ['fee', 'commission', 'fees', '手续费', '佣金', '费用', '交易费用'],
  note: ['note', 'notes', 'memo', 'remark', '备注', '说明'],
  currency: ['currency', 'ccy', '币种', '货币', '结算币种'],
};
export const CASH_ALIASES: Record<CashField, string[]> = {
  date: ['date', 'tradedate', '交易日期', '成交日期', '日期', '时间', 'time', 'datetime'],
  type: ['type', 'kind', 'cashflowtype', '资金类型', '类型', '方向', 'action', '操作'],
  symbol: ['symbol', 'ticker', 'code', 'stockcode', '证券代码', '股票代码', '代码', '标的', '标的代码'],
  amount: ['amount', 'cashamount', '发生金额', '金额', '资金', 'value', '成交金额'],
  tax: ['tax', 'withholding', 'withholdingtax', '预扣税', '税费', '预扣税费'],
  note: ['note', 'notes', 'memo', 'remark', '备注', '说明'],
};

export function autoMap<T extends string>(header: string[], fields: T[], aliases: Record<T, string[]>): Mapping<T> {
  const used = new Set<number>();
  const map: Mapping<T> = {};
  for (const field of fields) {
    const idx = header.findIndex((h, i) => !used.has(i) && aliases[field].some(a => NORM(a) === NORM(h)));
    if (idx >= 0) { map[field] = idx; used.add(idx); }
  }
  return map;
}

const SIDE_VALUES: Record<string, 'buy' | 'sell'> = { buy: 'buy', b: 'buy', 买入: 'buy', 买: 'buy', sell: 'sell', s: 'sell', 卖出: 'sell', 卖: 'sell' };
const KIND_VALUES: Record<string, CashKind> = {
  deposit: 'deposit', d: 'deposit', 入金: 'deposit', 转入: 'deposit', 存入: 'deposit', 存款: 'deposit', transferin: 'deposit',
  withdraw: 'withdraw', w: 'withdraw', 出金: 'withdraw', 转出: 'withdraw', 取出: 'withdraw', 提款: 'withdraw', transferout: 'withdraw',
  dividend: 'dividend', div: 'dividend', 分红: 'dividend', 股息: 'dividend', interest: 'dividend', 利息: 'dividend',
  fee: 'fee', f: 'fee', 费用: 'fee', 账户费用: 'fee', 利息支出: 'fee', 服务费: 'fee', 管理费: 'fee',
};

function parseDateField(s: string): string {
  const t = s.trim().slice(0, 19);
  const m = t.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/) ?? t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/);
  if (!m) throw new Error('日期无效');
  let y: string, mo: string, d: string;
  if (m[1].length === 4) { y = m[1]; mo = m[2]; d = m[3]; } else { mo = m[1]; d = m[2]; y = m[3]; }
  try { return validDate(`${y}-${mo.padStart(2, '0')}-${d.padStart(2, '0')}`); } catch { throw new Error('日期无效或晚于今天'); }
}

function parseNumberField(s: string, label: string, positive: boolean, allowZero = false): string {
  const c = cleanNum(s);
  if (!/^\d+(\.\d+)?$/.test(c)) throw new Error(`${label}无效`);
  const d = D(c);
  if (positive && !d.gt(0)) throw new Error(`${label}必须大于 0`);
  if (!positive && allowZero && d.lt(0)) throw new Error(`${label}不能为负`);
  return d.toFixed();
}

function parseSymbol(s: string): string {
  const sym = s.trim().toUpperCase();
  if (!isSymbolText(sym)) throw new Error('代码无效');
  return sym;
}

function checkCurrency(s: string): void {
  const c = normalizeText(s);
  if (c && !['usd', '美元', '美金', '$', 'us$'].includes(c)) throw new Error('仅支持美元交易');
}

function colOf<T extends string>(cells: string[], mapping: Mapping<T>, field: T): { value?: string; idx?: number } {
  const idx = mapping[field];
  return idx === undefined ? {} : { value: (cells[idx] ?? '').trim(), idx };
}

export interface RowError { line: number; reason: string }
export interface TradeRow { line: number; trade: Trade; duplicate: boolean }
export interface TradeImport { mapping: Mapping<TradeField>; rows: TradeRow[]; errors: RowError[]; total: number }
export interface CashRow { line: number; record: CashRecord; duplicate: boolean }
export interface CashImport { mapping: Mapping<CashField>; fallbackKind: CashKind; rows: CashRow[]; errors: RowError[]; total: number }

const tradeKey = (t: Pick<Trade, 'date' | 'symbol' | 'side' | 'quantity' | 'price'>) => `${t.date}|${t.symbol}|${t.side}|${t.quantity}|${t.price}`;

export function analyzeTradeCsv(table: CsvTable, mapping: Mapping<TradeField>, existing: Ledger): TradeImport {
  const seen = new Set(existing.trades.map(tradeKey));
  const rows: TradeRow[] = []; const errors: RowError[] = [];
  table.rows.forEach((cells, i) => {
    const line = i + 2;
    try {
      const date = colOf(cells, mapping, 'date');
      if (date.value === undefined) throw new Error('未选择日期列');
      const symbol = colOf(cells, mapping, 'symbol');
      if (symbol.value === undefined) throw new Error('未选择代码列');
      const side = colOf(cells, mapping, 'side');
      if (side.value === undefined) throw new Error('未选择方向列');
      const quantity = colOf(cells, mapping, 'quantity');
      if (quantity.value === undefined) throw new Error('未选择数量列');
      const price = colOf(cells, mapping, 'price');
      if (price.value === undefined) throw new Error('未选择单价列');
      const currency = colOf(cells, mapping, 'currency');
      if (currency.value !== undefined) checkCurrency(currency.value);
      const sideNorm = normalizeText(side.value!);
      const dir = SIDE_VALUES[sideNorm];
      if (!dir) throw new Error('方向只能是买入 / 卖出');
      const trade: Trade = {
        id: '', sequence: 0,
        symbol: parseSymbol(symbol.value!),
        side: dir,
        date: parseDateField(date.value!),
        quantity: parseNumberField(quantity.value!, '数量', true),
        price: parseNumberField(price.value!, '单价', true),
        fee: colOf(cells, mapping, 'fee').value ? parseNumberField(colOf(cells, mapping, 'fee').value!, '手续费', false, true) : '0',
        note: colOf(cells, mapping, 'note').value ?? '',
        source: 'import',
      };
      const k = tradeKey(trade);
      const duplicate = seen.has(k);
      seen.add(k);
      rows.push({ line, trade, duplicate });
    } catch (e) {
      errors.push({ line, reason: e instanceof Error ? e.message : '解析失败' });
    }
  });
  return { mapping, rows, errors, total: table.rows.length };
}

const cashKey = (r: Pick<CashRecord, 'date' | 'kind' | 'symbol' | 'amount' | 'tax'>) => `${r.date}|${r.kind}|${r.symbol ?? ''}|${r.amount}|${r.tax ?? '0'}`;

export function analyzeCashCsv(table: CsvTable, mapping: Mapping<CashField>, fallbackKind: CashKind, existing: Ledger): CashImport {
  const seen = new Set((existing.cash?.records ?? []).map(cashKey));
  const rows: CashRow[] = []; const errors: RowError[] = [];
  table.rows.forEach((cells, i) => {
    const line = i + 2;
    try {
      const date = colOf(cells, mapping, 'date');
      if (date.value === undefined) throw new Error('未选择日期列');
      const type = colOf(cells, mapping, 'type');
      const kind = type.value === undefined ? fallbackKind : (KIND_VALUES[normalizeText(type.value)] ?? (() => { throw new Error('资金类型无法识别'); })());
      const amount = colOf(cells, mapping, 'amount');
      if (amount.value === undefined) throw new Error('未选择金额列');
      const symbol = colOf(cells, mapping, 'symbol');
      const sym = symbol.value ? parseSymbol(symbol.value) : undefined;
      if (sym && kind !== 'dividend' && kind !== 'fee') throw new Error('只有分红和费用记录可以关联股票');
      const amountV = parseNumberField(amount.value!, '金额', true);
      const tax = colOf(cells, mapping, 'tax');
      let taxV: string | undefined;
      if (tax.value) {
        if (kind !== 'dividend') throw new Error('只有分红记录可以填写税费');
        taxV = parseNumberField(tax.value, '税费', false, true);
        if (D(taxV).gt(amountV)) throw new Error('税费不能超过分红金额');
      }
      const record: CashRecord = {
        id: '', sequence: 0,
        date: parseDateField(date.value!),
        kind,
        amount: amountV,
        tax: taxV,
        symbol: sym,
        note: colOf(cells, mapping, 'note').value ?? '',
        source: 'import',
      };
      const k = cashKey(record);
      const duplicate = seen.has(k);
      seen.add(k);
      rows.push({ line, record, duplicate });
    } catch (e) {
      errors.push({ line, reason: e instanceof Error ? e.message : '解析失败' });
    }
  });
  return { mapping, fallbackKind, rows, errors, total: table.rows.length };
}

export function applyTradeImport(data: Ledger, trades: Trade[], newId: () => string): Ledger {
  if (!trades.length) return data;
  const seqStart = data.trades.reduce((m, t) => Math.max(m, t.sequence), -1) + 1;
  const added = trades.map((t, i) => ({ ...t, id: t.id || newId(), sequence: seqStart + i }));
  return validateLedgerSafe({ ...data, trades: [...data.trades, ...added] });
}

export function applyCashImport(data: Ledger, records: CashRecord[], newId: () => string): Ledger {
  if (!records.length) return data;
  const seqStart = (data.cash?.records ?? []).reduce((m, r) => Math.max(m, r.sequence), -1) + 1;
  const added = records.map((r, i) => ({ ...r, id: r.id || newId(), sequence: seqStart + i }));
  return validateLedgerSafe({ ...data, cash: { ...data.cash, records: [...(data.cash?.records ?? []), ...added] } });
}

function validateLedgerSafe(data: Ledger): Ledger {
  try { return validateLedger(data); } catch (e) { throw new Error(`导入后账本无法通过校验：${e instanceof Error ? e.message : '数据无效'}。当前账本未改变。`); }
}

export const csvTemplate = `Date,Symbol,Side,Quantity,Price,Fee,Note
2026-09-10,AAPL,BUY,10,220.5,1,分批建仓
2026-09-11,MSFT,SELL,2,390,1,部分止盈`;
export const cashCsvTemplate = `Date,Type,Symbol,Amount,Tax,Note
2026-09-10,DEPOSIT,,2000,,工资转入
2026-09-11,DIVIDEND,AAPL,120,12,季度分红`;
