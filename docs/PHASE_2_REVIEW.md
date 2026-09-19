# Phase 2 — Portfolio Screenshot Optimization · Review

> 基线：`portfolio/demo-mode` @ `d23e65c`（Phase 1 收尾）。
> 本阶段分支：`portfolio/screenshots`（`4478957` + `caee2f0`）。**未触碰 `main`**。
> 范围：任务书 §7 Phase 2、§13 Screenshots。
> 出图链路：`scripts/test-screenshots.sh`（macOS 模拟器）→ CI artifact `App-screenshots` → 人工核对后落回 `docs/screenshots/`。

## Files Changed

### 提交 1 — `4478957` `feat(screenshots): shoot every screen from the demo ledger and add the import screen`

| 文件 | 变化 | 说明 |
| --- | --- | --- |
| `tests/native/ScreenshotsApp.swift` | 改写取数方式 | 不再注入账本，改走真实 Demo Mode；删掉手写的 `sampleDays`；新增 `import` 屏 |
| `ios/App/App/StockLedger/ImportView.swift` | +11 | 新增 `static var prefillOverride` 截图接缝（与 `LedgerStore.fileURLOverride` 同类，正常运行时恒为空串） |
| `scripts/test-screenshots.sh` | +16 / −2 | 截图列表加入 `import`；新增「缺图 / 疑似空白画面即失败」守卫 |

### 提交 2 — `caee2f0` `fix(l10n): translate the import field labels and the stale-quote hint, and keep the calendar screenshot live`

| 文件 | 变化 | 说明 |
| --- | --- | --- |
| `tests/native/ScreenshotsApp.swift` | 新增 `CalendarOnlyView` | 日历屏改为订阅 `AppState` 的 `View`（根因见下） |
| `ios/App/App/StockLedger/L10n.swift` | +6 | 6 个导入字段名的英文译文 |
| `ios/App/App/StockLedger/HoldingsView.swift` | +2 / −1 | 不再把日期插进 L10n key |
| `scripts/test-screenshots.sh` | +8 | 日历屏必须有收益数据才放行 |

## §7 对照

§7 要求 Demo Mode 下各页「不为空、不报错、没有明显布局问题、数字格式一致、日期格式一致、盈亏显示正确、没有 Debug 信息、没有 Placeholder、没有 Test Data 字样」。

出图清单与 §7 页面一一对应（`scripts/test-screenshots.sh` 的循环即清单）：

| §7 页面 | 截图 | 数据来源 | 结论 |
| --- | --- | --- | --- |
| Dashboard / Portfolio | `holdings.png` | 示例账本 + 自带报价 | 有 5 个持仓、今日盈亏、浮动/已实现收益；**不再出现 `Awaiting data` / `Missing previous close` / `No ledger backup yet`**（示例模式本就隐藏备份提醒） |
| Transaction History | `trades.png` | 示例账本 32 笔 | 汇总与列表都有数据；日期与金额格式统一 |
| Daily P&L Calendar | `calendar.png` | 示例账本重放的每日收益 | 2026-09：本月 +$549.78、13 个交易日、逐日红绿格子与图例（见下方缺陷 1） |
| Performance Chart | `returns.png` | 同上 | 累计收益曲线与现金账本都有数据 |
| Import | `import.png` | 虚构券商 CSV（`ScreenshotsApp.importCSV`） | 三步流程可见：识别到 8 列 · 6 行、字段映射、`Import 5 rows`（5 行可导入 + 1 行负数数量报错） |
| Settings | `settings.png` | 示例账本 32 笔交易 / 12 笔流水 | 分区与数值完整 |

示例数据的备注本身就带 `Sample:` 前缀（`L10n.swift:397-405`），不存在「把虚构数据当真实数据」的表述问题。

## 核对产物时查出的两个缺陷

出图这一步的价值就在这里：这两个问题在「CI 绿 + 图有 100+ KB」的前提下都能通过，只有把 PNG 打开逐张看才会暴露。

### 缺陷 1：日历截图是空态

**现象**（首次 CI 的 `calendar.png`）：显示 `No history synced yet. Sync to see daily and monthly returns.`。

**根因**：不是数据问题，是我自己在 harness 里写的取数方式。原先写成普通函数 `calendarList(state)`，把 `state` 当参数传进来、在视图层级里直接读 `state.insights` —— 这种写法 **SwiftUI 不会订阅 `AppState`**，`derived` 在后台算完后这一屏不刷新，于是永远停在第一帧（空态）。日志可证：6 屏都完整走完 `HARNESS-START → state-ready → rootVC-set → key-visible → alive+3s`，没有崩溃，纯粹是没订阅。

**修复**：拆出 `private struct CalendarOnlyView: View`，用 `@EnvironmentObject private var state: AppState` 持有状态（与 `InsightsView` 同一个模式）。修好后 `calendar.png` 从 108 KB 变成 204 KB，内容是真日历。

### 缺陷 2：英文界面里混着中文

**现象**（首次 CI 的 `import.png`）：`Date (required)` 旁边是 `代码 (required)`、`数量 (required)`、`单价 (required)`。

**根因 A**：`代码` / `数量` / `单价` / `币种` / `成交编号` / `流水编号` 这 6 个 `TradeField` / `CashField` 标签在 `L10n` 里没有英文译文，`L10n.tr` 查不到就原样显示中文。已补齐。

**根因 B**（顺手 grep 全部调用点发现，只有 1 处）：`HoldingsView.swift:189` 把日期插进了 key —— `L10n.tr("报价较早（\(quote.date)），可用下方按钮同步最新行情。")`。`L10n.tr` 查的是静态字典，插值后的 key 永远查不到，英文界面必然显示中文。`L10n.swift:333-334` 里本来就备好了两段译文，说明原意就是拼接。已改为按两段拼接。

## 新增的持续守卫

`scripts/test-screenshots.sh` 现在有两道守卫（原来的脚本只负责出图，出成什么样都算过）：

1. **体积守卫**：6 张图缺一张、或小于 20 KB（疑似白屏）即 `FAIL`。
2. **日历数据守卫**：harness 在启动 3 秒后打印 `HARNESS derived screen=<screen> days=N months=M`，脚本读统一日志，日历那一屏 `days` 或 `months` 为 0 即 `FAIL`。

为什么需要第 2 条：空态截图（缺陷 1）有 100+ KB，体积守卫拦不住；而「日历必须不为空」是 §7 的硬要求，不能只靠人肉看图。

## 已知问题（本轮未修，留给后续阶段）

| 问题 | 位置 | 为什么不在这轮改 |
| --- | --- | --- |
| 交易页日期区间胶囊显示 `Sep 19, 2026 → Sep 19, 2026`，而汇总是 `In range 32 trades` | `TradesView.swift:9-10`（`from` / `to` 默认为空串，未筛选时胶囊显示今天作占位） | 这是「空筛选该显示成什么」的产品口径问题，改的是展示层行为，不该在截图阶段顺手定；建议 Phase 3 或 Phase 6 明确口径后一起改 |
| README 截图表格仍是 5 张、没有 `import` | `README.md:84`、`README.zh-Hans.md:84` | README 属 §12 Phase 6 |
| README 其它过期内容（`Vitest (147)` 实际 148；示例入口文案已改） | `README.md` | 同上 |

## Deviations

- **截图固定为英文界面**，两版 README 共用同一组图（现状如此，未改动）。
- **未新增 iOS E2E**：§10 的 E2E 条目已按 `docs/PHASE_1_REVIEW.md` 记录的豁免处理（当前架构不支持，Phase 5 再评估）。
- **未包含**：README 改写、LICENSE、错误处理（Phase 3）、测试覆盖扩张（Phase 4）、CI 工作流改动（Phase 5）。

## CI

| run | commit | 结果 |
| --- | --- | --- |
| `35437015307` | `4478957` | success（job `build` 10 分 21 秒） |
| `35438530985` | `caee2f0` | success |

`portfolio/*` 分支不自动触发 CI，两次均为手动 `gh workflow run build-ios.yml --ref portfolio/screenshots`。
