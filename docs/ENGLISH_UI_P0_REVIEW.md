# English UI / UX — P0 Review

范围：审计书 (`PORTFOLIO_POLISH_PHASE_ENGLISH_UI_UX_AUDIT.md`) 的 **Phase B / P0**。
前置：`docs/ENGLISH_UI_AUDIT.md`（Phase A 审计结论）。分支：`portfolio/readme`。

P0 的目标是**英文界面下不再出现中文**，且不改变任何产品的计算口径。

## 1. 三条根因与修法

审计阶段先证伪了一个想当然的假设：英文词典并不是「缺很多条」——覆盖率本来就是 100%。
真正导致中英混排的是三条互相独立的根因。

### 根因 1：本地化结果被固化了（缓存）

`LedgerDerived` 里存的是**求值当时**就已经本地化好的字符串
（`Engine.displayedReturn` → `LedgerDerived.displayReturn.title/caption`），
而派生缓存的失效键只有「账本 + 历史」，**不含语言**。所以切到 English 后只重绘视图完全无效，
标题与说明会一直停在旧语言。

- `ios/App/App/StockLedger/Store.swift`：`language.didSet` 里在语言真正变化时让缓存重算
  （`if oldValue != language { rebuild(ledger) }`）。
- 顺带修正该文件里两处 `quoteErrors` / `historyErrors` 的键：改用当前语言的名称。

### 根因 2：产品生成的文案被写进了「数据」或拼进了「查表键」

这是本次发现的**新一类泄漏**，也是审计初稿里被误判成「漏译」的那部分。
两类表现：

1. **把值拼进键**：`L10n.tr("成交 \(date) · …")` 这类写法，键里带了具体值，
   **永远匹配不上词典**（词典里只有 `"成交 {} · …"`）。这种漏译不会报错、不会空白，只会静默回退中文。
2. **把文案写进数据**：结单导入把系统说明写进了 `Trade.note` / `CashRecord.note`，
   而这些字段是**持久化**的——文案的语言在导入那一刻就被冻结了。

修法（`L10n.swift` 新增约 40 条占位符键，词典 524 → 526 条）：

| 文件 | 改动 |
| --- | --- |
| `ImportView.swift` | 括号、页脚、无障碍标签、逐行说明、金额摘要改为 `{}` 占位符键 |
| `StatementImport.swift` | 选择/导入提示句改为占位符键 |
| `CsvImport.swift` | 校验失败的两条原因句、两处分隔符 `、` 改为占位符键 / `L10n.tr("、")` |
| `Engine.swift` | `missing` 里的 `"\(symbol)：\(reason)"` 改为 `L10n.tr("{}：{}", …)` |
| `HSBCStatement.swift` | `Row.detail` 从**存储字段**改为**按结构化字段计算**的属性 |
| `Models.swift` | 新增 `Fmt.tradeNote(_:)` / `Fmt.cashNote(_:)`：展示层重建，见下 |
| `InsightsView.swift` / `TradesView.swift` | note 展示改走上面两个函数 |
| `SettingsView.swift` / `HoldingsView.swift` / `QuoteSettingsView.swift` | 拼接句改为占位符键 |

**没有动持久化数据，也没有做迁移**（审计书的约束：不自行决定数据迁移方案）。

`Fmt.tradeNote` / `Fmt.cashNote` 只在**能确认这段文案是系统自己生成的**时才重建：
交收说明必须同时满足 `source == "hsbc-statement"` + 有 `settlementDate` + note 与模板逐字一致；
净额分红说明按 `source == "hsbc-statement-net"` + `tax == nil` 判定。
用户自己改过的 note、人工录入的记录、老版本写的别的说明，一律**原样显示**。

### 根因 3：界面日期跟随设备区域

全工程没有任何 `.environment(\.locale, …)`，`Text(date)` 与日期格式因此跟随设备区域设置。

- `ios/App/App/StockLedger/RootView.swift`：注入覆盖整个界面的 `displayLocale`
  （`.en` → `en_US`，否则 `zh_CN`），并放在 `body` 的最后一个修饰符上，让 sheet 也继承。

数据层（`DateFormatter.ledgerDate`、`MarketClock`、存储格式 `yyyy-MM-dd`）**未改动**。

## 2. 顺带修掉的 UX 问题

- **P0-2 交易页筛选没有反馈**：列表标题区分「全部交易 N」与「范围内 N 笔」；
  `from > to` 时给出「起始日期晚于结束日期，请调整。」的说明，而不是静默返回空列表。
- **P0-3 现金合计在未设置期初余额时显示 `$0.00`**：
  `Engine.cashTotals` 的行为是**有意的**（未设期初时不由股票历史反推现金、不计买卖现金流），
  但界面把「未知」显示成了「零」。现在未设置期初时显示 `—` 并给出说明。
  **引擎数学未改**。

## 3. 回归测试

新增 `tests/native/LanguageTests.swift`（5 组断言）：

1. 词典完整性：条目数、无空值、无「值等于键」（漏译）、**英文值不得残留任何中日韩字符或全角标点**；
2. 占位符：中文模式按顺序替换；英文模式不留 `{}`；未收录时回退中文原文；
3. 空值占位符：`Fmt.money/signedMoney/percent(nil)` 一律 `—`，符号（含负号 U+2212）正确；
4. 展示层重建：交收说明与净额分红说明按当前语言重建，且**用户改过的 note / 人工录入 / 老格式说明原样返回**；
5. 根因 1：切到 `.en` 后 `displayReturn.title` 必须重算为英文（直接断言缓存失效，而不是断言视图）。

登记了两处（缺任一处都会假绿或 CI 报 `cannot find 'X' in scope`）：
`tests/native/NativeTests.swift` 的调用、`scripts/test-native.sh` 的 swiftc 文件列表。
本机是 Windows、没有 Swift 工具链，因此第 1–5 组由 CI 的 `macos-26` 执行。

## 4. P0 过程中发现并修掉的真 bug

`L10n.en` 里出现了**重复键**（`"该行无法解析"` 被加了第二遍）。
Swift 的字典字面量遇到重复键会在**运行时 trap**（等于启动即崩），
编译器不会报错，本机也没有 Swift 工具链——最终由 `pnpm test` 的 `tests/l10n.test.ts` 抓住。
去重后 148/148 通过。教训：**改 `L10n.swift` 的词典必须跑 `pnpm test`**。

## 5. 已知限制（不打算修，或需要你先决策）

1. **存量数据里的旧语言说明**：早期版本导入的记录，`note` 里存的中文说明若与当前模板不一致
   （或来自更早的格式），展示时仍会原样显示中文。这是「不改持久化数据」的直接代价，
   不做迁移。
2. **是否要让新的导入不再把文案写进 `note`**：改写入侧属于改变持久化数据语义，
   按审计书要求**暂停该项并汇报**，等你决策（详见汇报）。
3. `Diagnostics.record` 有 8 处用 `"\(type(of: error))：\(error.localizedDescription)"`：
   只进本机诊断日志、不进界面，归到 **P2**。
4. `CsvImport.swift` 的解析别名（`说明` / `买` / `卖`）与 CSV 模板表头是**输入约定**，
   故意保留中文，不计为漏译。

## 6. 验证状态

| 项目 | 结果 |
| --- | --- |
| `scripts/verify.ps1` | **QUALITY GATE PASSED**（148/148 Vitest + `tsc --noEmit && vite build`） |
| 词典不变量（本地脚本扫描） | 526 条、0 重复、0 空值、0 条英文值残留 CJK/全角 |
| 英文模式必然显示中文的条目 | 58 → **15**，且 15 条全部已归因（见上） |
| 原生 Swift 测试 / 模拟器渲染 / 截图 | macOS-only，由本次 commit 的 `build-ios.yml` 执行 |

后续：P1（收益页术语与百分比、交易页汇总口径、FAB 遮挡）→ P2（累计曲线可读性、数据与隐私说明、诊断日志标点）→ 终审。
