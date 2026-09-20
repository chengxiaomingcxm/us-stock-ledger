# Phase 1 — Demo Mode · Review

> 基线：`portfolio/core-safety` @ `e959d3e`（含 Phase 0 审计与 Phase 0.5 核心安全）。
> 本阶段分支：`portfolio/demo-mode`（`f07891a` + 测试修正 `6ad8116`）。**未触碰 `main`**。
> 范围：任务书 §4 Phase 1、§5 Demo Dataset、§6 Demo Mode UX、§10 Demo Mode Tests。

## Files Changed

### 提交 1 — `f07891a` `feat(demo): Phase 1 Demo Mode with isolated read-only sandbox`

| 文件 | 变化 | 说明 |
| --- | --- | --- |
| `ios/App/App/StockLedger/DemoData.swift` | 新增（212 行） | §5 的独立 Demo Data Generator |
| `ios/App/App/StockLedger/Store.swift` | +99 / − | `demo` 状态、`enterDemo()` / `exitDemo()`、写入一律拒绝的只读沙盒 |
| `ios/App/App/StockLedger/RootView.swift` | +48 | 全局 `DEMO` 标识横幅 + 退出入口 |
| `ios/App/App/StockLedger/HoldingsView.swift` | +25 | 首次启动的三入口空态；示例模式下隐藏备份提醒 |
| `ios/App/App/StockLedger/SettingsView.swift` | +30 / − | 「试用示例账本 / 退出示例模式」 |
| `ios/App/App/StockLedger/QuoteSettingsView.swift` | +2 / − | 示例模式禁止行情同步 |
| `ios/App/App/StockLedger/L10n.swift` | +16 / − | 中英词条 |
| `ios/App/App.xcodeproj/project.pbxproj` | +4 | 新文件登记（四处） |
| `scripts/test-native.sh` | +2 / − | 新测试文件加入编译列表 |
| `tests/native/DemoModeTests.swift` | 新增（186 行） | §10 的五项测试 |
| `tests/native/NativeTests.swift` | +1 | 调用新测试入口 |
| `tests/native/SafetyTests.swift` | +5 / − | 适配 `AppState` 初始化签名 |

### 提交 2 — `6ad8116` `test(demo): assert the cash invariant the app actually defines`

把「示例现金链不得透支」的断言从「同一交易日内交易与流水的先后顺序」改为「每日收盘后的余额」。
同日交易与流水的相对顺序 product 从未定义（界面只按日期汇总），按某个具体顺序断言等于把臆想的假设写进测试。

## §4 / §5 / §6 对照

| 任务书要求 | 实现 | 证据 |
| --- | --- | --- |
| §5 独立 Demo Data Generator，不散落在 UI | `enum DemoData`，UI 层只调用 `LedgerStore.demo()` | `DemoData.swift`、`Store.swift:59-60` |
| §5 5 个当前持仓、30–50 笔历史交易 | 6 个标的、**32 笔**交易 | `DemoData.swift:42`（`seeds` 表） |
| §5 5–10 条分红、若干入金/出金 | **6 条**分红 + 入金×3 / 出金×1 / 账户费用×2 + 期初余额 | `DemoData.swift:89`（`cashSeeds` 表） |
| §5 至少 1 个完全卖出 + 1 个部分卖出 + 正负收益 | `TSLA` 全部卖出（亏损），其余 5 只有加仓/减仓/部分止盈 | `DemoData.swift:42` |
| §5 全部为虚构数据 | 交易、价格、现金流水全部由生成器编造，不含任何真实账户信息 | `DemoData.swift:3` |
| §6 Req 1 不覆盖真实数据（优先隔离存储） | **内存只读沙盒**：`enterDemo()` 只改内存；`commit` / `commitRefresh` 在 `demo` 时直接拒绝并给出可读原因 | `Store.swift:164-167`、`Store.swift:454-462` |
| §6 Req 2 可退出并恢复原数据环境 | `exitDemo()` 重新读盘，连「账本读不出来」的写保护状态一起恢复 | `Store.swift:464-474` |
| §6 Req 3 明显的 `DEMO` 标识 | 顶部横幅 + 一键退出；设置页同样可退出 | `RootView.swift:76-89`、`SettingsView.swift:89-92` |
| §6 Req 4 不调用不必要的收费 API | 示例自带报价与历史收盘价，`DemoData` 不联网、不读 API Key；`commitRefresh` 在示例模式下不发请求 | `DemoData.swift:11`、`Store.swift:183` |
| §6 首次进入的三入口空态 | 记录第一笔交易 / 试用示例账本 / 导入数据 | `HoldingsView.swift:44-49` |

### 两个刻意的设计取舍

- **相对「现在」生成**：170 个交易日以最近一个交易日收尾，示例数据不会过期；测试传固定 `now` 即可完全复现（`DemoData.swift:6-7`、`DemoModeTests` 的锚点 `2026-09-18`）。
- **交易价格取自当日收盘价**：成本、市值、浮动/已实现收益与每日收益日历天然自洽，不会出现「图表和持仓对不上」（`DemoData.swift:8-9`）。

## Tests Added

`tests/native/DemoModeTests.swift` 对应 §10 的五项要求，全部把文件操作重定向到临时目录（`LedgerStore.fileURLOverride`），不碰真实 `Documents`。

| §10 要求 | 断言 |
| --- | --- |
| Demo dataset generates correctly | 交易日数量/升序/不重复/无休市日；交易 30–50 笔；**示例账本自身无超卖**；含任务书要求的 5 个标的；每个标的每个交易日都有收盘价；含完全卖出与仍持仓的标的；报价 = 最后一天收盘价；分红 5–10 条且发生时已建仓；**每日收盘后现金余额不为负**；同一锚点生成结果逐字段一致 |
| Demo Mode loads successfully | 加载后有 5 个持仓、成本为正、无「待报价」、日历有数据、现金有入金 |
| Demo mode does not overwrite real data | 交易/报价/现金/清空四条写入路径全部被拒绝，且**磁盘文件字节逐一比对未变** |
| Exit Demo restores original state | 退出后回到自己的账本，磁盘仍未被写入；账本损坏时退出**恢复写保护** |
| Demo calculations are valid | 通过上面「无超卖 / 无待报价 / 现金非负 / 持仓成本为正」间接覆盖 |

## §10 的 E2E 条目：本轮记录为豁免

任务书 §10 末尾有一条「如果架构允许：增加至少一个 E2E Test（Launch → Load Demo → Open Portfolio → Open Transaction → Open Calendar → Exit Demo）」。

**裁决（2026-09-19，用户决定）：当前架构不支持 iOS E2E，Phase 5 再评估。**

理由，均为仓库事实：

1. 原生侧没有 XCUITest target。`ios/App/App.xcodeproj` 只有应用 target；`tests/native/` 是 `swiftc` 直接编译的断言式测试，`NativeTests` 是 `@main` 入口，不驱动 UI。
2. 仓库唯一的 E2E 是 `e2e/*.spec.ts`（Playwright，26 例），跑的是 **Web 版**界面，且没有 npm script、CI 不跑、`playwright.config.ts` 写死 Windows 的 Chrome 绝对路径 —— 它覆盖不到 SwiftUI 界面，也不能充当 iOS E2E。
3. 新建 XCUITest target 会改动 Xcode 工程结构（新增 scheme/target/构建产物）并显著拉长 `build-ios.yml`（当前约 14 分钟），属于 §11 Phase 5 的 CI 议题，不属于 Phase 1。

**升级路径**：Phase 5 复评时，用现有 `tests/native/ScreenshotsApp.swift` 的思路（模拟器 + 一次性 harness app）扩展成 UI 驱动，或在 Xcode 工程里加一个 XCUITest target 并接入 `build-ios.yml`。

## Deviations / 已知边界

- **示例模式不跨启动保留**：重启即回到用户自己的数据。这是刻意选择（示例数据永远不可能变成用户的账本），已在 `Store.swift:452` 用 `ponytail:` 注明，升级路径是用 `@AppStorage` 记住状态。
- **`DemoData` 的交易日历依赖 `Engine.knownClosed`**，其休市日表只覆盖 2026–2028（`Engine.swift:198-215`）。运行日期在 2026 年内时节日不会被当成交易日；更早的年份只会让个别假日被算作交易日，属外观问题。已在 `DemoData.swift:13-15` 注明。
- **未包含**：README、LICENSE、截图重出、UI Polish、CI 工作流改动、错误处理（Phase 3）、覆盖率扩张（Phase 4）。

## CI

| run | commit | 结果 |
| --- | --- | --- |
| `35434984702` | `6ad8116` | **success**，19/19 步通过，**343 条原生断言**（含 `DemoModeTests`），耗时约 15 分 42 秒 |

`portfolio/*` 分支不自动触发 CI，本次为手动 `gh workflow run build-ios.yml --ref portfolio/demo-mode`。
