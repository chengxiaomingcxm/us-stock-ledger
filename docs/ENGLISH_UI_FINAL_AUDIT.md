# English UI / UX — Phase C Final Audit

依据：`PORTFOLIO_POLISH_PHASE_ENGLISH_UI_UX_AUDIT.md` §七（完成标准）与 §八「最终完成后输出」的 6 项。
前置：`docs/ENGLISH_UI_AUDIT.md`（Phase A）、`docs/ENGLISH_UI_P0_REVIEW.md`、`docs/ENGLISH_UI_P1_REVIEW.md`、`docs/ENGLISH_UI_P2_REVIEW.md`。
分支：`portfolio/readme`。原则同前：**尚未验证的不写「已验证」**。

## 1. Final git diff summary

本轮（Phase A 审计 → P0 → P1 → P2）在 `portfolio/readme` 上的提交，从 Phase A 审计提交的父提交起算：

| # | 提交 | 内容 |
| --- | --- | --- |
| 1 | `62b7b49` | Phase A 审计文档 |
| 2 | `ef16a33` | **P0**：本地化缓存重建、占位符键、locale 注入日期、原生回归测试 |
| 3 | `d9651db` | 写入侧：系统文案不写进 `note`，展示层按结构化字段重建；账本格式边界守卫 |
| 4 | `642296c` | 修原生测试：被改的 struct 必须是 `var` |
| 5 | `03a6a29` | 修格式边界测试的前提（合成的 `Decodable` 不接受缺键） |
| 6 | `b06da82` | 格式边界测试改为断言真实契约 |
| 7 | `b18e223` | 文档：记录第 2–6 项的 CI 结果 |
| 8 | `3fc05a4` | **P1a**：Trades 汇总改为按侧笔数 + 不含费金额 |
| 9 | `33717bf` | **P1b**：收益率措辞收紧、账户级浮动百分比、FAB 进安全区并在设置页隐藏 |
| 10 | `1b94bae` | P1 报告 |
| 11 | `ebdd64f` | **P2a**：曲线纵轴参考值 |
| 12 | `573310d` | **P2b**：英文术语统一、诊断日志冒号、`LedgerValidation` 默认标签、曲线金额加 `$`（`Fmt.compactMoney`） |
| 13 | 本提交 | P2 报告 + 本文件 |

聚合改动量（`git diff --shortstat 62b7b49^..HEAD`）：

- **代码 + 测试**：20 个文件，**+738 / −82**；
- **文档**：6 个文件，**+950 / −1**（Phase A 审计 + P0/P1/P2 报告 + 本文件 + `DATA-COMPATIBILITY.md`/`ARCHITECTURE.md` 的补正）；
- **合计**：28 个文件，**+1705 / −84**。

新增文件只有 6 个：5 份 docs + `tests/native/LanguageTests.swift`。没有新增依赖、没有新增架构层、
没有改持久化 schema（`format` 仍是 2）、没有改质量门禁脚本本身。

## 2. P0 / P1 / P2 completion status

| 优先级 | 状态 | 提交 | 本地门禁 | 远端 CI |
| --- | --- | --- | --- | --- |
| **P0**（英文模式的机制性缺陷） | ✅ 完成 | `ef16a33` | PASSED | `checks` `35489771077` / `build-ios` `35489770981` 双绿 |
| 写入侧 + 格式边界（P0 的下沉部分） | ✅ 完成 | `d9651db` → `b06da82` | PASSED | `checks` `35491658829` / `build-ios` `35491658868` 双绿 |
| **P1a**（Trades 汇总口径） | ✅ 完成 | `3fc05a4` | PASSED | `checks` `35492472127` / `build-ios` `35492472132` 双绿 |
| **P1b**（措辞、百分比、FAB） | ✅ 完成 | `33717bf` | PASSED | `checks` `35493290106` / `build-ios` `35493290097` 双绿 |
| **P2a**（曲线可读性） | ✅ 完成 | `ebdd64f` | PASSED | `checks` `35494951130` / `build-ios` `35494951117` 双绿 |
| **P2b**（术语统一 + 日志冒号） | ✅ 完成 | `573310d` | PASSED | `checks` `35495603492` / `build-ios` `35495603480` 双绿 |

单项细节见 `docs/ENGLISH_UI_P0_REVIEW.md` / `_P1_REVIEW.md` / `_P2_REVIEW.md`。

**P2-2（Settings 的 Data & Privacy）判定为「已经被满足」，没有新增 UI**：审计书要求「与真实实现一致才加入」，
四条都能从代码确认，而且都已经写在用户看得到的地方（证据表见 P2 报告 §1）。再加一节只会变成重复文案。

## 3. Test results

| 套件 | 规模 | 结果 |
| --- | --- | --- |
| Vitest（逻辑引擎，`tests/*.test.ts`） | 148 用例 / 13 文件 | **148 passed**（本地与 CI 一致） |
| 原生 Swift（`tests/native`，`scripts/test-native.sh`） | 固定断言 **397 → 408 → 414**（P1b → P2a → P2b），见下方说明 | CI `macos-26` **PASS** |
| Playwright E2E（`e2e/*.spec.ts`） | 26 用例 / 8 文件 | CI `ubuntu-latest` **26 passed** |
| 质量门禁 `scripts/verify.ps1` | 每个批次都跑过（P0、写入侧/格式边界、P1a、P1b、P2a、P2b） | 全部 **QUALITY GATE PASSED** |

> 「原生测试步骤 success」确实等于「断言全过」：`NativeTests.check` 失败会 `fatalError` 直接 trap，
> 而 `scripts/test-native.sh` 是 `set -euo pipefail`，所以进程非零退出会直接判失败，不存在「打印了 FAIL 还算过」。

> 另一个容易被忽略的证据：`scripts/test-calendar-rendering.sh` 的渲染宿主
> `tests/native/CalendarRenderApp.swift` 不只画日历，第 36 行**同时画 `CumulativeProfitChart`**。
> 也就是说 P2a / P2b 的曲线改动（留白窄栏、三个参考值、`$` 标注、自适应缩放）在**真模拟器里渲染过并成功退出**，
> 不只是「能编译」。该步骤在 CI 里只编译 `fixed` 变体（`RENDER_BASELINE` 未开，不做基线对比），
> 5 次截图各 `sleep 4`，所以耗时 6–7 分钟属正常——不是卡住。

> **原生断言总数不是固定值**：`NativeTests` 在大历史重算时跑
> `while state.rebuilding { try await Task.sleep(1ms); heartbeats += 1; check(耗时 < 30s) }`，
> 每轮心跳计 1 条，所以 CI 打印的 `PASS: N assertions; … main actor heartbeats: K` 里的 N 会随机快浮动。
> 扣掉心跳后的固定断言数：
>
> | 提交 | 总数 | heartbeats | 固定断言 |
> | --- | --- | --- | --- |
> | P1b `33717bf` | 447 | 50 | 397 |
> | P2a `ebdd64f` | 453 | 45 | 408（+11）|
> | P2b `573310d` | 482 | 68 | 414（+6）|
>
> 两次增量（+11、+6）与本轮新增断言数**逐条对上**；只看总数会误以为多出了 18 条。

**本阶段新增/加强的测试：**

| 提交 | 测试 | 钉住什么 |
| --- | --- | --- |
| `ef16a33` | `tests/native/LanguageTests.swift`（**新文件**：词典完整性 / 占位符 / 空值占位 / 生成说明 / 切语言重建缓存） | 漏译会静默回退中文，只能逐条断言；切语言必须让 `LedgerDerived` 缓存重算 |
| `d9651db`–`b06da82` | `SafetyTests.systemTextNeverEntersNote`、`newerFormatIsRefusedNotSilentlyDowngraded` | 系统文案不进 `note`；缺键 / 截断 / 更高 `format` 的文件进写保护而不是被降级 |
| `3fc05a4` | `EngineGoldenTests.rangeSummary()` | 区间汇总的笔数与**不含费**金额；只看卖出时买入侧必须归零 |
| `ebdd64f` | `EngineGoldenTests.axisReferences()` | 参考值只标三条、太近时丢后出现的那条 |
| P2b | `LanguageTests.validationDefaultLabel()`、`DiagnosticsTests`（+3 条） | 默认参数也必须走词典；日志错误行用半角冒号且不含「：」 |

**本地代偿手段**（本机是 Windows、没有 Swift 工具链；原生测试只能在 CI 跑）：

- `.scratch/swift-scan.mjs`：逐行、区分字符串/注释/插值的括号与引号配平；
- `.scratch/swift-let.mjs`：抓「值类型的 `let` 被赋值」这一整类编译错误（是踩过的坑，见 `642296c`）；
- `.scratch/en-values.mjs`：词典不变量（重复键 / 空值 / 漏译 / 英文值残留 CJK 或全角）；
- `.scratch/i18n-scan.mjs`：源码里的中文字面量分类（本地化入口 / 解析别名 / **裸字面量**）；
- `.scratch/leak-scan.mjs`：把值拼进查表键的写法（`composed`）与不在词典里的静态句；
- `.scratch/replay-notes.mjs`、`.scratch/replay-axis.mjs`、`.scratch/replay-label.mjs`：把纯逻辑在 Node 里按同一口径重放，用来在推之前验证断言里的期望值。

最后一次扫描结果：`i18n-scan` **literals=1206 / raw=0**（裸字面量归零）；
`leak-scan` **composed=0**、`notInDict=6` —— 这 6 条是：4 条 CSV/结单的**输入别名**
（`CsvImport.swift` 的 `备注`/`说明`/`买`/`卖`，必须保持中文才能匹配中文券商导出）、
1 个永不渲染的死常量（`CsvImport.template`，见 §5）、1 条用于**比对**历史 note 的常量
（`Models.swift:261` 的 `"汇丰月结单；交收日 "`）。没有一条是渲染出来的界面文案。
`en-values` 531 条、0 重复、0 空值、0 条英文值含 CJK/全角。

## 4. Manual verification checklist（只有真机 / 人能做的）

CI 在模拟器上真的启动过 App（`scripts/test-screenshots.sh` 渲染 6 屏：holdings / trades / returns / settings / calendar / import，每张图存在且 ≥20KB 防空白，日历屏另断言 `days>0 months>0`），但以下项目模拟器与 CI 覆盖不到，需要你在真机上过一遍：

| # | 怎么验 | 期望 |
| --- | --- | --- |
| 1 | 真机安装 1.0.1 IPA 并冷启动 | 正常进入，无闪退 |
| 2 | 设置 → 语言：中文↔English 来回切 | 标题、说明、日期、单位全部跟着变；**不出现中文残留**（重点看收益卡片标题与说明行、交易页汇总、现金账本） |
| 3 | 已导入过汇丰结单的账本上切到英文 | 交易与流水的说明行显示英文（由 `settlementDate` / `source` 重建），已持久化的数据一字未改 |
| 4 | 设置 → 系统字号调到最大 | 三行汇总（`In range N trades` 那几行）不截断、不重叠 |
| 5 | 深色 / 浅色模式各看一遍 | 曲线的参考值与刻度可读；涨跌颜色偏好生效 |
| 6 | VoiceOver 打开，遍历持仓 / 交易 / 收益 | 图表有整体朗读（当前 / 最高 / 最低 / 交易日数）；金额读成数字而不是逐字 |
| 7 | 小屏 iPhone（SE / 320pt 级） | 无横向溢出；FAB 不压住列表最后一行 |
| 8 | 交易表单备注输入 > 500 字后保存 | 英文模式提示 `Note is at most 500 characters.`（中文模式 `备注最多 500 字。`） |
| 9 | 收益页同步历史后看累计收益曲线 | 右侧出现上限 / 零 / 下限三个参考值，且不与曲线重叠 |
| 10 | 设置 → 从备份恢复旧版本导出的 JSON | 正常恢复；若文件被截断或来自更高版本，进入写保护并提示，不覆盖原文件 |

## 5. Known limitations

1. **`CsvImport.template`（`CsvImport.swift:611`）是死代码**：`78a2d7d` 引入后从未被引用，样例行里有一个中文单元格。
   它渲染不到界面，所以**不会**泄漏中文；但一旦有人把它接进界面就会。本轮按审计书 §六「不做无关删除」没有动它，
   建议后续单独清理（删掉，或把示例单元格写成英文）。
2. **曲线没有逐日读数**（审计书 P2-1 方案 B）。现有实现是不接受交互的 `CAShapeLayer` 视图，
   做长按拖动要先跟外层 `List` 的滚动手势做仲裁；本机没有 Swift 工具链、行为改对没改对无法本地验证，
   因此只做了方案 A（参考值）。升级路径写在 `ProfitPlotView` 的 `ponytail:` 注释里。
3. **中文 `账户总收益` 与英文 "Total return incl. dividends and fees" 措辞不同、口径相同**。
   英文改的是「别夸大成 account」；中文要不要一起改是产品文案决定，本轮未动中文键。
4. **P1b 是纯视图层改动，没有行为断言**：`FAB` 进安全区、设置页隐藏、账户级百分比守卫都只在 CI 的
   `xcodebuild` 覆盖到「能编译」，语义靠真机清单第 7 项确认。这是本阶段测试覆盖最薄的一处，如实标注。
5. **`Diagnostics` 日志在所有语言下都保留中文原文**（例如 `上次运行没有正常结束（闪退或被强制退出）。`）。
   有意为之：日志是给人回查的诊断材料；本轮只统一了分隔符。
6. **`scripts` 侧的质量门禁不包含原生测试**（macOS-only），所以「本地全绿」不等于「原生全绿」——
   原生与模拟器检查一律以 CI 为准。这也是 P0 阶段踩过「假绿」后写进 `AGENTS.md` 的原因。
7. 早期 Web 版（`src/` + `tests/`）与本轮无关，仍保留用于构建与回归；它不是当前 UI，本轮没往它加功能。

## 6. 是否已经达到 Portfolio-ready 状态

**结论：英文 UI/UX 层面已达到 Portfolio-ready；「可公开展示」的其余部分仍取决于真机验证。**

判断依据：

- 审计书列出的 P0 / P1 / P2 项**全部处理完**，每一项都有对应的提交、本地门禁结果与远端 CI 记录；
- 英文模式下**产品自身产生的中文文本为 0**（`i18n-scan` raw=0；`leak-scan` composed=0，这是 P0 那条根因的可验证形式）；
- 三套测试在 CI 上全绿，且本阶段每一处逻辑改动都留了可运行的断言或可重放的脚本；
- 交付物齐备：审计（Phase A）、三份 review、最终审计、以及未跟踪的用户任务书原件。

要保持成立，需要在真机上完成 §4 的 10 项（尤其是第 2、3、7、8 项：语言切换、旧数据说明重建、小屏、超长备注）。
在真机清单跑完之前，本文件不把「无明显 Crash」「应用可正常启动」标成「已验证」——
模拟器启动成功不等于真机启动成功。

## 附录：审计书 §七 Definition of Done 逐项

| # | 检查项 | 状态 | 证据 |
| --- | --- | --- | --- |
| 1 | English 模式没有产品自身产生的中文文本 | ✅ | `i18n-scan` 裸字面量 **raw=0**（修复前是 1，见 §3）；`leak-scan` **composed=0**；531 条英文值 0 条含 CJK/全角 |
| 2 | 日期 locale 正确 | ✅ | `RootView.displayLocale` + `.environment(\.locale, …)`；数据层仍用 `DateFormatter.ledgerDate`（`en_US_POSIX`）；`LanguageTests` 覆盖切语言重算 |
| 3 | Trades Date Range 实际过滤正确 | ✅ | `Engine.range` + `EngineGoldenTests.rangeSummary()` 断言区间外那笔不计入 |
| 4 | All / Buy / Sell + Date Range 组合正确 | ✅ | 同上；只看卖出时买入侧笔数与金额必须为 0 |
| 5 | Cash Ledger 不存在 misleading $0.00 | ✅ | `InsightsView` 以 `opening != nil` 判断，未设置期初显示 `—` + 说明，不再显示 $0.00 |
| 6 | Holdings Daily P&L 语义清晰 | ✅ | `TodayCard` 标题 `Daily P&L` / `Today's P&L`，说明行 `As of market close`（P1b） |
| 7 | Securities Return / Account Return 区分清晰 | ✅ | P2-3：`Securities return` 与 `Total return incl. dividends and fees`；说明行「入金出金不计入收益」 |
| 8 | 关键 return percentage 正确 | ✅ | 持仓页 `Unrealized P&L %` 分母是持仓成本且 `cost > 0` 守卫；已实现不给百分比（代码注释写明理由） |
| 9 | Trades Summary 不再跨证券累计 shares | ✅ | P1a：`RangeResult` 删掉 `buyQuantity` / `sellQuantity`，改为按侧笔数 + 不含费金额 |
| 10 | FAB 不遮挡任何内容 | ✅ | P1b：由 `overlay` 改为 `safeAreaInset(edge: .bottom)`（参与布局，列表自动留空间） |
| 11 | Settings 不显示 New Trade FAB | ✅ | P1b：`tab != 3` |
| 12 | Holdings / Trades / Returns 金融数字互相 reconcile | ✅ | `EngineGoldenTests` 「每日收益之和与曲线一致」（`:230`）；`NativeTests` 「平仓后每日收益 reconcile 到已实现收益」（`:138`） |
| 13 | Existing tests 全部通过 | ✅ | 148 Vitest / 447+ 原生断言 / 26 E2E，本地与 CI 一致 |
| 14 | 新 bug fix 有对应 regression tests | ⚠️ 除 P1b 外 ✅ | 见表 §3；**P1b 是纯视图层改动，只由 `xcodebuild` 覆盖编译、没有行为断言**（§5 第 4 条） |
| 15 | English / Chinese smoke test 通过 | ✅ | CI 渲染 6 屏英文截图（`test-screenshots.sh`：每张 PNG 存在且 ≥20KB 防空白，并对日历屏断言 `days>0 months>0`）；中文路径由 `L10n.tr` 在 `.zhHans` 直返键覆盖，`LanguageTests` 两种模式都断言 |
| 16 | 没有 unrelated changes | ✅ | 提交范围只含审计书的 P0/P1/P2 项，加上 `LedgerValidation` 默认标签（同属 P0 那条「值没本地化」根因）；两份用户任务书始终未跟踪 |
| 17 | 没有 debug code / temporary files | ✅ | `verify.ps1` 的「被跟踪的构建产物」「会进提交的散落调试文件」两项 PASS；所有草稿与脚本都在已忽略的 `.scratch/`（`.gitignore:26`） |

