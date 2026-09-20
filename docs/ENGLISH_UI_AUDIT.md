# English UI/UX & Functional Audit — Phase A

> 任务：Portfolio Polish Phase — English Version UI/UX & Functional Audit
> 本文件是 **Phase A（AUDIT）产物：只审计，未改任何代码**。
> 结论全部带 `文件:行号`，可用文末两个扫描脚本复现。基线：`portfolio/readme` @ `40daee3`。

## 0. 审计工具（可复现）

| 脚本 | 作用 |
| --- | --- |
| `.scratch/i18n-scan.mjs` | 提取 Swift 源码里含中文的字符串字面量，并用「最近的未配对左括号 → 调用者」判断它是否经本地化入口（`L10n.tr` / `*.message`），把 CSV/结单解析别名单独归类 |
| `.scratch/coverage-scan.mjs` | 取 `L10n.en` 词典的键，与代码中作为键使用的中文串做差集，列出「会静默回退成中文」的键 |

当前结果：中文literal 1157 个 → 本地化入口 1135、解析别名 9、**裸字面量 13**；词典 486 条，代码用键 417 个，**仅 3 个"缺失"且经核对全是扫描器对嵌套拼接的误报**。

---

## A. Confirmed issues

### A0（重要负面结论）英文词典不是问题

`L10n.en` 有 486 条，代码里作为键使用的中文串 417 个，**实际覆盖率 100%**。
`L10n.swift:18-21`：

```swift
static func tr(_ zh: String) -> String {
    guard current == .en else { return zh }
    return en[zh] ?? zh          // ← 缺键静默回退中文（不报错、不空白）
}
```

真正的原因是**下面三条求值/缓存/数据层的路径**，不是"没翻译"。

---

### A1 [P0-1] 英文模式下仍是中文 —— 三条独立根因

#### 根因 1：本地化字符串被烘进**缓存派生对象**，切语言不失效

- `Engine.swift:427-428` 在**求值时就把中文翻好并固化成字符串**：

```swift
result.title = closed ? L10n.tr("最近收盘收益") : (date == today ? L10n.tr("今日盈亏") : L10n.tr("最近报价日收益"))
result.caption = "\(L10n.tr("美东")) \(date) · " + (closed ? L10n.tr("已完成交易日收盘") : L10n.tr("最新报价")) + ...
```

- 该结果被存进 `LedgerDerived.displayReturn`（`Engine.swift:577`），由 `AppState.rebuild` 缓存
  （`Store.swift:137-155`），**失效键是 `trades` / `history`，不含语言**。
- `Store.swift:76-81` 的 `language.didSet` 只做两件事：`L10n.current = language`、写 `UserDefaults`。
  **既不 `rebuild`，也不清缓存。**
- `RootView.swift:74` 的 `.id(state.language)` 只能强制**视图**重绘；视图内的 `L10n.tr` 会重新求值，
  但 `derived` 里**已经烘好的中文不会重算**。

⇒ 用户看到的 `美东 2026-09-18 · 已完成交易日收盘` 即由此产生。同一根因影响**所有由 Engine 生成并缓存的标题/说明**。

#### 根因 2：产品解释性文字被写进**数据**，渲染时无法翻译

| 位置 | 内容 | 去向 |
| --- | --- | --- |
| `HSBCStatement.swift:144` | `note: "…汇丰 PAID BENEFITS 净额；税前金额与预扣税未披露"` | `CashRecord.note` → 现金记录列表直接 `Text(record.note)` |
| `HSBCStatement.swift:122` | `note: "汇丰月结单；交收日 \(settlementDate)"` | `Trade.note` |
| `HSBCStatement.swift:125` | `detail: "成交 \(tradeDate) · 交收 \(settlementDate) · \(quantity) 股 × \(price)"` | 交易备注 |
| `HSBCStatement.swift:62-63` | `Report(warnings: ["此类结单不含…", "分红按 PAID BENEFITS 派付净额记录；…"])` | 导入预览警告 |
| `DemoData.swift:44,90-141` | `note: L10n.tr("示例入金")` 等 | **播种时**固化成字符串写入示例账本 |

⇒ 用户看到的 `净额；税前金额与预扣税未披露` 即此类。
**关键点**：`L10n.tr` 只在**当下求值**有效；一旦写进数据，语言就与数据一起冻结。
示例数据虽然用了 `tr`，但播种时机在进入示例模式时，**切换语言不会重新播种**。

#### 根因 3：UI 日期跟随**设备 locale**，不是 App 语言

- `TradesView.swift:125-150` 的 `DateField` 用 `DatePicker`；其显示文本由 **SwiftUI 环境 `locale`** 决定，
  默认即设备 locale。
- 全仓库显式设 locale 的 formatter 只有 5 处（`HoldingsView.swift:264-274` 的 `ledgerDate` = `en_US_POSIX` +
  `yyyy-MM-dd`，用于**数据**；`Models.swift:163,251`、`QuoteService.swift:57,68`、`HSBCStatement.swift:34` 为解析用），
  **没有任何一处**把 UI locale 与 `L10n.current` 绑定（无 `.environment(\.locale, …)` 命中）。

⇒ 设备中文时，**英文模式下**的 `DatePicker` 显示 `2026年9月20日`：Trades 的起始/结束日期、记账表单日期、
持仓的报价日期（`HoldingsView.swift:239`）。

---

### A2 [P0-2] Trades 日期区间：**过滤本身正确，是标签在误导**

**过滤链已追完（`DatePicker → state → filter → summary → list`）：**

- `Engine.swift:353-378` `range(_:from:to:side:query:gains:ordered:)`：
  - `if !from.isEmpty && trade.date < from { continue }` → **下界闭区间** ✓
  - `if !to.isEmpty && trade.date > to { continue }` → **上界闭区间** ✓
  - `if let side, trade.side != side { continue }` → **与 All/Buy/Sell 正确组合** ✓
  - `list`、`buyQuantity`、`sellQuantity`、`fees`、`realized` **在同一个循环里累加** ⇒ Summary 与 List **同源、必然一致** ✓
- `from`/`to` 为空 = 无界；单日区间（`from == to`）只含当日 ✓
- 日期是 `yyyy-MM-dd` 字符串比较 ⇒ 字典序等价于时间序，且已是美东口径 ✓

**真正的问题（`TradesView.swift:58`）：**

```swift
Section("\(L10n.tr("全部交易")) \(state.ledger.trades.count)") {   // ← 未过滤的全量计数
    ForEach(result.list) { … }                                    // ← 过滤后的行
```

表头写「全部交易」却用**未过滤**的 `ledger.trades.count`，下面的行却是过滤后的 `result.list`。
⇒ 出现 `From/To 同一天 + In range 26 + All trades 26` 的观感，看起来像筛选失效。**这是截图/标签造成的**误判，不是 filtering bug。

**真实缺口**：`from > to` 时无任何校验或提示，结果只是空列表 + `没有找到交易，试试其他条件。`（`TradesView.swift:63`），用户无法判断是区间写反了。

---

### A3 [P0-3] Cash Ledger 的 `$0.00` 是**设计使然**，但呈现违反「未知 ≠ 0」

`Engine.swift:130-165`：

```swift
/// 未设置期初时不根据股票历史推断现金，也不计入买卖现金流。
static func cashTotals(_ ledger: Ledger) -> CashTotals {
    ...
    if let opening {                       // ← buyOut / sellIn 只在这个分支里累加
        for trade in ledger.orderedTrades {
            if trade.side == .buy { totals.buyOut += trade.gross + trade.fee }   // 公式正确 ✓
            else { totals.sellIn += trade.gross - trade.fee }                    // 公式正确 ✓
        }
        totals.balance = opening.amount + totals.net
    }
```

- 公式本身正确（买入含费、卖出扣费），**不建议改**。
- 但 `InsightsView.swift:65-67` **无条件**渲染三行：
  `Fmt.money(-cash.buyOut)` / `Fmt.money(cash.sellIn)` / `Fmt.signedMoney(cash.tradeNet)`
  ⇒ 未设期初时显示看起来"真实"的 `$0.00`。
- 对比：同一屏的余额已正确处理为 `Set opening balance`（`L10n.swift:148`），只有这三行没有。
- ⇒ 属任务书里的**情况 A**：应显示 unavailable / not configured，并提示
  `Set an opening balance to enable cash-flow tracking.`，**而不是 `$0.00`**。

---

### A4 [P1-1] Holdings 顶部标签语义

- `Engine.swift:427` 决定标题；`L10n.swift:448`：`最近收盘收益` → **`"Latest close return"`**，
  与 `Total return`（累计）并列时容易混淆。
- 建议改为 `Daily P&L` / `Last trading day P&L`，并把 `-$41.23  -1.46%` 与
  `As of Sep 18, 2026 market close` 放在同一视觉组（`Engine.swift:460-463` 已有可复用的辅文键）。
- `TodayResult.percent` 已存在（`Engine.swift:390`），当日涨跌幅无需新计算。

### A5 [P1-2] 收益率 %

- `LedgerSummary`（`Engine.swift:18-30`）已有 `cost` / `value` / `unrealized` / `realized` / `totalProfit`
  ⇒ `unrealized / cost` **分母明确**，可以做 %。
- `realized` **没有可信分母**（已卖出部分的成本未单独保留）⇒ 按任务书要求**不显示 realized %**。
- 现有 UI 只给金额：`HoldingsView` 的 `Unrealized -$38.17` / `Cost $3,501.80` / `Total return +$58.15`。

### A6 [P1-3] Trades Summary 跨证券累加 shares

- `TradesView.swift:46-47`：`"\(Fmt.quantity(summary.buyQuantity)) \(L10n.tr("股"))"`，`L10n.swift:85` `股` → `shares`。
- `Engine.swift:369`：`result.buyQuantity += trade.quantity`（**不区分证券**）⇒ `105 shares` 这种跨标的加总无金融含义。
- `RangeResult`（`Engine.swift:344-351`）已有 `fees`、`realized`，但**没有** buy/sell 的**金额**字段。

### A7 [P1-4] 两个 "Total"

- `L10n.swift:71` `累计投资收益` → **`"Total return"`**；`L10n.swift:144` `账户总收益` → `"Total account return"`。
- 现有公式（`Engine.swift:44` `investNetAll`、`InsightsView` 的 `account-profit`）：
  - 大数字 = `summary.totalProfit` = 已实现 + 浮动
  - 账户总收益 = `totalProfit + investNetAll`，`investNetAll` = 分红净额 − 费用
  ⇒ **与建议的命名口径完全一致**，只需改文案，**不动公式**。

### A8 [P1-5][P1-6] FAB 遮挡 + 硬编码 inset

`RootView.swift:101-117`：

```swift
.overlay(alignment: .bottom) {            // ← 挂在整个 TabView 上 ⇒ 设置页也会显示
    if !state.demo {
        Button(action: presentNewTrade) { Label(L10n.tr("记一笔"), systemImage: "plus") … }
            .padding(.bottom, 68)          // ← 硬编码魔法数字
    }
}
```

- FAB 只在**示例模式**下隐藏，**设置页照样显示**（与要求 4 不符）。
- `overlay` **不会**给滚动内容留 inset ⇒ 列表最后一条会被压住，这正是遮挡根因；
  原生解法是 `.safeAreaInset(edge: .bottom)`（内容自动内缩，各页无需手加 padding）。

---

## B. False positives / already correct

1. **英文词典不是问题**：486 条、覆盖率 100%（唯 3 条"缺失"是扫描器对嵌套 `L10n.tr(` 拼接的误报）。
2. **Trades 日期区间过滤正确**：闭区间、与侧边筛选正确组合、Summary 与 List 同源一致（A2）。
3. **Cash 金额公式正确**（`gross + fee` / `gross − fee`）；未设期初时余额已正确显示 `Set opening balance` 而非 0。
4. **所有解析/展示用 `DateFormatter` 都显式设了 locale**（`en_US_POSIX` / `en_US`），无隐式设备依赖；
   `yyyy-MM-dd` 比较等价于时间序、美东口径一致。
5. **CSV / 结单的中文列名别名（113 处）必须保留中文** —— 那是券商表头匹配（`CsvImport.swift:35-40,102-109`），
   不应翻译。
6. **示例数据的可见文案都走了 `L10n.tr`**（`DemoData.swift:44,90-141`）。
7. 7 处裸中文在 `Diagnostics.record(...)`（`ImportView.swift:233,256`、`SettingsView.swift:134,138,178`、
   `StatementImport.swift:115`、`Store.swift:176,202`）——**本机技术日志**，非 UI 文案 ⇒ 归 P2（全角冒号观感问题）。
8. `Store.swift:37` 的 `unreadableMessage` 虽为裸中文常量，但渲染处 `RootView.swift:81` 是
   `L10n.tr(LedgerStore.unreadableMessage)`，键在词典内 ✓（**属于"动态键"一类**，见风险 R4）。

---

## C. Root cause（汇总）

> 产品文案在**求值那一刻**就被固化成字符串 —— 要么存进**缓存派生对象**（`LedgerDerived`），
> 要么写进**数据**（结单 note / 示例数据）。而语言切换只覆盖了"视图重绘"这一层，
> 没有覆盖"派生缓存"和"已固化的数据"这两层；同时 UI 日期用的是设备 locale 而非 App 语言。

三条根因相互独立，因此**修词典无济于事**。

---

## D. Files involved

| 问题 | 涉及文件 |
| --- | --- |
| P0-1 根因1 | `Engine.swift:427-428,577`、`Store.swift:76-81,137-155`、`RootView.swift:74` |
| P0-1 根因2 | `HSBCStatement.swift:62-63,122,125,144`、`DemoData.swift:44,90-141`、`InsightsView.swift`（现金/交易备注渲染） |
| P0-1 根因3 | `TradesView.swift:125-150`、`HoldingsView.swift:239`、`RootView.swift`（缺 `.environment(\.locale,…)`） |
| P0-2 | `TradesView.swift:12-15,37-58,63`（`Engine.range` 不动） |
| P0-3 | `InsightsView.swift:60-70`（`Engine.cashTotals` 不动） |
| P1-1/P1-4 | `Engine.swift:427`、`L10n.swift:71,144,448` |
| P1-2 | `Engine.swift:18-30`、`HoldingsView.swift`（收益区） |
| P1-3 | `Engine.swift:344-351,369`、`TradesView.swift:46-47` |
| P1-5/P1-6 | `RootView.swift:101-117` |

## E. Tests involved

**现有可复用**：`tests/native/EngineGoldenTests.swift`（引擎口径）、`DemoModeTests.swift`、
`CsvImportTests.swift`、`ErrorPathTests.swift`、`SafetyTests.swift`；`tests/*.test.ts` 148 项；
`e2e/` 26 项；`scripts/test-screenshots.sh`（截图非空 + `HARNESS derived` 守卫）。

**Phase B 需要新增/加强（按最小）**：

1. **语言切换回归**（覆盖根因 1）：新增 `tests/native/LanguageTests.swift` —— 切到 `en` 后
   `L10n.current == .en`，且**派生结果里的标题/说明**必须是英文（直接断言 `LedgerDerived.displayReturn.title`）。
   → 这条现在**必然失败**，正是回归证据。
2. **区间过滤**：先核对 `EngineGoldenTests` 是否已覆盖单日/多日/空区间/Buy only/Sell only/ET 边界/`from>to`；
   缺哪个补哪个（预计只需补 `from > to` 与 ET 边界两条）。
3. **`from > to` 的 UI 反馈**：属视图层，用既有 E2E（`e2e/history.spec.ts` 或 `v125.spec.ts` 已有交易区间用例）扩展一条。
4. **英文日期格式**：`DatePicker` 的显示依赖环境 locale，**纯逻辑测试覆盖不到**；
   建议 (a) 对 `.environment(\.locale,…)` 的取值做单元断言（`L10n.current` → 期望 locale），
   或 (b) 在 `test-screenshots.sh` 已有的英文模式下新增一张 Trades 截图作为守卫。
5. **Cash 未设期初**：`InsightsView` 三行不出现 `$0.00`（属视图契约）；原生测试不易覆盖，
   建议用截图守卫或 E2E。

## F. Proposed minimal changes（Phase B 方案，逐条最小 diff）

| # | 问题 | 最小改法 | 影响面 |
| --- | --- | --- | --- |
| 1 | P0-1 根因1 | `Store.swift:76-81` `language.didSet` 内追加 `rebuild(ledger)`（或把 language 纳入缓存失效键） | 1 行级；切语言多一次后台重算 |
| 2 | P0-1 根因2 | **需你决策**（见下），倾向：结单/示例的 note 改为**结构化标识**，渲染时 `L10n.tr` | 触及已持久化数据，见 R1 |
| 3 | P0-1 根因3 | `RootView` 增加一处 `.environment(\.locale, L10n.current == .en ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN"))` | 1 行，覆盖全部 `DatePicker` |
| 4 | P0-2 | `TradesView.swift:58` 表头改为反映过滤结果；`from > to` 时给显式提示 | 仅视图文案，不动 `Engine.range` |
| 5 | P0-3 | `InsightsView.swift:65-67` 在 `ledger.opening == nil` 时显示 `—` + 一行提示 | 仅视图，不动公式 |
| 6 | P1-1 | 改 `L10n` 中 `最近收盘收益` 的 EN 值（→ `Daily P&L`）+ 标题下加 "As of … market close" | 文案级 |
| 7 | P1-3 | `RangeResult` 增 `buyAmount`/`sellAmount` 两个累加字段，Summary 用「笔数 + 金额」替代跨证券股数 | 触及 `Engine` + 视图；影响截图/E2E 文案断言 |
| 8 | P1-4 | 只改 EN 文案：`Total return` → `Securities return` | 文案级 |
| 9 | P1-5/6 | FAB 从 `.overlay` 改 `.safeAreaInset(edge: .bottom)`；设置页（tab 3）不显示；删除 `.padding(.bottom, 68)` | 视图结构；需小屏/Dynamic Type 复验 |

**明确不做**：不改 `cashTotals` / `range` / `displayedReturn` 的金融计算；不新增依赖、Manager、Service；
不改持久化 schema。

## G. Risks

- **R1（最大）**：根因 2 触及**已持久化数据**。旧账本/旧现金记录里的中文 note 不会因改代码而变；
  若要"旧数据也变英文"就必须回填或迁移，而任务书禁止无 migration 的 schema 改动。
- **R2**：`didSet` 里 `rebuild` 会增加一次派生重算。CI 实测 25,000 收盘价 / 4,000 交易日 / 1,000 笔交易耗时 0.252s，
  且 `rebuild` 本身是 `Task.detached`，可接受。
- **R3**：`DateField`/`DatePicker` 的 locale 改动会同时影响记账表单与报价日期，属**行为可见**变化，
  需真机/截图复验（含 12/24 小时制与星期起始）。
- **R4**：**动态键无法静态校验**。`L10n.tr(error)`、`L10n.tr(issue)`、`L10n.tr(row.reason)`、
  `L10n.tr(text)`（`Models.swift:191`、`CsvImport.swift:141`）、`L10n.tr(LedgerStore.unreadableMessage)`
  是把**变量**当键传进去，覆盖率脚本只能核对其中常量（已核对 `unreadableMessage` ✓）。
  ⇒ 建议 Phase B 顺带加一条**运行期守卫**（开发期断言"键未命中"），或把这类键收敛到常量。
- **R5**：P1-3 改动 Summary 会改变现有截图与可能的 E2E 文案断言，需同步更新（`e2e/v125.spec.ts` 有交易区间用例）。
- **R6**：本轮改动会碰 `Engine.swift` 的呈现结构（P1-3）与 `RootView` 布局，**回归面比 Phase 5/6 大**，
  建议按 P0 → 测试 → P1 → 测试 的批次提交，每批都跑 `pnpm e2e` 与原生套件。

---

## 需要你拍板（任务书 §10：冲突先说，不自行猜测）

### Q1：P0-1 根因 2（写进数据的中文散文）用哪种修法？

| 方案 | 做法 | 代价 |
| --- | --- | --- |
| **A**（倾向） | 结单/示例的 `note`/`detail`/warning 改存**结构化标识**，渲染时 `L10n.tr` | 干净、语言永远跟随；但**旧记录里已有的中文 note 保持不变**（需接受"旧数据保留原语言"） |
| **B** | 保留写入中文，但渲染时 `L10n.tr(note)` | 只对**固定句式**有效；带变量拼进去的（如 `汇丰月结单；交收日 2026-09-18`）永远匹配不到键，无效 |
| **C** | 仅在**新导入**时按当前语言写入 | 最省事、零兼容风险；但英文用户在导入后再切语言仍会不一致 |

请选一个（或说明你更在意"旧数据一致"还是"零兼容风险"）。我不自行决定。

### Q2：P1-3 的 Summary 具体保留哪些字段？

任务书给的候选是：
`In range 26 trades / Buy 18 trades / Sell 8 trades / Buy amount $X / Sell amount $X / Realized P&L +$96.32`

我的建议（最小改动、信息量最大）：保留 `In range`（笔数）+ `Buy`/`Sell`（**改为笔数**）+ `手续费` +
`已实现收益`，并**新增** `Buy amount` / `Sell amount`（金额）；**删除**跨证券的 `shares` 合计。
是否同意？

---

## 附：遗留事项与本次审计无关

- `releases/v1.0.1.json` 已写入（版本 1.0.1 / build 6 / sha256 `1c07a8cf…`，8/8 结构校验通过），
  昨天因脚本 bug 未提交，本次已单独提交。**发布仍等 Codex 审查后同步 `main` 自动触发。**
- 本审计**未改动任何产品代码**；工作区仅新增本文件与 `.scratch/` 下的扫描脚本（后者被 git 忽略）。
