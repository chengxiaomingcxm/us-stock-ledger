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
| 9 | `33717bf` | **P1b**：收益率措辞收紧、账户级浮动百分比、FAB 进安全区并在设置页隐藏（**该浮动 FAB 后来被整体删除**，见 §7） |
| 10 | `1b94bae` | P1 报告 |
| 11 | `ebdd64f` | **P2a**：曲线纵轴参考值 |
| 12 | `573310d` | **P2b**：英文术语统一、诊断日志冒号、`LedgerValidation` 默认标签、曲线金额加 `$`（`Fmt.compactMoney`） |
| 13 | `c5021b2` | P2 报告 + 本文件（Phase C 最终审计） |
| 14 | `006306b` | **最终 UI 轮**：删除浮动 FAB，新增入口改为导航栏 `+`；首页 P&L 两行合并为一行 |
| 15 | `eb7b054` | **V1.0 收尾**：设置信息架构、原生 1.0 数据基线、截图宿主改为非示例模式、本文件与 FAB 相关的描述同步（§7） |
| 16 | `c171e73` | README 截图全部换成本轮 CI 产出的图；README / HELP / issue 模板的导航路径与按钮文案同步到新架构 |
| 17 | `f031d0c` | README 文案与实际 App 对齐（去掉不存在的「清空」、修正 `import.png` 的截图标题与 Demo 标签）；删两个无引用的旧 demo 文案键 |
| 18 | 本提交 | Help 的账本格式说明去掉「测试版 / 旧 Web 版」措辞（只留兼容边界）；§3 的词条数同步为 536 |

聚合改动量（`git diff --shortstat 62b7b49^..c5021b2`；**不含** §7 的最后两轮）：

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
| **P1b**（措辞、百分比、FAB 进安全区） | ✅ 完成 | `33717bf` | PASSED | `checks` `35493290106` / `build-ios` `35493290097` 双绿 |
| **P2a**（曲线可读性） | ✅ 完成 | `ebdd64f` | PASSED | `checks` `35494951130` / `build-ios` `35494951117` 双绿 |
| **P2b**（术语统一 + 日志冒号） | ✅ 完成 | `573310d` | PASSED | `checks` `35495603492` / `build-ios` `35495603480` 双绿 |
| **V1.0 收尾**（设置 IA + 1.0 基线 + 截图，§7） | ✅ 完成 | `eb7b054` | PASSED | `checks` `35499085353` / `build-ios` `35499085355` 双绿 |

单项细节见 `docs/ENGLISH_UI_P0_REVIEW.md` / `_P1_REVIEW.md` / `_P2_REVIEW.md`。

> **FAB 已经成为历史**：`33717bf` 当时把浮动 FAB 移进安全区并在设置页隐藏（要求原文承认它是 overlay 方案的补丁）。
> 最终 UI 轮 `006306b` 直接删掉了这个 FAB，新增入口改为 **Holdings / Trades 导航栏右上角的 `+`**（示例模式下不显示）。
> 因此所有“FAB 不遮挡内容”“Settings 不显示 FAB”这类要求都已按当前实现改写（§4 第 7 项、§5 第 4 条、§七 第 10/11/14 项），
> 不再把 overlay 时代的约束当作待验证项。

**P2-2（Settings 的 Data & Privacy）判定为「已经被满足」，没有新增 UI**：审计书要求「与真实实现一致才加入」，
四条都能从代码确认，而且都已经写在用户看得到的地方（证据表见 P2 报告 §1）。再加一节只会变成重复文案。

## 3. Test results

| 套件 | 规模 | 结果 |
| --- | --- | --- |
| Vitest（逻辑引擎，`tests/*.test.ts`） | 148 用例 / 13 文件 | **148 passed**（本地与 CI 一致） |
| 原生 Swift（`tests/native`，`scripts/test-native.sh`） | 固定断言 **397 → 408 → 414 → 413**（P1b → P2a → P2b → V1.0 收尾），见下方说明 | CI `macos-26` **PASS** |
| Playwright E2E（`e2e/*.spec.ts`） | 26 用例 / 8 文件 | CI `ubuntu-latest` **26 passed**；V1.0 收尾本地也实测 **26 passed (45.8s)** |
| 质量门禁 `scripts/verify.ps1` | 每个批次都跑过（P0、写入侧/格式边界、P1a、P1b、P2a、P2b、V1.0 收尾） | 全部 **QUALITY GATE PASSED**（V1.0 收尾：13 files / 148 tests passed） |

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
> | V1.0 收尾 `eb7b054` | 467 | 54 | 413（−1）|
>
> 两次增量（+11、+6）与本轮新增断言数**逐条对上**；只看总数会误以为多出了 18 条。
> V1.0 收尾那行的 −1 同样是逐条对上的：`LanguageTests.generatedNotes()` 删掉一条与 `net` 用例重复的空 `note` 断言，
> 同时新增两条「1.0 前写进 note 的说明原样显示」断言，净 −1。

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

最后一次扫描结果：`i18n-scan` **literals=1234 / raw=0**（裸字面量归零）；
`leak-scan` **composed=0**、`notInDict=5` —— 这 5 条是：4 条 CSV/结单的**输入别名**
（`CsvImport.swift` 的 `备注`/`说明`/`买`/`卖`，必须保持中文才能匹配中文券商导出）、
1 个永不渲染的死常量（`CsvImport.template`，见 §5）。
（原第 6 条是 `Models.swift` 里用于**比对**历史 note 的 `"汇丰月结单；交收日 "` 常量，
本轮删除 1.0 前的兼容分支后它一并消失。）
没有一条是渲染出来的界面文案。
`en-values` 536 条（V1.0 收尾删掉 2 个已无引用的旧 demo 文案键后的值；本轮刚开始时是 538）、0 重复、0 空值、0 条英文值含 CJK/全角。

> 提交 16 以后只动了文档 / 注释 / 用户可见文案（`c171e73`、`f031d0c`、`e72a57b`、`1017ed7`、`6ef18e9`），
> 其中带 `.swift` 的 `e72a57b` 已经跑过 CI：`checks` `35500279164` / `build-ios` `35500279299` **双绿**；
> 之后的 `1017ed7`、`6ef18e9` 只改 `*.md`，按两个 workflow 的 `paths-ignore` 本来就不触发 CI，
> 其 pre-commit 门禁各自打印 `QUALITY GATE PASSED`。每一步都重跑了词典一致性扫描
> （`swift-scan` OK、`check-l10n` 0 条缺译、只有 1 条已知的 `期初前有 {} 笔交易。`）；
> 代码与截图的首次 CI 证据是 §3 `build-ios` `35499085355`（对应 `eb7b054`）。
`swift-balance` 会报 `PROBLEMS=1`（`L10n.swift` 圆括号净差 +1）：这是该脚本的已知误报——
`"报价较早（": "Quote is stale ("` 这类键把半个全角括号放在中文侧、另一半在下一行英文侧，
ASCII 括号计数跨行不配平；HEAD 版本同样 `net=1`，与本轮改动无关。

## 4. Manual verification checklist（只有真机 / 人能做的）

CI 在模拟器上真的启动过 App（`scripts/test-screenshots.sh` 渲染 6 屏：holdings / trades / returns / settings / calendar / import，每张图存在且 ≥20KB 防空白，日历屏另断言 `days>0 months>0`），但以下项目模拟器与 CI 覆盖不到，需要你在真机上过一遍：

| # | 怎么验 | 期望 |
| --- | --- | --- |
| 1 | 真机安装 1.0.1 IPA 并冷启动 | 正常进入，无闪退 |
| 2 | 设置 → 显示 → 语言：中文↔English 来回切 | 标题、说明、日期、单位全部跟着变；**不出现中文残留**（重点看收益卡片标题与说明行、交易页汇总、现金账本） |
| 3 | 1.0 之后导入过汇丰结单的账本上切到英文 | 交易与流水的说明行显示英文（由 `settlementDate` / `source` 重建），已持久化的数据一字未改。**注意**：1.0 之前导入、`note` 里已写死中文说明的行会原样显示中文——那不是漏译，而是「1.0 前数据不是兼容目标」的既定口径（§7） |
| 4 | 把 iOS 系统文字大小调到最大 | 三行汇总（`In range N trades` 那几行）不截断、不重叠 |
| 5 | 深色 / 浅色模式各看一遍 | 曲线的参考值与刻度可读；涨跌颜色偏好生效 |
| 6 | VoiceOver 打开，遍历持仓 / 交易 / 收益 | 图表有整体朗读（当前 / 最高 / 最低 / 交易日数）；金额读成数字而不是逐字 |
| 7 | 小屏 iPhone（SE / 320pt 级） | 无横向溢出；导航栏右上角的 `+` 与标题不重叠，列表最后一行不被任何浮层压住（已无浮动 FAB） |
| 8 | 交易表单备注输入 > 500 字后保存 | 英文模式提示 `Note is at most 500 characters.`（中文模式 `备注最多 500 字。`） |
| 9 | 收益页同步历史后看累计收益曲线 | 右侧出现上限 / 零 / 下限三个参考值，且不与曲线重叠 |
| 10 | 设置 → 数据 → 备份与恢复 → 从备份恢复，选一个 1.0 之后导出的 JSON | 正常恢复；若文件被截断或来自更高版本，进入写保护并提示，不覆盖原文件 |
| 11 | 设置首页逐个点开（§7 的新信息架构） | 首页只有 `显示 / 行情数据 / 数据 / 支持` 四组入口，没有说明段落与操作按钮；每个二级页都能返回，且二级页里没有新增记录入口（`账本信息` 全部是只读行，`期初余额` 未设置时显示 `未设置`、现金余额那一行不出现） |

## 5. Known limitations

1. **`CsvImport.template`（`CsvImport.swift:611`）是死代码**：`78a2d7d` 引入后从未被引用，样例行里有一个中文单元格。
   它渲染不到界面，所以**不会**泄漏中文；但一旦有人把它接进界面就会。本轮按审计书 §六「不做无关删除」没有动它，
   建议后续单独清理（删掉，或把示例单元格写成英文）。
2. **曲线没有逐日读数**（审计书 P2-1 方案 B）。现有实现是不接受交互的 `CAShapeLayer` 视图，
   做长按拖动要先跟外层 `List` 的滚动手势做仲裁；本机没有 Swift 工具链、行为改对没改对无法本地验证，
   因此只做了方案 A（参考值）。升级路径写在 `ProfitPlotView` 的 `ponytail:` 注释里。
3. **中文 `账户总收益` 与英文 "Total return incl. dividends and fees" 措辞不同、口径相同**。
   英文改的是「别夸大成 account」；中文要不要一起改是产品文案决定，本轮未动中文键。
4. **纯视图层改动没有行为断言**：P1b 的账户级百分比守卫，以及 `006306b` 的「删掉浮动 FAB、改为导航栏 `+`、合并 P&L 两行」，
   在 CI 里只由 `xcodebuild` 覆盖到「能编译」；语义靠真机清单第 7 项确认，截图里能看到 `+` 与合并后的行（见 §7）。
   这是本阶段测试覆盖最薄的一处，如实标注。
5. **`Diagnostics` 日志在所有语言下都保留中文原文**（例如 `上次运行没有正常结束（闪退或被强制退出）。`）。
   有意为之：日志是给人回查的诊断材料；本轮只统一了分隔符。
6. **`scripts` 侧的质量门禁不包含原生测试**（macOS-only），所以「本地全绿」不等于「原生全绿」——
   原生与模拟器检查一律以 CI 为准。这也是 P0 阶段踩过「假绿」后写进 `AGENTS.md` 的原因。
7. 早期 Web 版（`src/` + `tests/`）与本轮无关，仍保留用于构建与回归；它不是当前 UI，本轮没往它加功能。
8. **1.0 之前的数据不是兼容目标**（§7）：`Fmt.tradeNote` / `Fmt.cashNote` 不再识别旧版本写进 `note` 的系统文案，
   这类行在英文界面下会原样显示中文。数据安全底线不变——已持久化的 `note` 永远不会被系统文案覆盖。
   `src/`（旧 Web 版）自己的升级逻辑与夹具保留不动：它属于另一个已下线的产品，不在本轮清理范围内。

## 6. 是否已经达到 Portfolio-ready 状态

**结论：英文 UI/UX 层面已达到 Portfolio-ready；「可公开展示」的其余部分仍取决于真机验证。**

判断依据：

- 审计书列出的 P0 / P1 / P2 项**全部处理完**，每一项都有对应的提交、本地门禁结果与远端 CI 记录；
- 英文模式下**产品自身产生的中文文本为 0**（`i18n-scan` raw=0；`leak-scan` composed=0，这是 P0 那条根因的可验证形式）；
- 三套测试在 CI 上全绿，且本阶段每一处逻辑改动都留了可运行的断言或可重放的脚本；
- 交付物齐备：审计（Phase A）、三份 review、最终审计、以及未跟踪的用户任务书原件。

要保持成立，需要在真机上完成 §4 的 11 项（尤其是第 2、3、7、8、11 项：语言切换、1.0 后数据的说明重建、小屏、超长备注、设置信息架构）。
在真机清单跑完之前，本文件不把「无明显 Crash」「应用可正常启动」标成「已验证」——
模拟器启动成功不等于真机启动成功。

## 7. V1.0 收尾（本轮）

以 Native SwiftUI 版为 **Stock Ledger 1.0 的产品基线**，本轮做三件事，**不增加功能、不改业务逻辑与金融计算、不加依赖**：

1. **设置信息架构**（`ios/App/App/StockLedger/SettingsView.swift`）：首页只留分类与入口，四个分组 `显示 / 行情数据 / 数据 / 支持`；
   原来的操作与说明全部移入二级页：`语言`、`外观`、`涨跌颜色`、`行情来源`、`导入与导出`（CSV / 结单 PDF / 错误日志）、
   `备份与恢复`（导出 / 恢复 / 当前账本 / 上次备份）、`账本信息`、`示例`、`帮助`、`关于`。
   `账本信息` 是**只读**页（笔数、账本格式、期初余额、能算出来才显示的现金余额）；
   `clearAll()` 本身没有任何 UI 调用，本轮也没有把它暴露出来——把它摆到设置里就是新增一个危险功能。
   所有二级页写在同一个文件里，避开新增 Swift 文件所需的 pbxproj 四处登记 + `scripts/test-native.sh` 两处同步（那是踩过的假绿陷阱）。
2. **1.0 数据基线**：删除为 1.0 之前测试版保留的兼容分支——`Fmt.tradeNote` / `Fmt.cashNote` 里「`note` 逐字等于旧模板才重建」那一支。
   现在只在 `note` 为空时生成说明；`note` 非空（用户写的，或 1.0 前版本写进去的系统文案）一律原样显示，
   但**系统文案仍然不会覆盖已持久化的值**（数据安全底线不变）。`Ledger.currentFormat`（= 2）与 `LedgerStore.decode` 的格式守卫保持不变，
   作为 1.0 起的稳定边界。界面上的开发历史文案（「沿用此前原生 2.0 测试版的数据」等）一并清掉，口径同步到 `DATA-COMPATIBILITY.md`。
3. **README 截图**：截图宿主 `tests/native/ScreenshotsApp.swift` 改为「用示例账本数据、但不进入只读示例模式」，
   并把备份提醒按「刚备份过」处理——这样 Holdings / Trades 截图能看到最终设计的导航栏 `+`，又不会拍到属于个人状态的过期提醒；
   正式业务行为一行未改。旧截图全部替换为这一轮 CI 产出的图（来源：`eb7b054` 的 `build-ios`）。

本轮本地实测：`verify.ps1` **QUALITY GATE PASSED**（Vitest 148 / 13 files ✓、`tsc --noEmit && vite build` ✓）、
`pnpm e2e` **26 passed (45.8s)**；原生与模拟器检查按既有约定以 CI 为准。

本轮 CI（`eb7b054`）：`checks` `35499085353` 成功；`build-ios` `35499085355` 成功，其中原生测试打印
`PASS: 467 assertions; … main actor heartbeats: 54` → 固定断言 **413**（与上文推算的 −1 对得上），
`Render production calendar on iPhone simulator` 与 `Render English UI screenshots` 两步均成功。
6 张新截图从该 run 的 `App-screenshots` 产物取出，人工核对后落回 `docs/screenshots/`：
`holdings.png` / `trades.png` 都拍到了导航栏 `+` 且没有备份提醒条，`settings.png` 是新的四组 IA
（Display / Market data / Data / Support），`import.png` 与旧图逐字节相同（该屏本轮未动）。
`returns.png` / `calendar.png` 与旧图不同属预期：示例账本按 `now` 生成，两次出图不冸同一天。

由此带来的两处口径变化，必须写清楚，否则会变成新的「过时要求」：

- 真机清单第 3 项（§4）的期望变了：**1.0 之前导入、`note` 里已经写死中文说明的行，在英文界面下会原样显示中文**。
  这是「1.0 前数据不是兼容目标」的直接后果，不是漏译。
- `LanguageTests.generatedNotes()` 净少一条断言（删掉一条与 `net` 用例重复的空 `note` 断言，新增两条「1.0 前写进 note 的说明原样显示」断言），见 §3。

## 附录：审计书 §七 Definition of Done 逐项

| # | 检查项 | 状态 | 证据 |
| --- | --- | --- | --- |
| 1 | English 模式没有产品自身产生的中文文本 | ✅ | `i18n-scan` 裸字面量 **raw=0**（修复前是 1，见 §3）；`leak-scan` **composed=0**；536 条英文值 0 条含 CJK/全角（V1.0 收尾后重跑），且 396 个代码引用键全部命中词典（独立复核，0 缺译） |
| 2 | 日期 locale 正确 | ✅ | `RootView.displayLocale` + `.environment(\.locale, …)`；数据层仍用 `DateFormatter.ledgerDate`（`en_US_POSIX`）；`LanguageTests` 覆盖切语言重算 |
| 3 | Trades Date Range 实际过滤正确 | ✅ | `Engine.range` + `EngineGoldenTests.rangeSummary()` 断言区间外那笔不计入 |
| 4 | All / Buy / Sell + Date Range 组合正确 | ✅ | 同上；只看卖出时买入侧笔数与金额必须为 0 |
| 5 | Cash Ledger 不存在 misleading $0.00 | ✅ | `InsightsView` 以 `opening != nil` 判断，未设置期初显示 `—` + 说明，不再显示 $0.00 |
| 6 | Holdings Daily P&L 语义清晰 | ✅ | `TodayCard` 标题 `Daily P&L` / `Today's P&L`，说明行 `As of market close`（P1b） |
| 7 | Securities Return / Account Return 区分清晰 | ✅ | P2-3：`Securities return` 与 `Total return incl. dividends and fees`；说明行「入金出金不计入收益」 |
| 8 | 关键 return percentage 正确 | ✅ | 持仓页 `Unrealized P&L %` 分母是持仓成本且 `cost > 0` 守卫；已实现不给百分比（代码注释写明理由） |
| 9 | Trades Summary 不再跨证券累计 shares | ✅ | P1a：`RangeResult` 删掉 `buyQuantity` / `sellQuantity`，改为按侧笔数 + 不含费金额 |
| 10 | 新增入口不遮挡任何内容 | ✅ | `006306b`：浮动 FAB 已删除，新增入口是导航栏 `+`（`.toolbar`），不参与列表布局，遮挡问题从根上不存在；P1b 的 `safeAreaInset` 补丁随之作废 |
| 11 | Settings 不显示新增入口 | ✅ | `006306b`：`+` 只挂在 Holdings / Trades 的导航栏上，Settings 页没有任何新增入口（示例模式下 `+` 也不显示） |
| 12 | Holdings / Trades / Returns 金融数字互相 reconcile | ✅ | `EngineGoldenTests` 「每日收益之和与曲线一致」（`:230`）；`NativeTests` 「平仓后每日收益 reconcile 到已实现收益」（`:138`） |
| 13 | Existing tests 全部通过 | ✅ | 148 Vitest / 413+ 原生固定断言（含心跳，见 §3）/ 26 E2E，本地与 CI 一致 |
| 14 | 新 bug fix 有对应 regression tests | ⚠️ 除纯视图层改动外 ✅ | 见表 §3；**P1b 与 `006306b` 的视图层改动只由 `xcodebuild` 覆盖编译、没有行为断言**（§5 第 4 条）；1.0 基线相关的逻辑改动有 `LanguageTests` / `SafetyTests` 的断言与 `.scratch/replay-notes.mjs` 的本地重放 |
| 15 | English / Chinese smoke test 通过 | ✅ | CI 渲染 6 屏英文截图（`test-screenshots.sh`：每张 PNG 存在且 ≥20KB 防空白，并对日历屏断言 `days>0 months>0`）；中文路径由 `L10n.tr` 在 `.zhHans` 直返键覆盖，`LanguageTests` 两种模式都断言。截图宿主自 V1.0 收尾起改为**非示例模式 + 示例数据**（§7），因此 Holdings / Trades 截图里能直接看到导航栏 `+`，这两屏的视图层改动不再只靠真机确认 |
| 16 | 没有 unrelated changes | ✅ | 提交范围只含审计书的 P0/P1/P2 项，加上 `LedgerValidation` 默认标签（同属 P0 那条「值没本地化」根因）；两份用户任务书始终未跟踪 |
| 17 | 没有 debug code / temporary files | ✅ | `verify.ps1` 的「被跟踪的构建产物」「会进提交的散落调试文件」两项 PASS；所有草稿与脚本都在已忽略的 `.scratch/`（`.gitignore:26`） |

