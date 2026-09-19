# Phase 0.5 — Core Safety & Test Guardrails · Review

> 基线：`portfolio/audit` @ `5e2b306`（含 Phase 0 审计报告）。
> 本阶段分支：`portfolio/core-safety`。**未触碰 `main`**。
> 只处理 Phase 0 发现的 P0-1、P0-2，以及为 `Engine` 建立最小测试护栏。

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
| `Store.swift` `replaceFromBackup(_:)` | 新增：用户明确选择备份恢复时解除保护并整体替换 |
| `SettingsView.swift` | 「替换并恢复」按钮改调 `replaceFromBackup` |
| `RootView.swift` | 顶部横幅显示读取失败与「写入已暂停」 |
| `L10n.swift` | 新增中英词条 |

**行为对照**

| 场景 | 修复前 | 修复后 |
| --- | --- | --- |
| 首次启动无文件 | 空账本，可写入 | 空账本，可写入（`.missing`） |
| 有效文件 | 正常读取 | 正常读取（`.loaded`） |
| 文件损坏 | 静默变空账本；下一次保存即覆盖原文件 | 显式失败 + 顶部横幅；`commit` / `commitRefresh` 全部拒绝；**原文件字节不变** |
| 损坏后想恢复 | 只能卸载重装 | 设置 → 从备份恢复（唯一放行的写入路径） |

**实现方式**：`load()` 被整体替换而非保留（唯一调用点是 `AppState.init` 的默认参数），避免留下仍会静默返回空账本的旧入口。

**测试用的最小接缝**：`LedgerStore.fileURLOverride`（`static var`，正常运行恒为 `nil`）把读写重定向到临时目录，使上述场景可被自动验证，且测试不会碰到真实 `Documents`。

## P0-2 Fix

**问题**：导入路径有整批 `validate`（超卖即拒绝），但手动录入路径没有——`TradeFormView.save` 只校验正数/日期/代码，`AppState.saveTrade` 直接追加并写入，`deleteTrade` 无任何检查。持有 10 股卖出 15 股会写盘：`quantity` 变 −5、`cost` 变负、持仓从列表消失而已实现盈亏虚高。

**修复**：在**状态层**（而非按钮层）加交易不变量守卫，采用**按时间顺序重放**而不是只看最终数量。

| 位置 | 变化 |
| --- | --- |
| `Engine.swift` `oversoldTrade(_ trades: [Trade]) -> Trade?` | 新增纯函数：按 `(date, sequence)` 重放，返回第一笔「卖出 > 当时可用股数」的交易；全部合法返回 `nil` |
| `Store.swift` `AppState.introducesOversell(_:)` | 私有守卫：`next` 违反不变量且 `ledger` 原本合法时，写入 `errorMessage` 并拒绝 |
| `Store.swift` `saveTrade(_:)` | 在 `commit` 之前调用守卫 |
| `Store.swift` `deleteTrade(_:)` | 改为 `@discardableResult -> Bool`，在 `commit` 之前调用守卫 |
| `L10n.swift` | 新增超卖说明的中英词条（带 `{}` 占位符：代码 + 日期） |

**为什么必须逐笔重放**：`Jan1 买 100 / Jan2 卖 100 / Jan3 买 100` 的最终持仓是 100，看起来合法；删掉 Jan1 的买入后 Jan2 就已超卖。只比较最终数量会漏掉这个洞，因此守卫按时间顺序重放（与 Web 版 `src/ledger.ts` `calculate` 的逐笔检查口径一致）。

**历史脏数据不被锁死**：若账本在本次改动前就已经不合法（修复前写入的负持仓），守卫放行，用户可以继续修正账本，而不是被永久拒之门外。

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

## Test Results

| 套件 | 命令 | 结果 |
| --- | --- | --- |
| Native（Swift） | `bash scripts/test-native.sh`（macOS / CI） | **PASS: 243 assertions**（基线 110 → **新增 133**）；25,000 closes / 4,000 sessions / 1,000 trades 耗时 0.398s；主线程心跳 74 次 |
| Unit/Integration（Vitest） | `pnpm test` | **148 passed / 148**（13 files），与基线一致 |
| 质量门禁 | `scripts/verify.ps1` | `QUALITY GATE PASSED` |

断言数对比证据：

```
基线   run 35414879383 (deepseek-dev @ ae079d5): PASS: 110 assertions
本阶段 run 35418185280 (portfolio/core-safety @ 5a436b6): PASS: 243 assertions
```

### Native 测试基线

本阶段运行环境为 Windows，无法本地执行 `swiftc`（`NativeTests.swift` 依赖 AppKit / PDFKit）。因此 native 套件通过 GitHub Actions `build-ios.yml` 在 `macos-26` 上验证；`scripts/verify.ps1` 在 Windows 上按设计跳过 native 检查。

| 项 | 值 |
| --- | --- |
| 工作流 | `build-ios.yml`（workflow_dispatch，ref `portfolio/core-safety`） |
| run_id | `35418185280` |
| head_sha | `5a436b6f19e8fa485f339ad88fe094477dd580fa` |
| 结论 | **success**（全部步骤通过：pnpm test → native → 日历渲染 → 截图 → build → cap sync → IPA） |

> 未发现既有 Engine Bug：金标准期望值与 Swift 实现完全一致。若不一致，按任务书要求应停止并上报。

## Build Results

| 项 | 结果 |
| --- | --- |
| `tsc --noEmit && vite build` | 通过（1749 modules transformed，vite 7.3.6） |
| Native 编译（`swiftc -swift-version 5 -O`，含两个新测试文件） | 通过 |
| IPA 构建（`scripts/build-unsigned-ios.sh`） | 通过（run 35418185280 的 `StockLedger-unsigned-IPA` artifact） |
| 日历渲染 / 英文截图 harness | 通过（未因 `RootView` 新增横幅或 `AppState` 构造签名变化而回归） |

## Remaining Risks

1. **Swift 引擎仍只被「单点」覆盖。** 新增的 14 组金标准只覆盖 `summary` / `cashTotals` / `dailyReturns` / `todayPnl` 的主干与主要异常分支；`SplitEvent` 拆股路径、`InsightsPresentation` 预计算、`LedgerDerived` 缓存复用仍无断言。
2. **`Ledger.format` 仍未校验**（Phase 0 P2-1）。当前 `.failed` 只在解码失败时触发；若未来格式真的变化，旧 App 会尝试按格式 2 解码并可能「成功解码出错误内容」，而不是进入保护状态。
3. **`fileURLOverride` 是一个可变的全局测试接缝**（`Store.swift`）。它是 `internal`，仅在测试中非 nil；若将来有人误用会在生产代码里造成路径重定向。已用注释标注用途。
4. **守卫是「拒绝并提示」，不是「自动修正」。** 用户改小一笔买导致历史超卖时只能得到一句提示；提示已包含代码与日期，但不会指出应改哪一笔。
5. **`ledger-v2.json` 仍无版本化快照/轮转备份。** P0-1 修复保证了「损坏时不被覆盖」，但没有提供「损坏后的自动回滚点」；恢复仍依赖用户提前导出的备份。
6. **原生 UI 层无自动化断言。** 顶部横幅、`replaceFromBackup` 的交互仍靠人工核对；`SettingsView` 的恢复路径缺少 `startAccessingSecurityScopedResource()`（Phase 0 P2-4）未处理。
7. **CI 仍不在 PR 上运行**（Phase 0 P1-5），因此本阶段的 native 验证依赖手动 `workflow_dispatch`。

## Intentionally Not Fixed

- **P0-3**：Demo ledger overwrites real ledger。**P0-3 remains intentionally unresolved and will be handled in Phase 1 Demo Mode.**
- P1-1 Hero 截图降级状态、P1-2 无 LICENSE、P1-3 README 章节、P1-4 E2E 未接入、P1-5 PR 不触发 CI、P1-6 原生引擎覆盖、P1-7 门禁平台绑定、P1-8 文档数字过期、P1-9 英文残留、P1-10 Import 截图、P1-11 合成日历数据、P1-12 `AGENTS.md` 描述不符。
- 全部 P2 / P3。
- 未修改任何依赖（`package.json` / `pnpm-lock.yaml` 未变）、未改数据格式、未改 CI 工作流、未重构 `Engine` 与 `Store` 的既有 API（只新增）。
