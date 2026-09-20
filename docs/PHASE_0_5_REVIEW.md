# Phase 0.5 — Core Safety & Test Guardrails · Review

> 基线：`portfolio/audit` @ `5e2b306`（含 Phase 0 审计报告）。
> 本阶段分支：`portfolio/core-safety`。**未触碰 `main`**。
> 只处理 Phase 0 发现的 P0-1、P0-2，以及为 `Engine` 建立最小测试护栏。
>
> 本文描述的是**当前最终实现**。第一轮实现（`5a436b6`）在 Codex 审查后被修正，见「修复历史」。

## Files Changed

### 提交 1 — `b09cb02` `test: add Engine golden tests with hand-derived expected values`

| 文件 | 变化 |
| --- | --- |
| `tests/native/EngineGoldenTests.swift` | 新增，14 组金标准用例 |

### 提交 2 — `5a436b6` `fix: protect an unreadable ledger and enforce the manual trade position invariant`

| 文件 | 变化 | 说明 |
| --- | --- | --- |
| `ios/App/App/StockLedger/Store.swift` | +78 / −12 | P0-1：`LoadResult`、`loadFailure`、写入守卫、恢复入口；P0-2：`introducesOversell` 守卫 |
| `ios/App/App/StockLedger/Engine.swift` | +18 | P0-2：新增纯函数 `oversoldTrade(_:)`（按时间顺序重放） |
| `ios/App/App/StockLedger/L10n.swift` | +2 | 两条英文词条（读取失败说明、超卖说明） |
| `ios/App/App/StockLedger/RootView.swift` | +10 | 顶部横幅：账本读取失败时提示写入已暂停 |
| `ios/App/App/StockLedger/SettingsView.swift` | +1 / −1 | 「替换并恢复」改走 `replaceFromBackup`（读取失败后唯一放行的写入路径） |
| `tests/native/SafetyTests.swift` | 新增 | P0-1 / P0-2 回归测试 |
| `tests/native/NativeTests.swift` | +2 | 调用两个新测试入口 |
| `scripts/test-native.sh` | +1 / −1 | 把两个新测试文件加入编译列表 |

`git diff --stat`（相对 `5e2b306`，不含两个新增文件）：

```
 ios/App/App/StockLedger/Engine.swift       | 18 +++++++
 ios/App/App/StockLedger/L10n.swift         |  2 +
 ios/App/App/StockLedger/RootView.swift     | 10 ++++
 ios/App/App/StockLedger/SettingsView.swift |  2 +-
 ios/App/App/StockLedger/Store.swift        | 78 ++++++++++++++++++++++++++----
 scripts/test-native.sh                     |  2 +-
 tests/native/NativeTests.swift             |  2 +
 7 files changed, 102 insertions(+), 12 deletions(-)
```

**未包含**：README、LICENSE、Demo Mode、UI Polish、依赖升级、CI 工作流、重构、格式化整文件、生成物、密钥、调试数据。

### 修复历史

| 提交 | 内容 |
| --- | --- |
| `5a436b6` | 第一轮实现（P0-1 + P0-2）。Codex 审查后发现有 5 处缺陷，见下。 |
| `7420ca3` | 第二轮：修复审查发现的 5 个问题（恢复失败错误解除保护、既有超卖绕过守卫、删除失败无反馈、CSV 假报成功、同日 sequence 排序不确定） |
| `b2e693e` | `deleteTrade` 写盘失败时不再提前清掉 `undoTrade` |
| `8ffa75d` | 测试基础设施修正：注入的 persist 在成功分支必须真的写盘；两处解码改 `try?` + 断言，失败报 `FAIL:` 而不是把进程抛崩 |
| 本轮（第三轮） | 消除重复排序（`HoldingsView` 的相关交易列表也改用统一规则）、保存路径短路、失败路径必须留下 `errorMessage` 的契约断言 |

第二轮相对第一轮的差异：

```
 ios/App/App/StockLedger/CsvImport.swift    |   6 +-
 ios/App/App/StockLedger/Engine.swift       |  26 +++--
 ios/App/App/StockLedger/ImportView.swift   |   9 +-
 ios/App/App/StockLedger/L10n.swift         |   2 +
 ios/App/App/StockLedger/Models.swift       |  21 +++-
 ios/App/App/StockLedger/SettingsView.swift |   4 +-
 ios/App/App/StockLedger/Store.swift        |  42 +++++---
 ios/App/App/StockLedger/TradesView.swift   |  14 ++-
 tests/native/SafetyTests.swift             | 164 ++++++++++++++++++++++++++++-
 9 files changed, 252 insertions(+), 36 deletions(-)
```

## P0-1 Fix

**问题**：`LedgerStore.load()` 用两处 `try?` 把「文件不存在」「读取失败」「解码失败」全部折叠成空账本；而 `save` 使用 `.atomic` 整体替换原文件 → 一次静默的空账本加载之后，任何一次保存都会永久覆盖仍可抢救的原文件。

**修复**：让「读不出来」成为一种显式状态，并在状态存在时冻结写入。

| 位置 | 变化 |
| --- | --- |
| `Store.swift` `LedgerStore.LoadResult` | 新增三态：`.missing`（首次启动，合法）/ `.loaded` / `.failed(reason)` |
| `Store.swift` `LedgerStore.loadResult()` | 先 `fileExists` 再读；`Data(contentsOf:)` 与 `JSONDecoder` 的失败不再被吞掉，返回 `.failed` |
| `Store.swift` `AppState.loadFailure` | 新增 `@Published private(set) var loadFailure: String?` |
| `Store.swift` `AppState.init` | `ledger` 参数改为 `Ledger? = nil`；nil 时走 `loadResult()` 并按结果分支初始化 |
| `Store.swift` `commit(_:)` | `loadFailure != nil` 时直接拒绝，不调用 `persist` |
| `Store.swift` `commitRefresh(_:)` | 同上（自动行情同步也不会写入） |
| `Store.swift` `replaceFromBackup(_:)` | 新增：用户明确选择备份恢复时，**只有在备份真正写盘成功后才**解除保护并整体替换；失败时保护状态、内存账本与原文件都不变 |
| `SettingsView.swift` | 「替换并恢复」按钮改调 `replaceFromBackup` 并**检查返回值**，失败时弹错而不是静默关闭 |
| `RootView.swift` | 顶部横幅显示读取失败与「写入已暂停」 |
| `L10n.swift` | 新增中英词条 |

**行为对照**

| 场景 | 修复前 | 修复后 |
| --- | --- | --- |
| 首次启动无文件 | 空账本，可写入 | 空账本，可写入（`.missing`） |
| 有效文件 | 正常读取 | 正常读取（`.loaded`） |
| 文件损坏 | 静默变空账本；下一次保存即覆盖原文件 | 显式失败 + 顶部横幅；`commit` / `commitRefresh` 全部拒绝；**原文件字节不变** |
| 损坏后想恢复，但写盘失败 | —— | `replaceFromBackup` 返回 `false`，`loadFailure` **原样恢复**，之后交易/现金/报价/导入/清空/示例全部仍被拒，原文件字节不变 |
| 损坏后想恢复，写盘成功 | —— | 解除保护、内存账本更新、备份落盘，普通保存恢复 |
| 损坏后想恢复 | 只能卸载重装 | 设置 → 从备份恢复（唯一放行的写入路径） |

**实现方式**：`load()` 被整体替换而非保留（唯一调用点是 `AppState.init` 的默认参数），避免留下仍会静默返回空账本的旧入口。

**测试用的最小接缝**：`LedgerStore.fileURLOverride`（`static var`，正常运行恒为 `nil`）把读写重定向到临时目录，使上述场景可被自动验证，且测试不会碰到真实 `Documents`。

## P0-2 Fix

**问题**：导入路径有整批 `validate`（超卖即拒绝），但手动录入路径没有——`TradeFormView.save` 只校验正数/日期/代码，`AppState.saveTrade` 直接追加并写入，`deleteTrade` 无任何检查。持有 10 股卖出 15 股会写盘：`quantity` 变 −5、`cost` 变负、持仓从列表消失而已实现盈亏虚高。

**修复**：在**状态层**（而非按钮层）加交易不变量守卫，采用**按时间顺序重放**而不是只看最终数量。

| 位置 | 变化 |
| --- | --- |
| `Engine.swift` `Engine.Oversell` + `oversells(_ ledger:)` | 新增纯函数：按时间顺序重放，返回**每个**「卖出 > 当时可用股数」的时点，键为 `symbol|date|sequence`，值为超额股数（负持仓向后续时点累计） |
| `Store.swift` `AppState.introducesOversell(_:)` | 私有守卫：把旧账本的违规建成 `[键: 超额]` 字典；`next` 的每个违规键都能找到且超额未扩大才放行，否则写 `errorMessage` 并拒绝 |
| `Store.swift` `saveTrade(_:)` | 在 `commit` 之前调用守卫 |
| `Store.swift` `deleteTrade(_:)` | 改为 `@discardableResult -> Bool`，在 `commit` 之前调用守卫；写盘成功后才清 `undoTrade` |
| `Store.swift` `undoLastTrade()` | 改为 `@discardableResult -> Bool`，失败不再静默 |
| `TradesView.swift` | 滑动删除与「撤销新增」检查返回值，失败弹出「操作未完成」alert |
| `Engine.swift` / `Models.swift` | 排序规则收敛成一处：`Ledger.sortedTrades/sortedCash`，显式用数组下标做最终判据 |
| `CsvImport.swift` | `merge` / `mergeCash` 复用同一排序规则（`mergeCash` 顺带从两次排序减为一次） |
| `L10n.swift` | 新增超卖、操作失败的中英词条（带 `{}` 占位符：代码 + 日期） |

**为什么必须逐笔重放**：`Jan1 买 100 / Jan2 卖 100 / Jan3 买 100` 的最终持仓是 100，看起来合法；删掉 Jan1 的买入后 Jan2 就已超卖。只比较最终数量会漏掉这个洞，因此守卫按时间顺序重放（与 Web 版 `src/ledger.ts` `calculate` 的逐笔检查口径一致）。

**为什么不能「旧账本不合法就一律放行」**（第一轮的缺陷）：只要账本里已经有任何一笔超卖，之后所有仍然非法的写入都会被放行——包括新增另一只股票的超卖。现在的规则是**逐违规时点比较**：

| 情况 | 判定 | 原因 |
| --- | --- | --- |
| 删掉违规卖出 / 补更早买入缩小超额 | 允许 | 违规键不变、超额变小或消失——这是在**修复** |
| 与违规无关的合法操作（如新增 MSFT 买入） | 允许 | `next` 的违规集合与旧账本完全一致 |
| 新增另一只股票的超卖（NVDA Buy 10 / Sell 20） | 拒绝 | 出现旧账本里不存在的违规键 |
| 把已有超卖从 10 股扩大到 50 股 | 拒绝 | 同一违规键，超额变大 |
| 把违规提前到更早的历史时点 | 拒绝 | 违规键的 `date` 变了，视为新违规 |
| 删掉买入导致中间时点悬空 | 拒绝 | 产生旧账本里不存在的新违规键 |

**性能**：正常账本（无违规）只跑一遍重放就返回；只有确实存在违规时才再跑一遍旧账本，用于比对。

**双层保护**：`TradeFormView` 的「当前可卖 / 一半 / 全部」（`TradesView.swift:224-227`）仍然保留为 UI 层提示；本次新增的是不可绕过的状态层守卫。

## Tests Added

### `tests/native/EngineGoldenTests.swift`（14 组）

所有期望值均由夹具输入**人工推导**后写成字面量，没有任何一处用 `Engine.*` 的输出当期望值。

| 分组 | 用例 | 关键断言（人工推导值） |
| --- | --- | --- |
| `Engine.summary` | 多笔买入 | 成本 2202、股数 20、均价 110.1、市值 2600、浮动 398、费用 2 |
| | 部分卖出 | removed 550.5、剩余成本 1651.5、**均价仍是 110.1**、已实现 198.5、浮动 298.5、总盈亏 497 |
| | 全部卖出 | 清仓那笔 747、合计已实现 945.5、无未平仓时市值/浮动为 0、费用 4.5 |
| | 缺行情 | 市值 / 浮动 / 总盈亏全部为 `nil`（不按零），但成本仍可算 |
| `Engine.cashTotals` | 分红 / 税费 / 出入金 | externalNet 18500、investNet 24.25、余额 23122.25；同一账本 `summary.realized == 198.6`——证明现金流水不进证券收益 |
| `Engine.dailyReturns` | 正常三连 | 0 / 20 / −10；累计曲线 0 / 20 / 10（收益之和与曲线自洽） |
| | 现金流隔离 | 加入入金/出金/分红/费用后逐日 `profit` 与 `cumulative` **完全不变**；同时余额从 5000 变 12439.5（证明记录确实被读到，排除假阳性） |
| | Gap | 相邻收盘记录之间夹未确认工作日 → 当日 `profit == nil` |
| | 缺当日收盘 | `profit == nil` 且 `cumulative == nil` |
| `Engine.todayPnl` | 正常 | 期初 10×110=1100、期末 10×121=1210 → 110；基准 1100；百分比 0.1 |
| | 缺上一收盘 | pnl / percent / basis 全部 `nil` |
| | 当日加仓 | 15×121 − 10×110 − (5×120+2) = 113 |
| | 当日卖出 | 6×130 − 10×110 + (4×130−1) = 199（用 sellNet 而非 gross） |
| | 基准日期错位 | `previousCloseDate == today` → `nil` |

> 交叉核对：同一组夹具与同一组期望值先在 TypeScript 端口（`src/ledger.ts` / `src/history.ts` / `src/cash.ts`）上跑通 8 个用例后即删除临时文件，确认推导值正确，而非由 Swift 实现反推。

### `tests/native/SafetyTests.swift`

**P0-1**

| 用例 | 断言 |
| --- | --- |
| 无账本文件 | `loadResult()` 为 `.missing`；`AppState` 空账本且 `loadFailure == nil`；首次写入正常落盘 |
| 有效账本 | `.loaded`；重新打开读到 1 笔交易且无失败状态 |
| 损坏账本 | `.failed`；`loadFailure != nil`；界面回退空账本（只读） |
| 损坏账本 + 保存 | `saveTrade`、`setQuote`、`commit` 全部被拒绝，且**原文件字节逐一比对未变** |
| 恢复 | `replaceFromBackup` 放行、`loadFailure` 解除、备份内容落盘 |
| 恢复写盘失败（第二轮） | `replaceFromBackup` 返回 `false`；`loadFailure` 仍在；`errorMessage` 非空；内存账本为空；原文件字节不变；随后 `commit` / `saveTrade` / `setQuote` / `saveCash` / `setOpening` / `replace(with:)` / `clearAll` / `loadDemo` 全部被拒且原文件字节仍不变 |
| 恢复写盘成功后（第二轮） | `loadFailure` 解除、内存账本更新、磁盘内容可解码、普通 `saveTrade` 恢复成功 |

**P0-2**

| 用例 | 断言 |
| --- | --- |
| 买 100 → 卖 50 | 成功，账本 2 笔 |
| 买 100 → 卖 100 | 成功 |
| 买 100 → 卖 101 | 拒绝，账本仍 1 笔，`errorMessage` 非空 |
| 无持仓卖 1 | 拒绝，账本为空 |
| 买 100 / 卖 80 → 删买入 | 拒绝，账本仍 2 笔 |
| Jan1 买 100 / Jan2 卖 100 / Jan3 买 100 → 删 Jan1 | 拒绝（最终数量看似合法） |
| 同上 → 删 Jan3 | 允许（证明守卫不是一律拒绝） |
| 买 100 / 卖 80 → 改小买入为 50 | 拒绝，数量仍为 100 |
| 修复前的脏账本（先有卖出） | 不阻塞后续修正买入 |

**P0-2/既有超卖（第二轮新增，`legacyOversellStillGuardsNewDamage`）**

脏账本违规键 = `AAPL|2026-01-02|0`，超额 10 股。

| 用例 | 断言 |
| --- | --- |
| S1 删掉违规卖出完全修复 | 允许，账本剩 1 笔 |
| S2 新增 NVDA Buy 10 / Sell 20 | 买入允许；卖出被拒，账本笔数不变，`errorMessage` 非空 |
| S3 超卖从 10 扩大到 50 | 被拒，数量仍为 10，`errorMessage` 非空 |
| S4 新增 MSFT Buy 10 | 允许；`Engine.oversells` 仍只有 1 条（MSFT 未引入新违规，AAPL/MSFT 互不串联） |
| 违规提前到更早时点 | 被拒 |
| 补更早买入把超额从 10 降到 6 | 允许，且同一时点超额确为 6 |

其它：

| 用例 | 断言 |
| --- | --- |
| 同日/买后卖 | 买入与同日卖出都允许 |
| 同日/卖后买 | 被识别为历史超卖，账本为空 |
| 删除关键买入 | 被拒、账本不变、**`errorMessage` 非空**（界面只能靠它告知用户） |
| 排序/同日 sequence 重复 | 平手时保持数组顺序；交换数组顺序语义随之确定；**30 笔完全平手仍严格保持数组顺序** |
| 排序/sequence 不同 | 由 sequence 决定，与数组顺序无关 |

## Test Results

| 套件 | 命令 | 结果 |
| --- | --- | --- |
| Native（Swift） | `bash scripts/test-native.sh`（macOS / CI） | **PASS: 252 assertions**（基线 110）；25,000 closes / 4,000 sessions / 1,000 trades 耗时 0.24s；主线程心跳 46 |
| Unit/Integration（Vitest） | `pnpm test` | **148 passed / 148**（13 files），与基线一致 |
| 质量门禁 | `scripts/verify.ps1` | `QUALITY GATE PASSED` |

断言数轨迹：

```
基线        run 35414879383 (deepseek-dev @ ae079d5):          PASS: 110 assertions
第一轮      run 35418185280 (portfolio/core-safety @ 5a436b6): PASS: 243 assertions
第二轮      run 35420223985 (portfolio/core-safety @ 7420ca3): FAILURE —— 测试自身缺陷，见下
本轮        run 35422399163 (portfolio/core-safety @ 8ffa75d): PASS: 252 assertions
```

**失败 run 的根因（自我记录，不是业务代码问题）**：第二轮新增的 `restoreFailureKeepsTheProtection` 注入的 persist 闭包在**非失败分支里既不抛错也不写盘**，于是恢复「成功」后磁盘上仍是那份损坏文件，紧接着的 `try JSONDecoder().decode(...)` 抛出 `DecodingError`，把测试进程打崩（`Trace/BPT trap: 5`）——所以日志里只有崩溃、没有任何 `FAIL:` 输出。
现已修正：注入的 persist 在正常分支真正调用 `LedgerStore.save`；两处解码改为 `try?` + 断言，同类问题以后会报 `FAIL:` 而不是崩溃。

### Native 测试基线

本阶段运行环境为 Windows，无法本地执行 `swiftc`（`NativeTests.swift` 依赖 AppKit / PDFKit）。因此 native 套件通过 GitHub Actions `build-ios.yml` 在 `macos-26` 上验证；`scripts/verify.ps1` 在 Windows 上按设计跳过 native 检查。

| 项 | 值 |
| --- | --- |
| 工作流 | `build-ios.yml`（workflow_dispatch，ref `portfolio/core-safety`） |
| run_id | `35422399163` |
| head_sha | `8ffa75d8120641bd772f0324b1e76688885666f6` |
| 结论 | **success**，19/19 步（pnpm test → native → 日历渲染 → 截图 → build → cap sync → IPA） |

> 未发现既有 Engine Bug：金标准期望值与 Swift 实现完全一致。若不一致，按任务书要求应停止并上报。

## Build Results

| 项 | 结果 |
| --- | --- |
| `tsc --noEmit && vite build` | 通过（1749 modules transformed，vite 7.3.6） |
| Native 编译（`swiftc -swift-version 5 -O`，含两个新测试文件） | 通过 |
| IPA 构建（`scripts/build-unsigned-ios.sh`） | 通过（run 35422399163 的 `StockLedger-unsigned-IPA` artifact） |
| 日历渲染 / 英文截图 harness | 通过（未因 `RootView` 新增横幅或 `AppState` 构造签名变化而回归） |

## Known Limitations（刻意保留的行为）

1. **违规键是 `symbol|date|sequence`**：如果某个未来路径在手动录入时重排同日 sequence，已有的违规会被当成「新违规」而保守拒绝（fail-closed，不会造成数据损坏）。当前 `saveTrade` 编辑既有交易保留 sequence、`deleteTrade` 只做删除、导入路径（`replace(with:)`）不走该守卫，所以实际不可达。
2. **守卫是「拒绝并提示」，不是「自动修正」**：用户改小一笔买导致历史超卖时只能得到一句提示；提示已包含代码与日期，但不会指出应改哪一笔。
3. **原生 UI 层没有自动化断言**：本轮新增的 alert、预览保留、恢复失败提示只靠编译 + 人工核对。状态层已用「失败必须留下 `errorMessage`」的契约把界面唯一依赖的失败通道固定下来。

## Remaining Risks

1. **Swift 引擎仍只被「单点」覆盖。** 14 组金标准只覆盖 `summary` / `cashTotals` / `dailyReturns` / `todayPnl` 的主干与主要异常分支；`SplitEvent` 拆股路径、`InsightsPresentation` 预计算、`LedgerDerived` 缓存复用仍无断言。
2. **`Ledger.format` 仍未校验**（Phase 0 P2-1）。当前 `.failed` 只在解码失败时触发；若未来格式真的变化，旧 App 会尝试按格式 2 解码并可能「成功解码出错误内容」，而不是进入保护状态。
3. **`fileURLOverride` 是一个可变的全局测试接缝**（`Store.swift`）。它是 `internal`，仅在测试中非 nil；若将来有人误用会在生产代码里造成路径重定向。已用注释标注用途。
4. **`ledger-v2.json` 仍无版本化快照/轮转备份。** P0-1 修复保证了「损坏时不被覆盖」，但没有提供「损坏后的自动回滚点」；恢复仍依赖用户提前导出的备份。
5. **`SettingsView` 的恢复路径缺少 `startAccessingSecurityScopedResource()`**（Phase 0 P2-4）未处理，某些文件提供方上可能读取失败。
6. **`Engine.oversells` 的性能路径没有测试覆盖** —— 现有性能测试走的是 `commit` 而不是 `saveTrade`；按量级（≤5000 笔）可忽略，且正常账本已短路为单次重放。
7. **CI 仍不在 PR 上运行**（Phase 0 P1-5），因此本阶段的 native 验证依赖手动 `workflow_dispatch`。

## Intentionally Not Fixed

- **P0-3**：Demo ledger overwrites real ledger。**P0-3 remains intentionally unresolved and will be handled in Phase 1 Demo Mode.**
- P1-1 Hero 截图降级状态、P1-2 无 LICENSE、P1-3 README 章节、P1-4 E2E 未接入、P1-5 PR 不触发 CI、P1-6 原生引擎覆盖、P1-7 门禁平台绑定、P1-8 文档数字过期、P1-9 英文残留、P1-10 Import 截图、P1-11 合成日历数据、P1-12 `AGENTS.md` 描述不符。
- 全部 P2 / P3。
- 未修改任何依赖（`package.json` / `pnpm-lock.yaml` 未变）、未改数据格式、未改 CI 工作流、未重构 `Engine` 与 `Store` 的既有 API（只新增）。
- 未改 `Ledger.format = 2`、`ledger-v2.json`、Bundle ID 或任何持久化结构 —— 不需要迁移。
- 未合并 `main`、未发布正式包、未改版本号与标签、未使用真实 PDF / CSV / API Key / 交易数据作为 fixture、未删除或弱化任何已有测试、未改 Quality Gate。
