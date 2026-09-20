# English UI / UX — P1 Review

范围：审计书 (`PORTFOLIO_POLISH_PHASE_ENGLISH_UI_UX_AUDIT.md`) 的 **Phase B / P1**（术语、口径标注、可达性）。
前置：`docs/ENGLISH_UI_AUDIT.md`（Phase A）、`docs/ENGLISH_UI_P0_REVIEW.md`（P0 + 写入侧/格式边界）。
分支：`portfolio/readme`。

> **后续状态（V1.0 收尾轮追加）**：§1 里 `[P1-5]` / `[P1-6]` 的悬浮「记一笔」按钮，中间方案（`safeAreaInset` 进安全区 +
> 设置页隐藏）后来被**整体删除**——新增入口改为 Holdings / Trades 导航栏右上角的 `+`（提交 `006306b`）。
> **当前要求以 [`docs/ENGLISH_UI_FINAL_AUDIT.md`](ENGLISH_UI_FINAL_AUDIT.md) 为准，本文只作历史记录。**

P1 的原则：**不夸大数字的含义**。能算的百分比才给，算不了的不给；标签要能被数字本身证实。

## 1. 逐项

### P1-1 收益卡片：`Latest close return` → `Daily P&L`

- `最近收盘收益` 与 `最近报价日收益` 的英文都改为 **"Daily P&L"**（同一种口径的两种测量时点，不该有两个名字）。
- 区分信息留在说明行里，不下沉到标题：
  - 收盘口径：`已完成交易日收盘` → **"As of market close"**，整行读作
    `US Eastern 2026-09-18 · As of market close`；
  - 报价口径：`最新报价` → "latest quote"（未改）。
- 标题与说明都由 `Engine.displayedReturn` 生成，因此仍受 P0 的缓存失效修正保护（切语言会重算）。

### P1-2 百分比：只给分母站得住的

- **按标的的浮盈百分比本来就已存在**（`HoldingsView.row(_:)`：`unrealized / max(cost, 1)`），本次没有改动它。
- 新增**账户级**浮盈百分比（`持有收益` 区块）：分母是 `summary.cost`（持仓成本，不受入金/出金扰动），
  且只在 `cost > 0` 时显示该行——结构上排除除零；`unrealized` 为 nil 时显示 `—`（P0 的空值契约）。
- **不给已实现收益率**：已实现收益没有可比的持仓基数（分母会是「卖过的成本」，随平仓时点漂移，
  不同区间之间不可比）。审计书 P1-2 也是这个结论，代码里以注释记下理由，避免以后被「补全」。
- 文案随之统一：`浮动收益` → "Unrealized P&L"（与 P1a 的 "Realized P&L" 对齐），新增 `浮动收益率` → "Unrealized P&L %"。

### P1-3 交易页汇总：改成「笔数 + 金额」，删掉跨标的股数

按产品给定规格（英文界面）：

```
In range N trades
Buy       N trades
Sell      N trades
Buy amount  $X
Sell amount $X
Fees        $X
Realized P&L +$X
```

- `Engine.RangeResult` 里删掉 `buyQuantity` / `sellQuantity`（跨标的股数相加本身没有业务含义），
  换成 `buyCount` / `sellCount` / `buyAmount` / `sellAmount`。
- **金额 = Σ(股数 × 成交价)，不含手续费**；手续费单独一行，不重复计入金额。
- 不采用 `trade.gross`：那个字段在结单导入的行上等于**银行舍入后的整笔交收额**，
  用它会让同一个数同时表达「成交额」与「银行现金流」两种含义（代码注释已写明）。
- 已实现 P&L 继续复用现有引擎（`summary().gains`），不做二次推导。
- 词典新增 `手续费合计` → "Fees"、`买入金额` → "Buy amount"、`卖出金额` → "Sell amount"。

### P1-4 术语：`Total return` → `Securities return`

- `累计投资收益` 的英文由 "Total return" 改为 **"Securities return"**。
  该数只是已实现 + 浮动的证券收益，不含分红、税费，也不含入金/出金；中文键本来就说「投资收益」，
  是英文的 "Total" 夸大了范围。
- 范围控制：`账户总收益`（"Total account return"，= 上述值 + 分红 − 税 − 费用）审计书没有点名，
  本次**不动**，留给 P2 的「英文术语一致性」一并处理（见 §4）。

### P1-5 / P1-6 悬浮按钮

- 由 `.overlay(alignment: .bottom)` 改为 **`.safeAreaInset(edge: .bottom)`**：
  `overlay` 不参与布局，最后一行列表内容会被按钮盖住，以前只能靠各处手动补底部内边距；
  `safeAreaInset` 会让列表自动留出这块空间。
- 删掉按钮上那个 `.padding(.bottom, 68)`（原意是绕开标签栏，现在由安全区负责），改为 12pt 间距。
- 按钮在**设置页不再出现**（`tab != 3`）：设置页没有可记录的东西，摆一个只会让人误点的入口没有收益。
  示例模式仍然隐藏（原有行为）。

## 2. 测试

- 新增 `EngineGoldenTests.rangeSummary()`：期望值人工推导（买入 10×100 + 5×200 = 2000、
  卖出 4×120 = 480、手续费 1+2+1 = 4），并显式钉住**不含费**——若误把费并进金额，这两个数会变成 2003 / 481。
  另断言只看卖出侧时买入侧必须归零（防「残留累计值」这类回归），以及区间外那笔不计入。
- 词典不变量由 `LanguageTests` 覆盖（新增的 4 条中文键都必须在英文词典里命中，且英文值不得残留中日韩字符）。
- UI 层的 `if summary.cost > 0` 是视图内的结构性守卫，原生测试套件不含 SwiftUI 视图，
  因此由 CI 的 `xcodebuild` 步骤覆盖编译，逻辑上无除零路径。

## 3. 验证状态

| 项目 | 结果 |
| --- | --- |
| `scripts/verify.ps1`（本地） | **QUALITY GATE PASSED**（148/148 Vitest + `tsc --noEmit && vite build`） |
| 词典不变量（本地扫描） | 531 条、0 重复、0 空值、0 条英文值残留 CJK/全角 |
| 纯逻辑本地重放（`.scratch/replay-notes.mjs`） | **PASS 28 / FAIL 0** |
| P1a `3fc05a4` | `checks` run `35492472127` **success**；`build-ios` run `35492472132` **success** |
| P1b `33717bf` | `checks` run `35493290106` **success**；`build-ios` run `35493290097` **success**（原生测试、日历渲染、英文截图、`xcodebuild`、IPA 全部通过） |

## 4. 已知遗留（交给 P2）

1. `账户总收益` = "Total account return"：这个数同样不含入金/出金，英文里的「account total」仍然夸大，
   需要在 P2 的英文术语一致性里与 `Securities return` 一起定稿。
2. 收益卡片的说明行英文是 `US Eastern 2026-09-18 · As of market close`：
   语义正确，但 "As of" 出现在句中且日期在前，句子略绕；若 P2 统一重写说明行，可一并调整。
3. `Diagnostics.record` 的 8 处全角冒号（只进本机日志）——P2。
