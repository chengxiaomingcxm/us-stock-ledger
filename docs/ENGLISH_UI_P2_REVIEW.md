# English UI / UX — P2 Review

范围：审计书 (`PORTFOLIO_POLISH_PHASE_ENGLISH_UI_UX_AUDIT.md`) 的 **Phase B / P2**
（`[P2-1]` 曲线可读性、`[P2-2]` Settings 的 Data & Privacy、`[P2-3]` 英文金融术语统一），
外加 P1 报告 §4 遗留的第 3 项（`Diagnostics` 全角冒号）。
前置：`docs/ENGLISH_UI_AUDIT.md`（Phase A）、`docs/ENGLISH_UI_P0_REVIEW.md`、`docs/ENGLISH_UI_P1_REVIEW.md`。
分支：`portfolio/readme`。

> **阅读提示（V1.0 收尾轮追加）**：本文记录的是 P2 阶段**当时**的状态与证据，里面引用的
> `SettingsView.swift` 行号属于那版实现。设置信息架构在 V1.0 收尾轮已改为
> `显示 / 行情数据 / 数据 / 支持` 四组 + 二级页（原「数据」节的操作移入
> `导入与导出`、`备份与恢复`，末节 footer 移入 `关于`），最新口径见
> `docs/ENGLISH_UI_FINAL_AUDIT.md` §7。**要求以最终审计文档为准，本文只作历史记录。**

P2 的原则：**先证明再动手**。审计书对 `[P2-2]` 写死了前提（「无法从代码确认就不要写进 UI」），
本文档对每一项都给出「代码里是什么」的证据；不对的地方改，已经对的地方**不加**。

## 1. 逐项

### P2-1 累计收益曲线：加纵轴参考值（审计书方案 A）

审计书给了 A / B 两个选项，B（长按拖动读数）标为「优先，**如果现有 Chart 实现容易支持**」。
本项目的曲线不是 Swift Charts：

- 它是 `InsightsView.CumulativeProfitChart` → `ProfitPlot`（`UIViewRepresentable`）→ `ProfitPlotView`（`UIView` + `CAShapeLayer`）；
- `ProfitPlotView.isUserInteractionEnabled = false`，重算被 `previousBounds` / `renderedRevision` 双重缓存挡住
  （注释写明「滚动时只平移已有的 Core Animation 层，从不重画」）；
- 它处在一个可滚动的 `List` 的 `Section` 里。

要支持长按拖动读数，必须先解决手势仲裁（长按 vs 外层 `List` 的 pan，否则要么拖动读不出数、
要么曲线把整页滚动吃掉），而本机是 Windows、没有 Swift 工具链，**行为改对没改对无法在本地验证**，
只能在 CI 上确认「能编译」。这与审计书给 B 设的前提（「容易支持」）不符，所以取 A：

- 曲线让出右侧一条窄栏（`gutter = min(40, width × 0.2)`），参考值靠右对齐贴在这一栏里，所以数字不会压在曲线上；
- 标三条：**上限 / 零轴 / 下限**，取自 `InsightsPresentation.maximum` / `0` / `minimum`（这两个量本来就把 0 夹在里面）；
- 数值走同一套紧凑口径（`Fmt.compactSigned` 的位数规则：≥100 取整、<100 两位小数、上万用 k），
  所以轴上三个数与说明行的「最高 / 最低」不会一个圆整一个带小数；
- 上限/下限相撞时会重复标同一个数（全为正的历史里 `minimum` 就是 0，零轴落在底边），
  因此 `axisReferences(proximity:)` 按 0.09（≈168pt 高度下的 14pt）去重：**宁可少标一个数，也不叠字**；
- 代码里以 `ponytail:` 注释写明这是「刻意不做 B」，以及升级路径（真机可验证时加
  `UILongPressGestureRecognizer`，0.15s，画竖线 + 气泡读数）。

**同一种金额格式**：卡片大数走 `Fmt.signedMoney`（`+$58.15`），参考值如果不带 `$` 会被读成百分比。
所以纵轴的三个数与「最高 / 最低」说明行统一带货币符号（`+$120` / `$0.00` / `−$40.00`）。
本 App 只记美元（结单导入会跳过非美元行），符号是固定的。

🔴 **这里有一个真 bug 是本地重放抓到的**：第一版写成 `"$" + Fmt.compactSigned(...)`，
输出是 `$+120`——英文里货币符号要排在正负号**后面**，正确写法是 `+$120`（与 `signedMoney` 一致）。
是 `.scratch/replay-axis.mjs` 把四条期望全报 FAIL 才发现的，不是 CI。因此补了一个 `Fmt.compactMoney`：
与 `compactSigned` 同口径，只负责把符号搬对位置。

**日历格子仍然不带 `$`**（`InsightsView.swift:469` 照旧用 `compactSigned`）：那是 7 列的小格子，
加符号既挤又吵，单位由日历自己的区块与说明行交代。所以本轮的规则是
「**曲线卡片内**的金额统一带 `$`」，不是「全 App 所有紧凑金额都带 `$`」——这是有意的，
不是漏改。

改动：`Engine.swift`（`InsightsPresentation.axisReferences`）、`InsightsView.swift`（`ProfitPlotView`）。

### P2-2 Settings 的 Data & Privacy：**不加**（四条已经都为真，且已经在 UI 里）

审计书要求「只有在以下描述与真实实现一致时才加入」，且「无法从代码确认就不要写进 UI」。
逐条核实的结果：**四条都成立，而且都已经写在用户看得到的地方**，新增一节只会变成重复文案。

| 审计书要求 | 代码事实 | 用户已经在哪里看到 |
| --- | --- | --- |
| Data stored on device | `LedgerStore.fileURL` = `Documents/ledger-v2.json`（`Store.swift:12-15`）；没有服务端 | 设置页末节 footer「账本保存在本机」（`SettingsView.swift:116`）；「使用说明」页（`SettingsView.swift:233`） |
| API keys stored securely | `enum Keychain` 用 `kSecClassGenericPassword`（`QuoteService.swift:100-121`）；Key 不是 `Ledger` 的字段 | 行情来源页（`QuoteSettingsView.swift:57`、`:119`，两条 footer） |
| No account required | 全仓没有注册/登录/账号/订阅代码；`账号` 只出现在 URL 校验里（`QuoteService.swift:183` 禁止 URL 带凭据） | 不需要声明，因为没有任何入口暗示需要账号 |
| Backups contain no API keys | `LedgerStore.exportText`（`Store.swift:76`）只编码 `Ledger`；Key 存在 Keychain，不在 `Ledger` 里 | 设置页「数据」节 footer（`SettingsView.swift:87`）；「使用说明」页（`SettingsView.swift:233`） |

结论：`[P2-2]` 判定为**已被满足**，本次没有为它新增任何 UI 或字符串。

### P2-3 英文金融术语统一

按审计书给的清单做了一遍**值级别**的扫描（不是凭印象看几屏）：
把 `en` 词典 531 条按概念归类，列出同一概念出现过的所有英文写法，再逐组判定。

**改掉的（5 处，都是值，不动键）：**

| 中文键 | 改前 | 改后 | 为什么 |
| --- | --- | --- | --- |
| `当日收益` | "Daily return" | **"Daily P&L"** | 和收益卡片标题（`最近收盘收益` / `最近报价日收益` = "Daily P&L"）指同一天同一个量，不该两个名字 |
| `本月收益` | "This month" | **"Monthly P&L"** | 原名丢掉了「收益」：同一张卡片里日行叫 Daily P&L，月行只说 "This month"，数字是什么就没交代了 |
| `账户总收益` | "Total account return" | **"Total return incl. dividends and fees"** | 这个数 = 已实现 + 浮动 + 分红净额 − 账户费用，**不含入金/出金**；"account" 会被读成整个账户的回报（P1 报告已挂账） |
| `已实现收益 + 当前持仓浮动收益（证券口径）` | "Realized + open gains (securities only)" | **"Realized + unrealized P&L (securities only)"** | "open gains" 是同一概念的第三个名字；统一到 "Unrealized P&L" |
| `交易日` | "trading days" | **"Trading days"** | 它是 `LabeledContent` 的标签，全 App 的标签都首字母大写（同行还有 "Previous trading day"） |

> **与 Phase A 的偏离，说明一下**：Phase A §F 的「最小改法」清单第 8 条只写了
> `Total return` → `Securities return`（P1 已照做），**没有**为 `账户总收益` 开修改项；
> A7 那一段是在**描述现状**，不是在指定目标名。本次把 `账户总收益` 的英文从 "Total account return"
> 改成 "Total return incl. dividends and fees"，依据是 P1 报告 §4 挂的账 + 审计书 §七 的
> 「Securities Return / Account Return 区分清晰」：这个数 = 已实现 + 浮动 + 分红净额 − 费用，
> **不含入金/出金**，叫 "account" 仍然夸大。**公式一行没动**——A7「不动公式」的实质要求是遵守的。

**查过但判定不用改的（写在这里，免得下次重复扫）：**

- `P&L` 家族已经自洽：`Today's P&L`（`今日盈亏`）、`Daily P&L`、`Realized P&L`、`Unrealized P&L`、`Unrealized P&L %`。
- `Opening balance`（13 处）、`Cash flow` / `Net trade cash flow`、`As of market close`、
  `Account fees`、`Dividend` / `Dividends net of tax` / `Dividends received (net)`、
  `Withholding tax (optional)` / `Known withholding tax`、`Deposit` / `Deposits` / `Withdrawal` / `Withdrawals`
  ——都是同一写法，没有第二个名字。
- `持有收益` = "Holdings return"：它是**区块标题**（该区块的行才叫 Unrealized / Realized / Securities return），
  不是同一个数上的两个标签，保留。
- 长帮助段落里的 "that day's return" / "Cash movements" 是叙述性文字，不是术语；两段中文键分别长 770 / 751 字符
  （还是直引号 `「待补」` 与弯引号 `“待补”` 两个变体），为一句措辞去改这么长的字符串，风险大于收益。
- `个交易日` = "trading days" 保持小写——它只出现在 "{} trading days" 这种句子中间，首字母不该大写。

**没有动中文键**：P2-3 的题目是「英文金融术语统一」，而这些键就是中文 UI 的正文本身。
`账户总收益` 那一条改的是英文措辞，中文仍写「账户总收益」——两者现在措辞不同但都成立
（下方说明行「入金出金不计入收益」把口径讲清楚了）。若要把中文也改成同一口径，需要你点头，是一次单独的产品文案变更。

### P2-3 附带：诊断日志里的 8 处全角冒号（P1 报告 §4 第 3 项）

`Diagnostics.record` 的调用点原来各自拼 `"\(type(of: error))：\(error.localizedDescription)"`，
用的是中日韩标点「：」。日志是用户可以直接转发给支持者的纯文本，混着全角冒号读起来是错的。

改法不是逐处替换 8 遍，而是收敛到一个入口（净减代码）：

```swift
/// 统一的「抛出的错误」行：`类型: 说明`。
static func record(_ kind: String, error: Error) {
    record(kind, "\(type(of: error)): \(error.localizedDescription)")
}
```

8 处调用点变成 `Diagnostics.record("SAVE", error: error)`。顺便把日志行**格式**钉进了测试，
以后不会再退回全角（见下）。

### 顺手抓到的同类 bug：`LedgerValidation.note` 的默认参数是硬编码中文

这是做本项扫描时扫出来的——它属于 P0 那条根因（**拼进整句的值自己没本地化**），所以一并修。

`Models.swift:187` 的 `_ label: String = "备注"`，而这个 `label` 会被当成**值**填进整句翻译
`"{}最多 500 字。"`。5 个调用点（`TradesView.swift:326`、`InsightsView.swift:289` / `:313`、
`CsvImport.swift:371` / `:546`）**全都没传 `label`**，所以走的就是这个默认值：

| 模式 | 实际弹出的文字 |
| --- | --- |
| 中文 | `备注最多 500 字。`（正确） |
| 英文 | `备注 is at most 500 characters.` ← 整句翻译得再好也救不回来，漏的是参数 |

而且它是**可达的**：界面没有 500 字截断，`Models.swift:188` 是唯一的守卫，
备注打超 500 字就会弹出这句（英文模式下就是上面那行）。

改法：默认值改成 `L10n.tr("备注")`。英文从此是 `Note is at most 500 characters.`，
中文一字不变，并加了回归断言（含一条「旧写法确实会泄漏中文」的反向验证，见 §2）。

## 2. 测试

- **`EngineGoldenTests.axisReferences()`（新增）**：期望值人工推导并写成字面量——
  全为正（上限 120 / 下限被夹到 0）→ 2 条，上限在 0、零在 1；
  跨零（+80 / −40）→ 3 条，零轴在 80/120 = 0.667；上限 100、下限 −5 → 零轴 100/105 = 0.952
  与底边只差 0.048 < 0.09 → 丢掉靠后的下限那条。
  最后一条专门钉住「丢的是后出现的那条，不是上限」，防止去重写反。
  文字断言写成 `+$120` / `$0.00` / `+$100`——**符号在前、货币符号在后**，
  所以如果把 `compactMoney` 改回 `"$" + compactSigned(...)`，这三条会一起红。
- **`LanguageTests.validationDefaultLabel()`（新增）**：英文模式下 501 字备注的报错必须是
  `Note is at most 500 characters.`（不含任何中日韩字符）；500 字不报错（边界）；
  中文模式下仍是 `备注最多 500 字。`——三条一起锁住「默认值也走词典，且两种语言都不变味」。
- **`DiagnosticsTests`（补断言）**：`Diagnostics.record("TEST", error: DiagnosticsTestError())`
  写出的那一行必须带类型名、必须用半角冒号、**必须不含「：」**。
  错误类型定义在文件层，否则 `type(of:)` 对函数内局部类型会打印成 `(unknown context at ...)`，
  断言就变成在断言一个不稳定的名字。
- **本地重放**（`.scratch/replay-axis.mjs`，本机没有 Swift 工具链，用 Node 按同一份夹紧规则与
  proximity 判据重放）：**PASS 6 / FAIL 0**，含「全为负」「区间恒为 0（span 走 0.0001 兜底，不能出 NaN）」
  与「上万走 k 分支时符号仍在 `$` 之前」三个边界。
  这个脚本第一次跑出 2 个 FAIL——是**我手写的期望值错了**（`Fmt.compactSigned(80)` 走 `< 100` 分支，
  是 `+80.00` 不是 `+80`），实现本身没问题；修的是期望值，不是实现。
  第二次跑出的 4 个 FAIL 则**是实现的错**（`$+120` 的符号顺序，见 §1）——同一个脚本把两种错误都拦住了，
  一个「期望写错」一个「代码写错」，修法正好相反。
- 词典不变量（`tests/l10n.test.ts` + `.scratch/en-values.mjs`）：531 条、0 重复键、0 空值、
  0 条英文值残留 CJK/全角。改了 5 个值之后重跑仍然全过。
  （`值等于键(漏译): 1 [ 'CSV' ]` 是既有且正确的——`CSV` 中英文本来就一样。）
- **原生断言数（CI 打印的 `PASS: N assertions; … main actor heartbeats: K`）**：
  总数里混着一条**计时相关**的断言——`NativeTests` 等大型历史重算时跑
  `while state.rebuilding { try await Task.sleep(1ms); heartbeats += 1; check(耗时 < 30s) }`，
  每轮心跳计 1 条。所以总数会浮动，真正稳定的量是「**总数 − heartbeats**」：

  | 提交 | 总数 | heartbeats | 固定断言 |
  | --- | --- | --- | --- |
  | P1b `33717bf` | 447 | 50 | 397 |
  | P2a `ebdd64f` | 453 | 45 | **408**（+11 = `axisReferences()` 的 11 条）|
  | P2b `573310d` | 482 | 68 | **414**（+6 = `validationDefaultLabel()` 3 条 + `DiagnosticsTests` 3 条）|

  先看到 482 时我按「447 + 静态新增」算，差了 18 条——**差额全部来自心跳**（50 → 68）。
  扣掉心跳后增量与静态统计逐条对上。写在这里是因为「断言总数」看起来像个固定值，其实不是。
- **再一个本地重放**（`.scratch/replay-label.mjs`）：按 `L10n.tr` + `LedgerError.errorDescription`
  的真实口径重放三段字符串，**PASS 4 / FAIL 0**；其中第 4 条是反向验证：
  用旧写法（写死 `"备注"`）重放出来确实不是 `Note is at most 500 characters.`——
  说明这条断言真的能拦住回归，而不是永远为真。
- **字面量码位检查**（`.scratch/check-minus.mjs`）：`compactMoney` 里比较负号的字面量
  必须与 `compactSigned` 用的是同一个码位（U+2212，不是 ASCII 的 `-`，也不是 U+2013 的 en dash）
  ——否则负值会输出 `$−40.00` 而不是 `−$40.00`。
  这类错**本地重放抓不到**（重放脚本用 JS 自己实现同一语义），只能比对源码里的码位；
  结果 **PASS**（`compactSigned` = U+2212，`compactMoney` 比较项 = U+2212）。
  这个脚本第一版把正则写成只取第一个比较项（拿到的是 `+`），误报了一次 FAIL——
  修的是脚本，不是实现。

## 3. 验证状态

| 项目 | 结果 |
| --- | --- |
| `scripts/verify.ps1`（本地） | **QUALITY GATE PASSED**（148/148 Vitest + `tsc --noEmit && vite build`），P2a 跑 1 次、P2b 跑 3 次（中途补了 `$` 排列与标注缩放兜底） |
| 词典不变量（本地扫描） | 531 条、0 重复、0 空值、0 条英文值残留 CJK/全角 |
| 纵轴逻辑本地重放（`.scratch/replay-axis.mjs`） | **PASS 6 / FAIL 0**（含 `$` 排列的两轮修正） |
| 默认标签本地重放（`.scratch/replay-label.mjs`） | **PASS 4 / FAIL 0**（含「旧写法确实泄漏中文」的反向验证） |
| 负号码位检查（`.scratch/check-minus.mjs`） | **PASS**（`compactSigned` 与 `compactMoney` 都用 U+2212） |
| 源码中文扫描（`.scratch/i18n-scan.mjs`） | 裸字面量 **0**（修复 `LedgerValidation` 默认参数前是 1） |
| Swift 静态自检（`.scratch/swift-scan.mjs` / `swift-let.mjs`） | OK / OK |
| P2a `ebdd64f`（曲线参考值） | `checks` run `35494951130` **success**（13 文件 / 148 passed，E2E 26 passed）；`build-ios` run `35494951117` **success**（原生测试、日历渲染、英文截图、`xcodebuild`、IPA 全过） |
| P2b `573310d`（术语 + 日志冒号 + 默认标签 + `$`） | `checks` run `35495603492` **success**（单元测试 + 类型检查/构建 + E2E 全过）；`build-ios` run `35495603480` **success**（原生测试、日历渲染、英文截图、`xcodebuild`、设备构建、IPA 上传全过） |

## 4. 已知遗留

1. **中文 `账户总收益` 与英文 "Total return incl. dividends and fees" 措辞不同口径相同**。
   英文改的是「别夸大成 account」；中文要不要同步改，是一次产品文案决定，等你的意见。
2. **曲线只给了参考值，没有逐日读数**。审计书方案 B（长按拖动显示日期 + 累计收益）没做，
   理由与升级路径见 §1 的 `ponytail:` 注释；要做的话需要先有真机/模拟器验证条件。
3. **收益卡片说明行的语序**（`US Eastern 2026-09-18 · As of market close`）保持 P1 的样子：
   语义正确，审计书也没有要求改，为它重写整行没有收益。
4. `Diagnostics` 里中文键本身仍是中文（例如 `上次运行没有正常结束（闪退或被强制退出）。`），
   英文界面下日志里会中英混排。这是**有意的**：日志是诊断材料，中文原文更利于回查；
   本次只统一了分隔符，没有把日志文案也纳入本地化。
5. `CsvImport.template`（`CsvImport.swift:611`）**从引入起就没有任何引用**（`78a2d7d` 加的），
   它的样例行里有一个中文单元格「示例行」。因为它永远渲染不到界面，**不会**泄漏中文；
   但它是「一旦有人把它接进界面就会泄漏」的隐患。本轮**没有删它**：审计书 §六 明确禁止
   「删除现有正确功能」，而删一个用不到的常量属于无关改动。建议后续单独一次清理搞掉它
   （要么删，要么把示例单元格换成英文）——不在本轮 DoD 的「没有 unrelated changes」里冒险。
