# FINAL RELEASE AUDIT

审计日期：2026-09-22。审计对象：GitHub `main` 的 `b6ee84dc77bd9ddf5985f072fd3f4dafb7bc05bd`；正式发布：`v1.0.1`，源码 `bd890f1990e0a70bd8c9d2e03a67a4aa82c45b29`，版本 1.0.1 build 6。

## Executive Summary

未确认 P0；发现 2 项 P1、6 项 P2、1 项 P3。主要风险是导入顺序改变已实现收益，以及备份页可能导出过期内容。现有 CI、构建和发布资产有可追溯证据，但测试通过未覆盖这些业务场景。

这是跨仓库领域的静态审计、现有 CI 证据核验和局部算法复核，不是所有输入的穷举证明。未运行新一轮 iOS 真机、模拟器或 Swift 测试，未验证每个第三方接口的在线响应，也未进行二进制截图/视频的逐帧隐私检查。下文明确区分确定代码路径与待设备复现的界面现象。

本地 `stock-ledger-recovered` 的 main 实际仍在 `aefe676`。为遵守不修改现有文件的要求，仅 fetch 更新远端引用，使用 `git show` / `git grep` 读取远端提交，没有 pull、checkout 或合并。报告是唯一新增文件。原有未跟踪文件保持原样。

当前远端 main 与发布源码之间没有生产 Swift 代码差异，后续变化主要是发布清单修正、合成 PDF fixture、测试和文档。因此下面的生产代码发现也适用于已发布 IPA 的对应源码。代码位置均指审计提交，而不是尚未同步的本地旧工作区。

## Release Verdict

**READY WITH KNOWN ISSUES**

适合作为如实说明能力与限制的 Portfolio Project；不应宣称财务与恢复链路完全无缺陷。建议针对两项 P1 做小范围修复评估，不需要恢复整轮功能开发。

## Findings Summary

P0: 0

P1: 2

P2: 6

P3: 1

| ID | Severity | 问题 |
| --- | --- | --- |
| F01 | P1 | 同日批量“插入之前”反转导入记录顺序，改变成本和已实现收益 |
| F02 | P1 | 备份导出缓存只随记录数量变化，可能导出旧账本 |
| F03 | P2 | SPY 同时是基准和实际持仓时，其历史收盘价被排除 |
| F04 | P2 | 重复 sequence 的违规键碰撞，仍可扩大历史超卖 |
| F05 | P2 | 原生备份解码缺少完整业务校验 |
| F06 | P2 | 备份选择器读取没有申请安全作用域 |
| F07 | P2 | 现金/期初/手动报价保存失败仍关闭表单 |
| F08 | P2 | PDF 成功导入后丢失副本 URL，退出清理失效 |
| F09 | P3 | 对全历史无 secret 的绝对声明超出可证明范围 |

以下各节引用相同 ID，不重复计数。

## Critical Findings

未确认 P0。没有发现正常启动必崩、当前发布构建失败、真实有效凭据泄露，或此前“恢复失败后解除写保护”的直接覆盖路径仍然存在。

这不表示不存在数据丢失风险：F02 可能令用户在设备丢失/重新恢复时缺少最新数据；其触发有特定操作条件，且不会立即破坏当前磁盘账本，归为 P1。

## Financial Logic Findings

### F01 — P1：批量插入反转同日内部顺序

- File / Location：`ios/App/App/StockLedger/CsvImport.swift:417`，`merge(_:_:insertBeforeSameDay:)`；同时被 `HSBCStatement.candidate` 调用。
- Evidence：对每笔 imported 交易分别查找 `firstIndex(date >= trade.date)` 并插入。第二筆同日记录会插在第一笔之前。
- Reproduction：已有 Jan 1 买 100 股 @10，Jan 2 买 1 股 @10。导入 Jan 2 的买 100 股 @20、随后卖 100 股 @30，选择插入已有同日记录之前，手续费均为零。
- Expected：Jan 1 买入 → 导入买入 → 导入卖出 → 原有 Jan 2 买入。已实现 1,500，剩余成本 1,510，剩余股数 101。
- Actual：Jan 1 买入 → 导入卖出 → 导入买入 → 原有 Jan 2 买入。已实现 2,000，剩余成本 2,010，剩余股数 101。
- Verification：以无文件输出的 Node 内存程序复演该插入算法并独立按移动平均法计算，得到上述差异。这是算法复演，不冒充 Swift 运行时测试。
- Risk：持仓数量正常、没有超卖，现有验证会放行；已实现/浮动收益分配发生 500 的错误。证券总收益在报价完整时可能仍相抵，因此只核对总收益会漏检。
- Recommended Fix：保留导入批次内部顺序，再将整个同日批次放在已有同日记录之前；为先有持仓、同日买卖混合、选择插入之前的情形留下独立手算断言。
- 是否值得解除封版：是。它影响正式支持的导入选项与核心成本口径，修复范围可局限于合并顺序。

### F03 — P2：SPY 持仓没有历史收盘价

- File / Location：`Store.swift:378–380`，`syncHistory()`。
- Evidence：SPY 的 sessions 会加入日历，但 `for point ... where symbol != "SPY"` 和后续 guard 把 SPY closes / incoming quote 一律排除。
- Reproduction：持有 SPY，清空历史或新建账本后同步历史。即使 Yahoo 成功返回 SPY 日线，账本仍不保存其历史 closes。
- Risk：SPY 收益日历长期待补；这是缺数据，不是伪造零收益。普通报价刷新可提供当前 SPY quote，不能补上历史 closes。
- Recommended Fix：日历基准用途与实际持仓用途分开判断。封版期间记录即可。

已检查的财务正常路径：买入费用进入成本；卖出费用扣减收入；清仓使用全部剩余成本；证券收益与现金外部流入分开；分红净额减账户费用只在账户总收益额外计入一次；无期初不推算真实现金余额。今日收益采用期末市值减期初市值再加卖出净额、减买入含费支出。缺必要行情返回 nil。日历对拆股采取待核对处理，不自动改股数，符合已声明范围。

## Security Findings

### F08 — P2：PDF 副本清理路径被提前清空

- File / Location：`StatementImport.swift`，`commit()`、`.onDisappear`、`cleanUpCopies(_:)`。
- Evidence：成功提交执行 `rows = []; urls = []`，离开页面才调用 `cleanUpCopies(urls)`，此时已没有路径。更换所选文件时也会替换 URL 数组。
- Reproduction：选择以副本交付的 PDF → 导入成功 → 离开页面；清理函数得到空数组。若副本位于代码打算清理的临时目录，不能执行预期删除。
- Risk：真实结单副本可能留在应用沙盒，直到系统清理；未发现将它上传服务器的代码。具体驻留时间取决于 iOS 文件选择器及临时目录生命周期。
- Recommended Fix：成功后释放 URL 前执行现有副本清理；更换选择时清理旧副本，并保持严格目录边界。此项不要求单独解除封版。

安全证据与边界：

- 当前跟踪内容的凭据关键字命中为 GitHub Actions token 引用与明确测试占位符，没有确认真实密钥。
- 对本地可达的 177 个提交执行历史私钥/常见 token 特征变更扫描，并检查历史凭据类文件名。未找到高置信真实 secret；这不能覆盖服务器已删除的分支、不可达对象、所有非标准 token 或图片中文字。
- HSBC PDF fixture 有可审阅的生成脚本、虚构姓名/账号和 SAMPLE 标识；旧 JSON fixture 明确注明非真实账本。未确认真实交易数据进入 fixture。
- 原生 Keychain 使用固定 service/account、更新或新增、读回验证；备份 Ledger 模型不包含 QuoteSettings / API Key。配置使用 AfterFirstUnlock，可按需提升保护级别，但没有证据需要因此解除封版。
- 请求使用 HTTPS、认证 header、禁止重定向、ephemeral session；网络错误转换为固定文案，不回显认证 URL。发送股票代码会向所选行情供应商披露关注的股票，这是产品文档已声明的行为。
- 诊断日志为本地文件，包含错误原因、股票代码、可能的文件名或结单引用编号；没有发现自动上传。分享日志是用户主动行为，不应把日志称为完全匿名。
- 未执行最新依赖漏洞数据库查询，因此本报告不作“所有依赖均无已知漏洞”的结论。

## Data Integrity Findings

### F02 — P1：备份页缓存不是当前账本快照

- File / Location：`SettingsView.swift:BackupRestoreView`，导出按钮及第 189–190 行的 `.onChange`。
- Evidence：按钮分享 `exportText`；它仅在 `.task`、交易数量变化、现金数量变化时重建。账本内容、期初、历史、报价变化不属于失效条件。
- Reproduction：进入备份页，账本 A 有 1 笔交易、0 笔现金；在同一页恢复账本 B，它也有 1 笔交易、0 笔现金，但买入价不同。恢复成功后直接导出。
- Actual：持久化和内存已是 B，两个 count 均未变化，缓存仍可为 A；导出的备份与实际账本不一致。该路径由状态依赖可确定，未在本轮 iPhone 上操作复现。
- Risk：旧内容被标记成刚完成的备份；用户随后丢失设备或依赖该文件恢复时丢失最新内容。当前磁盘文件不会因为导出本身被覆盖。
- Recommended Fix：分享动作发生时直接序列化当前 ledger，或以真正的账本修订号失效缓存；验证相同数量恢复后立即导出。
- 是否值得解除封版：是。备份可靠性直接关系数据恢复，修复不需要新功能或存储迁移。

### F04 — P2：重复 sequence 的历史超卖比较仍可绕过

- File / Location：`Engine.swift:Oversell.id`；`Store.swift:277–279`，`introducesOversell`。
- Evidence：违规键为 symbol/date/sequence；旧违规按键累加，新违规却逐项与旧总量比较。
- Reproduction：旧账本同一股票、日期、sequence 下依次 Sell 5、Sell 5，无买入，两个不同 UUID。旧缺口为 5、10，相加 allowed=15。把第二笔改为 Sell 9，新缺口为 5、14，均 <=15，于是放行，但最大超卖从 10 扩大到14。
- Risk：需要已有脏账本和重复 sequence；正常新建 sequence 不会触发。排序稳定并不能消除违规身份碰撞。
- Recommended Fix：使用不碰撞的交易身份及逐时点缺口约束，验证重复 sequence 的放大案例。

### F05 — P2：可解码不等于合法账本

- File / Location：`Store.swift:48`，`decode`；`Models.swift:Ledger` / `nextTradeSequence`。
- Evidence：解码只额外拒绝 format 大于 2，未校验交易/现金 ID 唯一性、负数量、负价格、日期、sequence 上界或资金字段关系。
- Reproduction：修改一个结构完整 JSON，将 sequence 设为 Int.max，恢复后新增交易会在 max+1 产生溢出 trap；负数量或重复 UUID 也可进入正常派生计算/删除路径。
- Risk：输入需经过篡改或由旧缺陷生成；未证明应用正常录入能自行生成这种文件，故未定为普通操作 P0。导入不可信 JSON 可产生错误财务结果甚至后续 crash。
- Recommended Fix：恢复和载入共用基本业务校验，明确既有超卖的兼容修复策略；避免把格式版本检查当作完整验证。

原有恢复失败问题已改善：`replaceFromBackup` 保存原 loadFailure，commit 失败后恢复它。该函数在 MainActor 同步执行、生产 persist 不悬挂；本轮未发现异步任务能在临时清空标记时插入写盘。普通写入走 commit；报价写入走带保护和 generation 校验的 commitRefresh；磁盘采用 atomic write。示例模式的 commit 与 commitRefresh 均拒绝落盘，退出重新读磁盘。

## Import Findings

F01 同时影响 CSV 与共享该合并函数的 PDF 导入。CSV 解析与预览具有字段映射、日期/十进制限制、重复编号提示；PDF 有页数/大小、账户一致性、币种、交收额与费用关联检查。PDF 提交会再次检查编号与当前账本，并整体提交。

CSV 候选提交重新验证持仓，但不是完整的恢复业务校验。解析器对未闭合引号等畸形 CSV 的容错、同一文件无编号重复记录、预览后账本变化的重复检查，仍值得定向测试。本轮没有为这些潜在盲区额外计入已证实缺陷。

### F06 — P2：备份恢复遗漏安全作用域

- File / Location：`SettingsView.swift:195`，BackupRestoreView 的 fileImporter success 分支。
- Evidence：直接 `Data(contentsOf: url)`，没有 `startAccessingSecurityScopedResource()` / 配对 stop。相邻 CSV/PDF 读取实现已有对应处理。
- Risk：从需要安全作用域的外部文件提供商选择合法备份可能读取失败；具体取决于 URL 来源，不能宣称所有备份都失败。
- Recommended Fix：沿用已有受控读取模式。需要 iCloud/第三方 Files provider 的设备恢复验证；不单独要求解除封版。

## iOS Findings

### F07 — P2：部分表单不等待保存结果

- File / Location：`InsightsView.swift:CashFormView.save`，`HoldingsView.swift:QuoteFormView`；Store 的 saveCash/setOpening/setQuote。
- Evidence：上述 Store 方法返回 Void；调用后直接 dismiss。RootView 未统一呈现 errorMessage。
- Reproduction：写盘因磁盘故障失败，保存现金或期初，表单仍关闭，内存/磁盘保持旧值，用户输入不再保留。
- Risk：用户误以为保存完成并失去输入；未发现此路径破坏旧账本。交易、CSV、PDF 的 Bool 检查更完善，不能据此推断所有表单都安全。
- Recommended Fix：传递提交结果，失败留在表单并显示现有错误。

Xcode 与 SPM 目标为 iOS 16。当前 CI 证明所选 Xcode SDK 可编译及新模拟器可启动，不证明 iOS 16 真机各文件提供商行为。本轮检索 force cast/unwrap、数组访问、后台派生与 MainActor：核心已读 unwrap 多数有 guard 或常量前提，未确认正常输入稳定触发 crash。报价工作并发、UI 生命周期、语言全局状态和真实滚动帧率仍不能靠后台耗时证明。

## Test Coverage Findings

已检查 NativeTests 入口和 test-native.sh，新增套件真实编译并调用，不是仅存在文件。GoldenTests 使用字面量及推导注释，有移动平均成本、费用、现金边界、缺报价、日收益断言；PDF fixture 既有生成器自检，也调用生产 PDFKit/HSBC parser。生成器模仿生产解析规则的自检本身不能作为独立业务正确性证明。

可核验 CI：

- `35509012130`：eadfb94，Native 日志 `PASS: 509 assertions`，其中 heartbeat 80 次；对应固定断言数 429。设备构建 `BUILD SUCCEEDED`。
- `35509012119`：eadfb94，Vitest 148 passed，Playwright 26 passed。
- `35504343869`：正式 IPA 的 bd890f1，结论 success。

Playwright 启动 Vite preview，测试 legacy Web UI，不能证明 SwiftUI 表单/备份弹窗正确。模拟器截图与日历非空检查也不能替代完整的交互测试。

缺少直接封住本轮风险的用例：F01 的批量插前买卖顺序；F02 的同数量恢复后导出；F03 的 SPY 实际持仓；F04 的重复违规键；F05 的不合法备份；F06 外部 Files provider；F07 写入失败表单保留；F08 成功导入后的副本清理。

本轮没有在旧本地工作区重复跑整套测试/Quality Gate，因为它不是审计源码，并且 gate 会生成 build/dist 文件，违反本轮唯一新增报告的限制。使用上述对应提交的既有 CI 证据，未声称新执行过本地测试。

## CI / Release Findings

发布链路具有实际证据：

1. 清单 `releases/v1.0.1.json` 指向 bd890f1、run 35504343869、build 6。
2. run 的 headSha 与清单相同且 success。
3. Release target 为同一源码提交。
4. GitHub IPA asset digest 与清单均为 `f28c24ccd80d0e4516369119bdbb045174245d7d7c8466cae4dbe60658a946a6`。
5. publish 脚本核对 run/workflow/hash/version/build；已发布资产只校验、不覆盖。verify-ipa 检查 ZIP、ARM64 Mach-O、iPhoneOS、bundle id、内嵌资源与无开发服务器依赖。

证据链接：[正式构建](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35504343869)、[当前生产代码等价的 macOS 验证](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35509012130)、[Web 检查](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35509012119)、[正式 Release](https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.0.1)。

本轮没有重新下载 IPA 做独立散列或安装，只核对 GitHub 返回的 digest 与构建记录。最新 b6ee84d 是文档提交，源码等价关系由 diff 确认，不把 eadfb94 的成功运行说成 b6ee84d 新跑的 CI。

pnpm 使用 frozen lockfile；package.json 与锁文件声明可对应，CI 已实际安装成功。build-ios 覆盖原生编译，checks 的 PR 验证仅覆盖 Web。publish 脚本没有额外强制 source run 的分支为 main；当前发布来源正确，未来流程可增加约束作为改进，不据此认定本次发布断链。

## Documentation Findings

### F09 — P3：全历史无密钥的绝对保证

- File / Location：README.md，Data & privacy / API keys 段。
- Evidence：宣称工作树或 git history 的任何地方均不存在秘密，而列举的验证主要是模式/文件名扫描。
- Risk：特征扫描不能识别所有自由格式 token、图片、不可达对象。未发现泄露不等于能够保证不存在泄露。
- Recommended Fix：以后维护文档时改为“已对范围内可达历史做特征扫描，未发现真实凭据”，并注明范围；不为此解除封版。

版本 1.0.1/build 6、format 2、bundle id、存储路径和 iOS 16 基本一致。README 当前固定原生断言 429 与 CI 509-80 可解释；旧 Release 的原生断言数量来自较早构建，不应机械要求与最新 fixture 数量相同。文档保留多个历史审计与 legacy Web 发布，属于历史资料，不是意外 build artifact。Markdown 路径初筛中 `releases` 是有效目录链接，不算坏链接。

## Technical Debt

- Swift 与 TypeScript 两套独立计算实现，测试数量不能互相替代；不建议封版期重构合并。
- Diagnostics 文本行截断不是严格字节上限；大单行错误仍可能超过标称 32KB，当前未证明严重影响。
- 原生磁盘载入、编码与部分表单 I/O 在主线程，大量数据时有响应性风险，未测出真机性能退化。
- 未跟踪 BUG 文档/任务书/嵌套目录不在发布树中，未删除或提交。
- 当前树有 intentional synthetic PDF、图片、历史发布清单及 legacy 资源；未见跟踪 IPA、node_modules、dist/build 产物或真实银行文件。
- 审计未逐一执行所有脚本、全量历史版本、每种文件格式与外部服务组合；以上不是覆盖率 100% 的安全认证。

## Final Recommendation

保留已封版版本与现有 Release 资产。两项 P1 值得安排一个范围明确的小修补版本：修正插入批次顺序、保证导出当前账本，并增加各自独立回归验证。不要为 P2/P3 或技术债恢复大范围开发。报告完成时没有修改任何生产代码、测试、版本、CI 或发布资产。

1. **是否存在 P0？** 本轮未确认。
2. **是否存在 P1？** 是，F01 与 F02。
3. **是否可能导致资金收益计算错误？** 是，F01 已给出差额复现；F04/F05 在异常账本下另有风险。
4. **是否可能导致 Ledger 数据丢失？** 是，F02 可能使备份缺失最新内容，后续恢复造成回退；未确认正常提交直接静默清空磁盘的 P0 路径。
5. **是否存在 secret/privacy 泄露？** 未确认真实 secret 或远程隐私外泄；F08 是本地敏感副本未及时清理风险，历史扫描有上述边界。
6. **CI 是否足以证明当前版本可构建？** 是，正式源码和当前等价生产代码均有成功构建记录；不代表业务无缺陷或所有 iOS 16 设备验证通过。
7. **是否适合作为 Portfolio Project 展示？** 是，应如实区分原生与 Web 测试，并披露已知问题。
8. **是否有必要解除封版继续修改？** 建议只为两项 P1 做小范围修补评估；没有发现必须因 P0 立即解除封版的证据。本轮只交付报告，不实施修复。
