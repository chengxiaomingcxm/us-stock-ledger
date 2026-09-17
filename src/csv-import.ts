import { D, isSymbolText, numberText, validDate, validateLedger, type CashKind, type CashRecord, type Ledger, type Trade } from './ledger';

// 1.26：券商 CSV 导入。带表头，字符级解析（引号内可含换行，保留真实行号）；
// 字段映射 → 逐行校验 → 疑似重复/已导入去重 → 批校验 → 用户确认后写入。

export interface CsvTable { header: string[]; rows: { line: number; cells: string[] }[] }

const NORM = (s: string) => s.toLowerCase().replace(/[\s_\-()（）【】\[\].:：]+/g, '');
const normalizeText = (s: string) => s.trim().replace(/\s+/g, '').toLowerCase();

function detectDelim(line: string): string {
  let inQ = false; const counts = [0, 0, 0];
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') { if (inQ && line[i + 1] === '"') i++; else inQ = !inQ; continue; }
    if (inQ) continue;
    if (c === ',') counts[0]++; else if (c === ';') counts[1]++; else if (c === '\t') counts[2]++;
  }
  const max = Math.max(...counts);
  if (max === 0) throw new Error('没有找到表头分隔符，请使用逗号、分号或制表符分隔的 CSV。');
  return counts[0] === max ? ',' : counts[1] === max ? ';' : '\t';
}

export function parseCsv(text: string): CsvTable {
  if (text.length > 2_000_000) throw new Error('文件过大，请选择 2 MB 以内的 CSV。');
  const s = text.replace(/^\uFEFF/, '');
  if (!s.trim()) throw new Error('文件没有内容。');
  const firstEnd = s.search(/\r\n|\r|\n/);
  const delim = detectDelim(firstEnd === -1 ? s : s.slice(0, firstEnd));
  const raw: { line: number; cells: string[] }[] = [];
  let lineNo = 1;
  let row = { line: 1, cells: [] as string[] };
  let cur = '', inQ = false;
  const pushField = () => { row.cells.push(cur.trim()); cur = ''; };
  const endRow = () => { pushField(); if (row.cells.some(x => x !== '')) raw.push(row); row = { line: lineNo, cells: [] }; };
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inQ) {
      if (c === '"') { if (s[i + 1] === '"') { cur += '"'; i++; } else inQ = false; }
      else if (c === '\n' || c === '\r') { if (c === '\r' && s[i + 1] === '\n') i++; cur += '\n'; lineNo++; }
      else cur += c;
    } else if (c === '"') inQ = true;
    else if (c === delim) pushField();
    else if (c === '\n' || c === '\r') { if (c === '\r' && s[i + 1] === '\n') i++; lineNo++; endRow(); }
    else cur += c;
  }
  if (inQ) throw new Error('引号未闭合，请检查 CSV 文件。');
  endRow();
  if (!raw.length) throw new Error('文件没有内容。');
  const header = raw[0].cells;
  if (header.length < 2 || header.every(h => h === '')) throw new Error('缺少表头行。');
  const rows: { line: number; cells: string[] }[] = [];
  for (const r of raw.slice(1)) {
    if (rows.length >= 5000) throw new Error('最多导入 5,000 行，请拆分文件。');
    if (r.cells.length !== header.length) throw new Error(`第 ${r.line} 行列数与表头不一致（${r.cells.length} 列）。`);
    rows.push(r);
  }
  if (!rows.length) throw new Error('表头之外没有数据行。');
  return { header, rows };
}

export function decodeCsvBytes(buf: ArrayBuffer | Uint8Array): { text: string; encoding: string } {
  const u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  try {
    if (u8.length >= 2 && u8[0] === 0xff && u8[1] === 0xfe) return { text: new TextDecoder('utf-16le', { fatal: true }).decode(u8), encoding: 'UTF-16 LE' };
    if (u8.length >= 2 && u8[0] === 0xfe && u8[1] === 0xff) return { text: new TextDecoder('utf-16be', { fatal: true }).decode(u8), encoding: 'UTF-16 BE' };
  } catch { throw new Error('文件编码无法识别（UTF-16 字节不完整）。请把文件另存为 UTF-8 后再导入。'); }
  try { return { text: new TextDecoder('utf-8', { fatal: true }).decode(u8), encoding: 'UTF-8' }; } catch { /* 不是合法 UTF-8 */ }
  try {
    const text = new TextDecoder('gbk').decode(u8);
    if (!text.includes('\uFFFD')) return { text, encoding: 'GBK' };
  } catch { /* 运行环境不支持 GBK 解码 */ }
  throw new Error('文件编码无法识别（支持 UTF-8、UTF-8 BOM、UTF-16 和 GBK）。请把文件另存为 UTF-8 后再导入。');
}

export type TradeField = 'date' | 'symbol' | 'side' | 'quantity' | 'price' | 'fee' | 'note' | 'currency' | 'id';
export type CashField = 'date' | 'type' | 'symbol' | 'amount' | 'tax' | 'note' | 'currency' | 'id';
export type Mapping<T extends string> = Partial<Record<T, number>>;
export const tradeFieldLabels: Record<TradeField, string> = { date: '日期', symbol: '代码', side: '方向', quantity: '数量', price: '单价', fee: '手续费', note: '备注', currency: '币种', id: '券商编号' };
export const cashFieldLabels: Record<CashField, string> = { date: '日期', type: '类型', symbol: '代码', amount: '金额', tax: '税费', note: '备注', currency: '币种', id: '流水编号' };
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
  id: ['tradeid', 'executionid', 'transactionid', '成交编号', '成交单号', '流水号'],
};
export const CASH_ALIASES: Record<CashField, string[]> = {
  date: ['date', 'tradedate', '交易日期', '成交日期', '日期', '时间', 'time', 'datetime'],
  type: ['type', 'kind', 'cashflowtype', '资金类型', '类型', '方向', 'action', '操作'],
  symbol: ['symbol', 'ticker', 'code', 'stockcode', '证券代码', '股票代码', '代码', '标的', '标的代码'],
  amount: ['amount', 'cashamount', '发生金额', '金额', '资金', 'value', '成交金额'],
  tax: ['tax', 'withholding', 'withholdingtax', '预扣税', '税费', '预扣税费'],
  note: ['note', 'notes', 'memo', 'remark', '备注', '说明'],
  currency: ['currency', 'ccy', '币种', '货币', '结算币种'],
  id: ['id', 'cashflowid', 'flowid', '流水号', '流水编号', '记录编号', 'transactionid'],
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

function parseNumberField(s: string, label: string, positive: boolean): string {
  const t = s.trim().replace(/^usd\s*/i, '').replace(/^\$/, '');
  if (!t) throw new Error(`${label}无效`);
  if (!/^\d+(\.\d+)?$/.test(t) && !/^\d{1,3}(,\d{3})*(\.\d+)?$/.test(t)) throw new Error(`${label}格式无效（示例：1,234.56 或 1234.56，不接受小数逗号或空格分隔）`);
  const plain = t.replace(/,/g, '');
  try { return numberText(plain, label, positive); } catch (e) { throw new Error(e instanceof Error ? e.message : `${label}无效`); }
}

export function parseTradeDateTime(s: string): { date: string; time?: string } {
  const t = s.trim();
  let m = t.match(/^(\d{4})[-/ .](\d{1,2})[-/ .](\d{1,2})/);
  let dateStr: string;
  if (m) dateStr = `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
  else {
    m = t.match(/^(\d{1,2})[-/ .](\d{1,2})[-/ .](\d{4})/);
    if (!m) throw new Error('日期无效');
    dateStr = `${m[3]}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`;
  }
  let time: string | undefined;
  const rest = t.slice(m[0].length);
  if (rest) {
    if (/^[ T].*[Zz]$/.test(rest) || /^[ T][^\n]*[+-]\d{2}:?\d{2}$/.test(rest)) throw new Error('暂不支持带时区后缀的成交时间，请使用美东本地时间（如 09:30:00）');
    const tm = rest.match(/^[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d{1,6})?$/);
    if (!tm) throw new Error('日期后只能跟合法时间（例如 2026-09-11 09:30:00），多余字符无效');
    if (+tm[1] > 23 || +tm[2] > 59 || (tm[3] !== undefined && +tm[3] > 59)) throw new Error('时间无效');
    time = `${tm[1]}:${tm[2]}${tm[3] ? ':' + tm[3] : ''}`;
  }
  try { return { date: validDate(dateStr), time }; } catch { throw new Error('日期无效或晚于今天'); }
}

function parseSymbol(s: string): string {
  const sym = s.trim().toUpperCase();
  if (!isSymbolText(sym)) throw new Error('代码无效');
  return sym;
}

function checkCurrency(s: string): void {
  const c = normalizeText(s);
  if (c && !['usd', '美元', '美金', '$', 'us$'].includes(c)) throw new Error('仅支持美元，其他币种不会按汇率换算');
}

function colOf<T extends string>(cells: string[], mapping: Mapping<T>, field: T): { value?: string; idx?: number } {
  const idx = mapping[field];
  return idx === undefined ? {} : { value: (cells[idx] ?? '').trim(), idx };
}

export interface RowError { line: number; reason: string }
export type RowStatus = 'new' | 'suspected' | 'duplicate';
export interface TradeRow { line: number; trade: Trade; time?: string; status: RowStatus }
export interface TradeImport { mapping: Mapping<TradeField>; rows: TradeRow[]; errors: RowError[]; total: number; batchError?: string; orderAmbiguous: boolean; sameDayMixed: boolean }
export interface CashRow { line: number; record: CashRecord; status: RowStatus }
export interface CashImport { mapping: Mapping<CashField>; fallbackKind?: CashKind; rows: CashRow[]; errors: RowError[]; total: number; batchError?: string }

const tradeKey = (t: Pick<Trade, 'date' | 'symbol' | 'side' | 'quantity' | 'price' | 'fee'>) => `${t.date}|${t.symbol}|${t.side}|${t.quantity}|${t.price}|${t.fee}`;

function batchValidate(data: Ledger): string | undefined {
  try {
    validateLedger(data);
    return undefined;
  } catch (e) {
    return e instanceof Error ? e.message : '批量校验失败';
  }
}

export function analyzeTradeCsv(table: CsvTable, mapping: Mapping<TradeField>, existing: Ledger): TradeImport {
  const existingExt = new Set(existing.trades.filter(t => t.externalId).map(t => t.externalId!));
  const seenValues = new Set(existing.trades.map(tradeKey));
  const fileExt = new Set<string>();
  const rows: TradeRow[] = []; const errors: RowError[] = [];
  for (const { line, cells } of table.rows) {
    try {
      const dateCol = colOf(cells, mapping, 'date');
      if (dateCol.value === undefined) throw new Error('未选择日期列');
      const symbolCol = colOf(cells, mapping, 'symbol');
      if (symbolCol.value === undefined) throw new Error('未选择代码列');
      const sideCol = colOf(cells, mapping, 'side');
      if (sideCol.value === undefined) throw new Error('未选择方向列');
      const quantityCol = colOf(cells, mapping, 'quantity');
      if (quantityCol.value === undefined) throw new Error('未选择数量列');
      const priceCol = colOf(cells, mapping, 'price');
      if (priceCol.value === undefined) throw new Error('未选择单价列');
      const currencyCol = colOf(cells, mapping, 'currency');
      if (currencyCol.value) checkCurrency(currencyCol.value);
      const note = colOf(cells, mapping, 'note').value ?? '';
      if (note.length > 500) throw new Error('备注过长（最多 500 字）');
      const sideNorm = normalizeText(sideCol.value!);
      const dir = SIDE_VALUES[sideNorm];
      if (!dir) throw new Error('方向只能是买入 / 卖出');
      const { date, time } = parseTradeDateTime(dateCol.value!);
      const extCol = colOf(cells, mapping, 'id');
      let externalId: string | undefined;
      if (extCol.value) {
        const id = extCol.value.trim();
        if (id.length > 80) throw new Error('券商编号过长（最多 80 位）');
        externalId = id;
      }
      const trade: Trade = {
        id: '', sequence: 0,
        symbol: parseSymbol(symbolCol.value!),
        side: dir,
        date,
        quantity: parseNumberField(quantityCol.value!, '数量', true),
        price: parseNumberField(priceCol.value!, '单价', true),
        fee: colOf(cells, mapping, 'fee').value ? parseNumberField(colOf(cells, mapping, 'fee').value!, '手续费', false) : '0',
        note,
        source: 'import',
        externalId,
      };
      let status: RowStatus;
      if (externalId) {
        if (existingExt.has(externalId) || fileExt.has(externalId)) status = 'duplicate';
        else {
          const k = tradeKey(trade);
          status = seenValues.has(k) ? 'suspected' : 'new';
          if (status === 'new') seenValues.add(k);
        }
        fileExt.add(externalId);
      } else {
        const k = tradeKey(trade);
        status = seenValues.has(k) ? 'suspected' : 'new';
        seenValues.add(k);
      }
      rows.push({ line, trade, time, status });
    } catch (e) {
      errors.push({ line, reason: e instanceof Error ? e.message : '解析失败' });
    }
  }
  // 同日顺序：同一天内全部有成交时间时按时间排序；同一天既有买又有卖且时间不全时按文件顺序，但要求用户确认。
  let orderAmbiguous = false;
  const byDate = new Map<string, TradeRow[]>();
  for (const r of rows) { const g = byDate.get(r.trade.date) ?? []; g.push(r); byDate.set(r.trade.date, g); }
  const ordered: TradeRow[] = [];
  for (const group of byDate.values()) {
    const mixed = new Set(group.map(r => r.trade.side)).size > 1;
    if (group.length >= 2 && mixed) {
      if (group.every(r => r.time !== undefined)) group.sort((a, b) => (a.time! < b.time! ? -1 : a.time! > b.time! ? 1 : 0));
      else orderAmbiguous = true;
    }
    ordered.push(...group);
  }
  // 增量导入：导入行与账本已有同日交易混合买卖时，无法得知已有交易的盘中时间，同样需要用户确认相对顺序。
  const existingSides = new Map<string, Set<string>>();
  for (const t of existing.trades) { const s = existingSides.get(t.date) ?? new Set<string>(); s.add(t.side); existingSides.set(t.date, s); }
  let sameDayMixed = false;
  for (const r of rows) {
    const es = existingSides.get(r.trade.date);
    if (es && es.size && !es.has(r.trade.side)) { sameDayMixed = true; break; }
  }
  const seqStart = existing.trades.reduce((m, x) => Math.max(m, x.sequence), -1) + 1;
  const batchError = batchValidate({ ...existing, trades: [...existing.trades, ...ordered.filter(r => r.status === 'new').map((r, i) => ({ ...r.trade, id: `csv-${i}`, sequence: seqStart + i }))] });
  return { mapping, rows: ordered, errors, total: table.rows.length, batchError, orderAmbiguous, sameDayMixed };
}

const cashKey = (r: Pick<CashRecord, 'date' | 'kind' | 'symbol' | 'amount' | 'tax'>) => `${r.date}|${r.kind}|${r.symbol ?? ''}|${r.amount}|${r.tax ?? '0'}`;

export function analyzeCashCsv(table: CsvTable, mapping: Mapping<CashField>, fallbackKind: CashKind | undefined, existing: Ledger): CashImport {
  const existingExt = new Set((existing.cash?.records ?? []).filter(r => r.externalId).map(r => r.externalId!));
  const seenValues = new Set((existing.cash?.records ?? []).map(cashKey));
  const fileExt = new Set<string>();
  const rows: CashRow[] = []; const errors: RowError[] = [];
  for (const { line, cells } of table.rows) {
    try {
      const dateCol = colOf(cells, mapping, 'date');
      if (dateCol.value === undefined) throw new Error('未选择日期列');
      const currencyCol = colOf(cells, mapping, 'currency');
      if (currencyCol.value) checkCurrency(currencyCol.value);
      const typeCol = colOf(cells, mapping, 'type');
      let kind: CashKind;
      if (typeCol.value === undefined) {
        if (fallbackKind === undefined) throw new Error('未选择类型列，且未选择统一类型');
        kind = fallbackKind;
      } else {
        const k = KIND_VALUES[normalizeText(typeCol.value)];
        if (!k) throw new Error('资金类型无法识别（DEPOSIT / WITHDRAW / DIVIDEND / FEE）');
        kind = k;
      }
      const amountCol = colOf(cells, mapping, 'amount');
      if (amountCol.value === undefined) throw new Error('未选择金额列');
      const symbolCol = colOf(cells, mapping, 'symbol');
      const sym = symbolCol.value ? parseSymbol(symbolCol.value) : undefined;
      if (sym && kind !== 'dividend' && kind !== 'fee') throw new Error('只有分红和费用记录可以关联股票');
      const amountV = parseNumberField(amountCol.value!, '金额', true);
      const note = colOf(cells, mapping, 'note').value ?? '';
      if (note.length > 500) throw new Error('备注过长（最多 500 字）');
      let taxV: string | undefined;
      const taxCol = colOf(cells, mapping, 'tax');
      if (taxCol.value) {
        if (kind !== 'dividend') throw new Error('只有分红记录可以填写税费');
        taxV = parseNumberField(taxCol.value, '税费', false);
        if (D(taxV).gt(amountV)) throw new Error('税费不能超过分红金额');
      }
      const extCol = colOf(cells, mapping, 'id');
      let externalId: string | undefined;
      if (extCol.value) {
        const id = extCol.value.trim();
        if (id.length > 80) throw new Error('流水编号过长（最多 80 位）');
        externalId = id;
      }
      const record: CashRecord = {
        id: '', sequence: 0,
        date: parseTradeDateTime(dateCol.value!).date,
        kind,
        amount: amountV,
        tax: taxV,
        symbol: sym,
        note,
        source: 'import',
        externalId,
      };
      let status: RowStatus;
      if (externalId) {
        if (existingExt.has(externalId) || fileExt.has(externalId)) status = 'duplicate';
        else {
          const k = cashKey(record);
          status = seenValues.has(k) ? 'suspected' : 'new';
          if (status === 'new') seenValues.add(k);
        }
        fileExt.add(externalId);
      } else {
        const k = cashKey(record);
        status = seenValues.has(k) ? 'suspected' : 'new';
        seenValues.add(k);
      }
      rows.push({ line, record, status });
    } catch (e) {
      errors.push({ line, reason: e instanceof Error ? e.message : '解析失败' });
    }
  }
  const seqStart = (existing.cash?.records ?? []).reduce((m, x) => Math.max(m, x.sequence), -1) + 1;
  const batchError = batchValidate({ ...existing, cash: { ...existing.cash, records: [...(existing.cash?.records ?? []), ...rows.filter(r => r.status === 'new').map((r, i) => ({ ...r.record, id: `csv-${i}`, sequence: seqStart + i }))] } });
  return { mapping, fallbackKind, rows, errors, total: table.rows.length, batchError };
}

export function applyTradeImport(data: Ledger, trades: Trade[], newId: () => string, opts: { insertBeforeSameDay?: boolean } = {}): Ledger {
  if (!trades.length) return data;
  const existingExt = new Set(data.trades.filter(t => t.externalId).map(t => t.externalId!));
  const repeated = trades.filter(t => t.externalId && existingExt.has(t.externalId));
  if (repeated.length) throw new Error(`其中 ${repeated.length} 条记录的券商编号已存在，可能已导入过。未写入任何数据。`);
  if (opts.insertBeforeSameDay) {
    const entries = [
      ...data.trades.map(t => ({ t, group: 1 as const, order: t.sequence })),
      ...trades.map((t, i) => ({ t: { ...t, id: t.id || newId() }, group: 0 as const, order: i })),
    ];
    entries.sort((a, b) => a.t.date < b.t.date ? -1 : a.t.date > b.t.date ? 1 : a.group - b.group || a.order - b.order);
    const merged = entries.map((e, i) => ({ ...e.t, sequence: i }));
    return validateLedgerSafe({ ...data, trades: merged });
  }
  const seqStart = data.trades.reduce((m, t) => Math.max(m, t.sequence), -1) + 1;
  const added = trades.map((t, i) => ({ ...t, id: t.id || newId(), sequence: seqStart + i }));
  return validateLedgerSafe({ ...data, trades: [...data.trades, ...added] });
}

export function applyCashImport(data: Ledger, records: CashRecord[], newId: () => string): Ledger {
  if (!records.length) return data;
  const existingExt = new Set((data.cash?.records ?? []).filter(r => r.externalId).map(r => r.externalId!));
  const repeated = records.filter(r => r.externalId && existingExt.has(r.externalId));
  if (repeated.length) throw new Error(`其中 ${repeated.length} 条记录的流水编号已存在，可能已导入过。未写入任何数据。`);
  const seqStart = (data.cash?.records ?? []).reduce((m, r) => Math.max(m, r.sequence), -1) + 1;
  const added = records.map((r, i) => ({ ...r, id: r.id || newId(), sequence: seqStart + i }));
  return validateLedgerSafe({ ...data, cash: { ...data.cash, records: [...(data.cash?.records ?? []), ...added] } });
}

function validateLedgerSafe(data: Ledger): Ledger {
  try { return validateLedger(data); } catch (e) { throw new Error(`导入后账本无法通过校验：${e instanceof Error ? e.message : '数据无效'}。当前账本未改变。`); }
}

export const csvTemplate = `Date,Symbol,Side,Quantity,Price,Fee,TradeID,Note
2026-09-10,AAPL,BUY,10,220.5,1,T-1001,分批建仓
2026-09-11,MSFT,SELL,2,390,1,T-1002,部分止盈`;
export const cashCsvTemplate = `Date,Type,Symbol,Amount,Tax,FlowID,Note
2026-09-10,DEPOSIT,,2000,,F-2001,工资转入
2026-09-11,DIVIDEND,AAPL,120,12,F-2002,季度分红`;
