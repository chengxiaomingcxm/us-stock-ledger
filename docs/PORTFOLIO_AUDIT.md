# US Stock Ledger — Portfolio Audit

> Phase 0 交付物。本文件**只记录事实，不修改任何代码**。
> 审计基准：`deepseek-dev` @ `9489c7b`（原生版 1.0.0 · build 5），审计日 2026-09-19。
> 所有结论均以当前仓库的实际代码为依据，并标注 `文件:行号`。凡未经代码验证的推测都会写明「未验证」。

---

## Executive Summary

**项目现状**：这是一个「Web 原型 → 原生 iOS 重写」的双形态仓库。界面早已迁移到 SwiftUI（`SceneDelegate.swift:8-14`），但旧的 TypeScript/Vite/Capacitor 代码仍在仓库里、仍被 CI 构建、仍被打进 IPA 包内。原生侧业务逻辑完整、口径严谨（缺行情一律「待补全」，绝不按零顶替），并且已有一套相当扎实的测试与发布链路。

**审计结论**：工程底子是够用的，**当前阻碍 Portfolio 展示的不是代码能力，而是「对外表达」与「首次体验」**。

| 维度 | 评级 | 依据 |
| --- | --- | --- |
| 业务逻辑复杂度 | 强 | 移动平均成本、已实现/浮动收益、现金账本、每日收益重放、拆股检测、汇丰 PDF 解析 |
| 数据完整性设计 | 中上 | 先落盘后改内存（`Store.swift:154-160`）、导入整批校验、绝不按零顶替 |
| 数据安全 | **弱** | 账本读失败静默返回空账本（`Store.swift:13-17`）；载入示例会直接覆盖真实账本（`Store.swift:381-383`） |
| 测试 | 中上 | 148 个 Vitest 用例 + 53 个原生断言点；但原生引擎缺单测，E2E 26 例从未运行 |
| CI/CD | 中 | macOS 构建 + IPA + 截图链路完整；**PR 不触发**，E2E 未接入，质量门禁是 Windows-only |
| 文档 / 展示 | **弱** | 无 LICENSE、无架构/隐私/免责/路线图章节、README 测试数过期、无 Import 截图、Hero 截图显示「Awaiting data」 |
| 首次体验 | **弱** | Demo 会覆盖真实账本且无隔离、无全局 DEMO 标识，退出 = 清空账本 |

**问题计数**（分级标准见文末）：

- **P0 — Critical：3**
- **P1 — Important：12**
- **P2 — Improvement：11**
- **P3 — Optional：7**

**最重要的三个发现**：

1. **账本损坏会被静默吞掉，并可能被后续保存永久覆盖**（`Store.swift:13-17` + `:29-31`）。这是本仓库唯一的真实数据丢失路径，且没有任何用户可见提示。
2. **现有「示例账本」不满足任务书 §6 的任何一条 Requirement**：没有隔离存储、没有全局 DEMO 标识、退出即清空账本（`Store.swift:381-388`、`SettingsView.swift:84-91,144-157`）。好消息是 `AppState.init(ledger:settings:persist:)` 已经预留了注入点，Phase 1 是**小改动**而非重构。
3. **首个展示面（README + Hero 截图）目前是「未完成状态」**：Hero 截图 `docs/screenshots/holdings.png` 上直接写着 `Awaiting data`、`Missing previous close` ×3 与 `No ledger backup yet` 横幅 —— 因为它用的是只有 5 笔交易、缺 `history` 的旧 demo 账本。这是 30 秒内劝退潜在客户的第一要素。

---

## Current Architecture

### 两个运行时，一个仓库

```
                     ┌──────────────────────────────────────┐
   用户看到的界面 ──▶ │  SwiftUI App（iOS 16+，主产品线）      │
                     │  ios/App/App/StockLedger/*.swift      │
                     └───────────────┬──────────────────────┘
                                     │ Documents/ledger-v2.json
                                     │ iOS Keychain（行情密钥）

                     ┌──────────────────────────────────────┐
   构建期仍在打包 ──▶ │  Legacy Web 引擎（TypeScript + Vite） │
                     │  src/*.ts → dist/ → cap sync ios      │
                     └──────────────────────────────────────┘
                       仍被 CI 构建并内嵌进 IPA，但不再承载界面
```

| 层 | 技术 | 位置 |
| --- | --- | --- |
| UI Layer | SwiftUI（`TabView` 4 个 `NavigationStack`） | `RootView.swift:48-71` |
| Application Layer | `@MainActor final class AppState`（所有业务入口的唯一出口） | `Store.swift:80` |
| Calculation Engine | `enum Engine`（纯函数、无 I/O） | `Engine.swift:1-574` |
| Presentation Cache | `LedgerDerived` 后台预计算 + `revision` 比对复用 | `Engine.swift:547-574`、`Store.swift:130-148` |
| Persistence | `enum LedgerStore` → `Documents/ledger-v2.json`，`JSONEncoder` + `.atomic` | `Store.swift:7-38` |
| Secrets | iOS Keychain（`kSecClassGenericPassword`） | `QuoteService.swift:100-143` |
| Market Data | `QuoteService`（Yahoo / Finnhub / Custom HTTPS） | `QuoteService.swift:145-512` |
| Import | `CsvImport`（文本）、`HSBCStatement` + `StatementImport`（PDFKit） | `CsvImport.swift`、`HSBCStatement.swift` |
| Legacy Web | Vanilla TS + 模板字符串，`render()` 全量重建 `innerHTML` | `src/main.ts:115-161` |

**关键事实**：原生与 Web 是**两套独立实现**，共享的只有概念口径，不是代码。

---

## Project Structure

```
ios/App/App/StockLedger/     ← 主产品线：15 个 Swift 文件，全部显式加入 Xcode 源构建阶段
  Models.swift               数据模型 + 字段校验 + 金额格式化
  Store.swift                LedgerStore（落盘）+ AppState（全部业务入口/状态）
  Engine.swift               纯计算引擎（持仓/现金/日收益/今日盈亏/筛选）
  QuoteService.swift         行情 + 美东时钟 + Keychain
  CsvImport.swift            券商 CSV 解析/映射/去重/整批校验
  HSBCStatement.swift        汇丰结单文本 → 交易/分红行
  StatementImport.swift      PDFKit 抽文本 + 导入 UI
  RootView / HoldingsView / TradesView / InsightsView / SettingsView / ImportView /
  QuoteSettingsView / L10n.swift
ios/App/App/                 AppDelegate / SceneDelegate（SwiftUI 承载 + 遗留 Capacitor 注册）

src/                         ← 遗留 Web 引擎（18 个 TS/CSS 文件）
tests/                       ← Vitest 13 个文件（148 用例）+ tests/fixtures + tests/native（Swift）
e2e/                         ← Playwright 8 个文件（26 用例）
scripts/                     ← 构建 / 测试 / 渲染 / 门禁 / 发布脚本
docs/                        ← archive/（旧 Web 文档）+ screenshots/（5 张英文截图）
releases/                    ← v1.0.0 + 旧 Web 的 v1.1.0/1.2.0/1.21.0–1.26.0 清单
.github/workflows/           ← build-ios.yml（macOS 构建）+ publish-release.yml（ubuntu 发布）
```

| 入口 | 位置 |
| --- | --- |
| iOS 启动 | `SceneDelegate.swift:8-14` → `UIHostingController(rootView: RootView().environmentObject(AppState()))` |
| 状态根 | `AppState.init`（`Store.swift:120-129`），默认 `LedgerStore.load()` |
| Web 启动 | `index.html` → `src/main.ts:444 start()`（遗留） |

---

## Current Features

以代码为准的分类（**不以 README 为准**）。

### Fully Implemented

| 功能 | 证据 |
| --- | --- |
| 买入/卖出/手续费/备注/券商成交编号 | `Models.swift:12-31`、`TradesView.swift:148-313` |
| 移动平均成本、已实现、浮动、总收益 | `Engine.swift:51-97` |
| 缺行情 → 「待补全」，绝不按零 | `Engine.swift:73-76`、`Models.swift` `LedgerError` |
| 现金账本（期初/入金/出金/分红含税/费用） | `Models.swift:70-98`、`Engine.swift:100-134` |
| 买卖联动现金，出入金不计收益 | `Engine.swift:118-130` |
| 今日盈亏（对照上一交易日收盘，美东口径） | `Engine.swift:370-479` |
| 每日收益日历 + 累计曲线 | `Engine.swift:187-292, 481-546` |
| 拆股检测（只提示、不自动改股数） | `Engine.swift:196-199, 260-269` |
| 券商 CSV 导入（预览/去重/整批校验） | `CsvImport.swift` 全文件、`ImportView.swift` |
| 汇丰投资结单 PDF 导入（强完整性校验） | `HSBCStatement.swift:49-200`、`StatementImport.swift:203-240` |
| 行情：Yahoo 收盘 / Finnhub / 自定义 HTTPS | `QuoteService.swift:8-28, 214-500` |
| 备份导出（JSON 文本分享）/ 恢复（文件导入 + 二次确认） | `SettingsView.swift:63-119, 171-182`、`Store.swift:374-377` |
| 语言中英切换（400 词条） | `L10n.swift:35-459`、`RootView.swift:73` |
| 深浅色 + 红涨绿跌/绿涨红跌 + Dynamic Type + VoiceOver | `RootView.swift:17-31, 90, 110-141` |
| 示例账本（`LedgerStore.demo()`，5 笔交易 + 3 现金） | `Store.swift:40-74` |

### Partially Implemented

| 功能 | 现状 |
| --- | --- |
| Demo Mode | 存在，但**不隔离、无全局标识、退出即清空**（见 P0-3） |
| 本地化 | 400 条词典覆盖主界面；`ImportView.swift:271,305`、`HSBCStatement.swift:122,144`、`StatementImport` notice 直接写死中文 |
| 备份 | 原生导出**未指定文件名**（`SettingsView.swift:63,140` 分享裸字符串）；Web 侧有完整文件名逻辑 |
| 恢复 | 原生 `SettingsView.swift:112-119` 未调用 `startAccessingSecurityScopedResource()`，与 `ImportView.swift:223` 路径不对称（未实测） |
| 版本号 | `version.test.ts:12-13` 硬编码 `'1.0.0'`/`'5'`，每次发版必须改测试 |

### Experimental

| 项 | 说明 |
| --- | --- |
| `Ledger.format` 校验 | `Models.swift:119` 定义 `format = 2`，但 `load()` 从不检查 → 未知格式被静默按当前格式解码 |
| 节假日表 | `Engine.swift:168-176` 硬编码 2026–2028 NYSE 休市日；2029 起退化为「仅周末」 |
| 完整备份 vs 通用备份 | Web 侧有「丢弃 history/cash」的通用备份分支（`src/main.ts:435`）；原生侧只有完整导出 |

### Documentation Claims / Needs Verification

| 断言 | 出处 | 核实 |
| --- | --- | --- |
| `Vitest (147)` | `README.md:57`、`README.zh-Hans.md:57` | **过期**，实际 148（`CHANGELOG.md:19` 自己写的 148 是对的） |
| CI 在 `main`/`deepseek-dev` 上跑 | `AGENTS.md:85` | **不成立**，`build-ios.yml:3-5` 只有 `workflow_dispatch` + `push: main` |
| `official IPA builds run from main only` | `README.md:78` | 成立 |
| 5 张截图路径 | `README.md:84` | 成立，文件全部存在 |
| `export reminders after 30 days` | README 功能段 | 原生成立（`SettingsView.swift:185`）；旧 Web 默认 7 天（`src/preferences.ts:5`） |
| 「视觉正确性」有自动断言 | 归档 CHANGELOG | **不成立**，`tests/native/CalendarRenderApp.swift` 与 `ScreenshotsApp.swift` 只出 PNG，无断言 |

---

## Data Flow

### 交易 → 账本 → 展示

```
用户输入 (TradeFormView)
   ↓  LedgerValidation（正数 / 日期 / symbol / note）
AppState.saveTrade
   ↓  追加或替换 Trade，分配 sequence
AppState.commit
   ↓  try persist(next)  ← 先落盘
   ↓  成功后才 ledger = next  ← 再改内存
LedgerStore.save → JSONEncoder(.prettyPrinted,.sortedKeys) → .atomic write
   ↓
AppState.rebuild → Task.detached → Engine.summary / dailyReturns / InsightsPresentation
   ↓
LedgerDerived（summary / cash / days / insights / displayReturn / symbols）
   ↓  revision(UUID) 不变则直接复用缓存
SwiftUI 视图渲染
```

### 行情

```
RootView.task(id: RefreshTrigger)
   ↓  scenePhase == .active 且 interval > 0
AppState.refreshQuotes / syncHistory
   ↓  每批并发 2（QuoteService.fetchAll:219）
QuoteService → Yahoo / Finnhub / Custom HTTPS
   ↓  meta 校验：currency=USD、exchangeTimezoneName=America/New_York、instrumentType∈{EQUITY,ETF}
Normalization（Decimal 解析，拒绝科学计数法）
   ↓
applyQuotes → 合并规则：不覆盖更新的报价；同日手动报价优先
   ↓
commitRefresh（后台编码 + generation token 防覆盖）
```

### 导入

```
CSV / PDF 文件
   ↓  decode（UTF-16 BOM → UTF-8 fatal → GB18030 往返校验）
   ↓  parse（手写词法：引号/转义/字段内换行/CRLF；自动分隔符）
   ↓  autoMap（中英别名词典，每列只用一次）
   ↓  逐行校验 → ready / suspected / duplicate / error
   ↓  candidate（同日交易插入位置：之前/之后，重排 sequence）
   ↓  validate（整批重放买卖：超卖或超限 → 整批拒绝）
   ↓  用户在预览页勾选
   ↓  提交前再跑 candidate + validate（ImportView.swift:287-301）
AppState.replace → commit → 落盘
```

---

## Portfolio Calculation

核心全部在 `Engine.swift`（纯函数、无 I/O），金额一律 `Decimal`（不是 `Double`）。

| 项目 | 算法 | 位置 |
| --- | --- | --- |
| 买入成本 | `cost += gross + fee`；`quantity += q` | `Engine.swift:60-62` |
| 部分卖出 | `removed = (q == quantity) ? cost : cost * q / quantity` | `Engine.swift:64` |
| 已实现盈亏 | `profit = gross - fee - removed`，逐笔存入 `gains[trade.id]` | `Engine.swift:65-67` |
| 浮动盈亏 | `value = Σ qty×price`；缺价则 `value = nil`，**不按零** | `Engine.swift:73-76` |
| 手续费 | 买入费资本化进成本、卖出费冲减收益，另单独累计展示 | `Engine.swift:59, 61, 65` |
| 分红税 | 仅 `CashRecord.tax`；净额 `amount - tax` | `Models.swift:86-91` |
| 分红（无税额信息） | 汇丰「净额分红」写 `source = "hsbc-statement-net"` 且 `tax = nil`，UI 单独提示「预扣税未披露」 | `Engine.swift:562`、`InsightsView.swift:69-72` |
| 期末现金 | `balance = opening + Σ net`，只统计期初日及之后的流水，且买卖并入 | `Engine.swift:100-134` |
| 出入金 | 永不计入任何收益 | `Engine.swift:130` |
| 每日收益 | `profit = endQty×after − startQty×before + flows` | `Engine.swift:275-277` |
| 今日盈亏 | `profit = endValue − startValue − buyCost + sellNet`；`percent = total / basis` | `Engine.swift:449-462` |
| 拆股 | 检测到即把当日置为待补全并提示核对，**不自动调整** | `Engine.swift:196-199, 260-269` |

**共同口径**：任何必需的收盘价/报价缺失 → `nil`（「待补全」）→ 该日/该股不上报数字。这条规则在 Web 与原生两侧一致实现且都**有测试**（Web 侧 `tests/history.test.ts`、`tests/today-pnl.test.ts`）。

**时区**：所有业务日期为美东 `yyyy-MM-dd` 字符串；`MarketClock` 固定 `America/New_York`，跨日推算走 UTC 零点以避免夏令时 23/25 小时偏差（`QuoteService.swift:53-98`）。

---

## Data Storage

| 数据 | 位置 | 说明 |
| --- | --- | --- |
| 账本 | `Documents/ledger-v2.json` | `Store.swift:8-11`；`JSONEncoder(.prettyPrinted, .sortedKeys)` + `.atomic`（`:23-31`） |
| 行情密钥 | iOS Keychain：`service = com.personal.stockledger.market`，`account = quote-settings-v1` | `QuoteService.swift:100-143` |
| 语言 | `UserDefaults["app.language"]` | `Store.swift:85-89` |
| 外观 | `@AppStorage("appearance.theme")` 等 | `RootView.swift:36-37` |
| Demo 标记 | `@AppStorage("demo.loaded")` | `SettingsView.swift:19` |
| 上一收盘价 | **仅内存** `AppState.previousClose`，不落盘 | `Store.swift:92-93` |
| Web 遗留 | Capacitor Preferences（浏览器后端 = `localStorage["CapacitorStorage.*"]`） | `src/storage.ts:45`；E2E 直接写该键（`e2e/quote-api.spec.ts:21`） |

**格式**：`Ledger.format = 2`（`Models.swift:119`）；`Codable` 全合成，无自定义日期策略；日期字段都是字符串，只有 `fetchedAt`/`checkedAt` 是 `Date`。

**关键安全边界**：`.atomic` 写入意味着**每次保存都整体替换原文件**，仓库中不存在 `ledger-v2.json` 的轮转副本或自动快照。

---

## Market Data

| 提供方 | 用途 | 端点 | 鉴权 |
| --- | --- | --- | --- |
| Yahoo（默认） | 已完成交易日收盘 + 拆股 | `query2.finance.yahoo.com/v8/finance/chart/{sym}?interval=1d&range=3mo&includePrePost=false&events=splits` | 无 |
| Finnhub | 盘中最新价 + 前收 | `finnhub.io/api/v1/quote?symbol=` | `X-Finnhub-Token` |
| Custom | 用户自有 HTTPS 接口 | 模板含 `{symbol}` | `Authorization: Bearer`（可选） |

- **模式**：`close` / `live` / `auto`（美东 09:30 前或 16:15 后按收盘处理）——`QuoteService.swift:189-198`。
- **网络**：`timeoutInterval = 15`、`cachePolicy = .reloadIgnoringLocalCacheData`、`NoRedirectSession`（ephemeral、不跟随跳转、不带 Cookie）——`QuoteService.swift:244-245, 501-512`。
- **限流**：每批并发 2（`QuoteService.swift:219, 304`）；前台刷新间隔只允许 0/60/300 秒。
- **校验**：Yahoo meta 必须 `currency = USD`、`exchangeTimezoneName = America/New_York`、`instrumentType ∈ {EQUITY, ETF}`；当日 K 线须在收盘后 15 分钟才承认（`+900`，`:360-366`）。
- **失败策略**：逐 symbol 记录错误，**保留旧价**，绝不写入零价。
- **隐私事实**：请求发出即向第三方暴露持仓代码；Logo 走 `financialmodelingprep.com` 热链（`src/market.ts:12`）。

---

## Import System

### CSV（`CsvImport.swift` + `ImportView.swift`）

- 编码：UTF-16 BOM/无 BOM → UTF-8（fatal）→ GB18030（须完整往返）——`:148-163`
- 词法：手写逐字符解析，支持引号、双引号转义、字段内换行、CR/CRLF；分隔符在 `, ; \t` 中自动选择
- 映射：中英别名词典，自动映射时每列只用一次
- 值校验：金额 `1234.56 / 1,234.56`、≤12 位整数、≤8 位小数、拒绝负数；日期**拒绝** `Z`/`±hh:mm` 后缀
- 去重：`externalId` 精确判重 + 「日期+代码+方向+数量+单价+手续费」完整签名判疑似重复（默认不勾选）
- 同日顺序：时间齐全按时间排；不齐全需用户确认；双方都双向 → 直接拒绝导入
- 整批保护：写入前 `validate` 重放买卖，超卖即整批中止

### PDF（`HSBCStatement.swift` + `StatementImport.swift`）

- 文本抽取用 **PDFKit**；按 `selectionsByLine` + midY 容差 3pt 聚行，按 minX 排序拼接
- 前置断言：必须含 `HSBC` 与 `INVSTM0011`；账户号必须一致；账号哈希生成前缀 id
- 强完整性：每页 summary 条目数必须吻合、费用引用必须被消费、`|price×qty ± fee − settlement| ≤ 0.005`、Reference 行数必须等于日期行数 —— **任一不满足整份拒绝**
- 局限：只支持投资结单、不支持扫描件、单批 ≤5000 行、格式一变即完全不可用

---

## Native iOS Architecture

| 项 | 值 |
| --- | --- |
| Bundle ID | `com.personal.stockledger` |
| 部署目标 | iOS 16.0 |
| Swift | 5 |
| 版本 | `MARKETING_VERSION = 1.0.0`、`CURRENT_PROJECT_VERSION = 5` |
| Entitlements | **无**（全仓无 `CODE_SIGN_ENTITLEMENTS`） |
| 隐私清单 | `PrivacyInfo.xcprivacy`：无追踪、无采集数据类型 |
| 签名 | Automatic；脚本以 `CODE_SIGNING_ALLOWED=NO` 出未签名 IPA |

**设计要点**：

- `AppState` 是唯一状态源，`@MainActor`；持久化通过注入闭包 `persist: (Ledger) throws -> Void`（`Store.swift:120-122`）—— **这是 Phase 1 最重要的可复用点**。
- 计算在 `Task.detached(priority: .userInitiated)` 后台执行，UI 线程不做 JSON 编码（`Store.swift:130-148, 163-179`）。
- 视图用 `revision: UUID` 做 `Equatable` 快照比对，避免列表滚动时重算（`InsightsView.swift:95, 122`）。
- 无障碍：盈亏金额走 `AmountText`（颜色 + 正负号双通道）、持仓行 `.accessibilityElement(children: .combine)`、日历格有独立 label。
- **遗留死代码**：`LedgerSecretsPlugin`（`SceneDelegate.swift:35-70`）仍注册但无调用方，其 Keychain `account`/可访问性与 SwiftUI 路径不一致（`configuration` vs `quote-settings-v1`；`WhenUnlockedThisDeviceOnly` vs `AfterFirstUnlock`）。

---

## Testing

### 规模

| 层 | 文件 | 用例 | 运行环境 |
| --- | --- | --- | --- |
| Unit/Integration（Vitest） | 13 | **148** | Node（非 jsdom） |
| Native（swiftc 编译型） | `tests/native/NativeTests.swift` | **53 个断言点** | macOS / CI |
| Render harness（无断言） | `CalendarRenderApp.swift`、`ScreenshotsApp.swift` | 出 PNG 供人工核对 | macOS / CI |
| E2E（Playwright） | 8 | **26** | **本地 Windows only，从未在 CI 运行** |

### 已覆盖的核心逻辑

移动平均成本、部分/全部卖出、碎股清仓、改旧交易重算、删除致超卖拒绝、备份往返、双槽存储回退与损坏保护（`tests/ledger.test.ts`）；CSV 编码/词法/映射/去重/同日歧义/整批超卖（`tests/csv-import.test.ts` 23 例）；每日收益口径与「缺行情留空」（`tests/history.test.ts` 13 例）；今日盈亏 19 例；现金账本 20 例；行情校验与失败保留 12 例；密钥写入回读校验 4 例；版本一致性 1 例；L10n 重复键 1 例。

### 明显缺口（防止 Regression 的能力盲区）

| 缺口 | 证据 | 对 Portfolio Polish 的影响 |
| --- | --- | --- |
| **原生引擎无单测** | `dailyReturns/todayPnl/cashTotals` 只在 TS 端口有测试；`tests/native/NativeTests.swift:66-98` 集中在 HSBC 与候选/汇总 | 高：所有 Phase 1+ 改动都发生在 Swift 侧 |
| PDF 解析 | 只在 macOS-only 的 NativeTests 覆盖；Windows 上 `pnpm test` 完全不含 | 中 |
| E2E 全量 26 例 | `package.json` 无 script、CI 无引用、`playwright.config.ts:1` 写死 Windows Chrome 路径 | 高：这是现成的「可展示的自动化测试资产」，却在仓库里沉睡 |
| 原生视图层 | 无任何断言 | 中（截图人工核对） |
| 原生 L10n 完整性 | 只查重复键，不查缺键/兜底 | 中（与 P1-9 相关） |

### 结论

**如果 Phase 1 只改 Swift，现有测试几乎无法拦截 Regression**——因为 Swift 侧只有 53 个断言点，且不覆盖 `Engine` 的三大公式。这是 Phase 1 最大的工程风险（见下）。

---

## CI/CD

### `build-ios.yml`

| 项 | 值 |
| --- | --- |
| 触发 | `workflow_dispatch` + `push: main`（`paths-ignore`: `**/*.md`、`releases/**`、发布脚本、自身） |
| PR | **无 `pull_request` 触发器** |
| Runner | `macos-26`，timeout 30min，`concurrency` 同 ref 取消旧任务 |
| 步骤 | checkout(fetch-depth 0) → node 24 → pnpm 11.19.0 → `pnpm install --frozen-lockfile` → `pnpm test` → `test-native.sh` → `test-calendar-rendering.sh` → 上传日历 PNG（always） → `test-screenshots.sh` → 上传截图（always） → `pnpm build` → `cap sync ios` → `build-unsigned-ios.sh` → 上传 IPA + sha256（缺失即失败，保留 14 天） |
| 不包含 | lint、Playwright/E2E、`verify-ipa.py` |

### `publish-release.yml`

触发：`workflow_dispatch` + `push: main` 且改动 `releases/**` 等。ubuntu-24.04，单步跑 `scripts/publish-release.py`，无自定义 secrets（用 `github.token`）。校验链完整：sha256 → `verify-ipa.py` → Info.plist 版本一致 → tag 指向同一 commit → 拒绝覆盖已发布资源 → 下载对应 run_id 的 artifact → 发布。

### 评价

- **足以支撑**：原生构建、单测、模拟器截图、IPA 产出与发布。
- **不足以支撑 Portfolio Polish**：PR 无检查、E2E 未接入、质量门禁 `verify.ps1` 是 Windows-only 且 CI 不跑它（两条门禁链不等价）。

---

## Error Handling

| 场景 | 现状 | 风险 |
| --- | --- | --- |
| 账本读取/解码失败 | `try?` 静默返回空 `Ledger()`（`Store.swift:13-17`） | **P0**：无提示、无备份，后续保存覆盖原文件 |
| 账本保存失败 | `commit` 捕获并保留内存与磁盘（`Store.swift:154-160`）；导出失败静默（`SettingsView.swift:108-111`，仅表现为按钮不出现） | P2 |
| 同步期间并发修改 | `generation` token 检测并提示「已保留最新账本」（`Store.swift:168-171`） | 已处理 |
| 行情失败 | 逐 symbol 记录，保留旧价；429/401/403 有专门文案；错误信息**脱敏**（测试断言不含密钥） | 已处理 |
| 网络超时 | 15s（收盘）/12s（实时） | 已处理 |
| CSV 解析错误 | 逐行 `{line, reason}` 收集，不影响其他行；整批校验失败则整批拒绝 | 已处理 |
| CSV 列数不符 | **整文件报错**（`src/csv-import.ts:55`） | P2：与逐行错误的粒度不一致 |
| PDF 解析 | 严格全则全无；不可识别即拒绝并给出原因 | 已处理 |
| 备份导入 | 非法备份 → 明确提示且**不改动账本**；导入前预览 + 二次确认 | 已处理 |
| 用户可见的原始异常 | 原生：`error.localizedDescription` 走 `L10n`，均为中文可读文案；Web：`src/main.ts:267` 在缺少 `#form-error` 容器时 `toast(String(e))` | P2（仅 Web） |

**结论**：原生侧错误处理整体是好的；真正的洞只有「读失败静默」这一处，但它恰好是本项目唯一的真实数据丢失路径。

---

## Privacy & Security

### 扫描结果

| 检查 | 结果 |
| --- | --- |
| 硬编码 API Key / Token / Secret / Password | **未发现**。`git grep` 全仓库命中项全部是测试占位符（`TEST-ONLY-SECRET`、`SECRET`）、`${{ github.token }}`、Keychain 常量与本地化文案 |
| 私钥文件（`.pem/.p12/.p8/.key/.mobileprovision`） | **从未进入过 Git 历史**（`git log --all --diff-filter=A --name-only` 结果为空） |
| 真实账本数据进入仓库 | **未发现**。`.gitignore` 显式忽略 `stock-ledger-*.json`、`*.ipa`、`artifacts/`、`.env*`；历史中唯一被跟踪的备份文件是合成 fixture `tests/fixtures/v1-backup.json`（2 笔交易 + 1 条报价） |
| 疑似个人/券商信息 | **未发现**。汇丰相关代码只处理文件格式，不含任何真实账号 |
| 敏感日志 | 原生运行时不做文本日志；CI 的截图脚本会 dump 模拟器日志，但只进 artifact，不进仓库 |
| 密钥存储 | iOS 走 Keychain（`AfterFirstUnlock`）；**Web/其他平台走 Preferences（明文）**——`src/secure-settings.ts:8,16` |

**结论：无 CRITICAL 级泄露。** 未自动修改任何 Git 历史。

### 需要如实披露的隐私事实（Phase 4 README 必须写）

1. 行情请求会向 Yahoo / Finnhub / 用户自定义接口发出**持仓代码**（`QuoteService.swift:214-500`）。
2. 股票 Logo 走 `financialmodelingprep.com` 热链（`src/market.ts:12`）。
3. 账本、密钥均**不上传**，无账号体系、无云同步。
4. Keychain 存的是整段 `QuoteSettings` JSON，不是单独字段。

---

## Portfolio Readiness

以「一个陌生人在 30 秒内能否理解」为标准评估。

| 要求 | 现状 | 评级 |
| --- | --- | --- |
| 这是什么软件 | README 首段已说明（英文、定位清晰） | ✅ |
| 解决什么问题 | `## What this solves` 段落质量高 | ✅ |
| 核心功能 | `## Features` 完整 | ✅ |
| **软件长什么样** | 只有 5 张截图，且 **Hero 截图显示 `Awaiting data` / `Missing previous close` ×3 / `No ledger backup yet`**；缺 Import 页截图（任务书 §13 明确要求） | ❌ |
| 技术栈 | `## Tech stack` 表存在，但与实际不符（`Vitest (147)`、未提 Playwright/PDFKit 细节） | ⚠️ |
| 如何运行 | 有命令，但全是 macOS 脚本，未说明 Windows/Linux 用户能做什么 | ⚠️ |
| 如何测试 | 提到 Vitest + Swift + 模拟器渲染，未提 26 个 E2E 用例 | ⚠️ |
| 项目成熟度 | 有 CHANGELOG / 归档 / 发布链路；但 **无 LICENSE、无 Roadmap、无 Limitations、无 Disclaimer 章节** | ❌ |
| 架构可理解性 | 无架构图、无 `docs/ARCHITECTURE.md` | ❌ |
| 作品集叙事 | 无 `docs/CASE_STUDY.md` | ❌ |
| 仓库元数据 | 无 Description/Topics 证据（需在 Phase 5 确认）、无 badges | ❌ |

**另有：**

- 26 个 E2E 用例 + 完整 Page Object 素材是**强展示资产**，但因为没有 npm script、没有 CI，外部无法复现——等于不存在。
- 仓库根目录留着中文内部任务书 `US Stock Ledger — Portfolio Polish 开发任务书 V1.0.md`，文件名含空格与破折号，对英文访客不友好。
- `docs/archive/README.md:6-8` 仍写「当前发布版本 1.26，2.0 正在开发」。
- 版本线混叠：`releases/` 同时有 Web 的 v1.21–v1.26 与原生 v1.0.0，`publish-release.py:97-99` 每次全量遍历所有清单。

---

## Risks

分级标准：**P0** 可能造成数据损坏 / 安全问题 / 构建失败 / 核心功能不可用；**P1** 明显影响 Portfolio 质量、可靠性、测试、体验；**P2** 值得优化；**P3** 锦上添花。

### P0 — Critical（3）

| # | 问题 | 证据 | 影响 |
| --- | --- | --- | --- |
| P0-1 | **账本读/解码失败静默返回空账本** | `Store.swift:13-17`（两处 `try?`）+ `:29-31`（`.atomic` 整体覆盖） | 损坏但可抢救的账本无提示、无快照，下一次保存即永久覆盖。**唯一真实数据丢失路径** |
| P0-2 | **手动交易无超卖/超删守卫** | `TradesView.swift:286-313` 只校验正数/日期/代码；`Store.swift:185-201 saveTrade` 直接追加；`deleteTrade:203` 无检查；`Engine.swift:64` 无守卫 | 持有 10 股卖出 15 股 → `cost` 变负、`quantity` 变 −5 并**写入磁盘**，持仓从列表消失但已实现盈亏虚高。CSV/PDF 导入路径有 `validate` 保护，手动路径没有 |
| P0-3 | **载入示例会直接覆盖真实账本，且退出示例清空账本** | `Store.swift:381-388`（`loadDemo → replace → commit`）、`SettingsView.swift:84-91, 144-157`（仅确认框 + `demo.loaded` 标记） | 任务书 §6 Requirement 1/2/3 全部不满足。一次确认点击即不可逆丢失真实账本；无全局 DEMO 标识，用户极易误当真数据 |

> P0-2 与 P0-3 都需要用户主动操作才会触发，但后果都是**静默写盘**，符合 P0 定义。是否要在 Phase 1/2 一并修，请你决定（见「Recommended Phase 1 Preparation」）。

### P1 — Important（12）

| # | 问题 | 证据 |
| --- | --- | --- |
| P1-1 | Hero 截图显示降级状态（`Awaiting data` / `Missing previous close` ×3 / `No ledger backup yet`），首因劝退 | `docs/screenshots/holdings.png`；根因是 `LedgerStore.demo()` 无 `history`、无 `previousClose`（`Store.swift:40-74`） |
| P1-2 | 无 LICENSE | 全仓无 `LICENSE*` |
| P1-3 | README 缺 Architecture / Privacy / Disclaimer / Limitations / Roadmap / Demo Video 章节，无架构图 | `README.md` 全文（唯一图片是 `:84` 截图行） |
| P1-4 | 26 个 E2E 用例未接入任何 npm script 与 CI，且 `playwright.config.ts:1` 写死 Windows Chrome 路径 | `package.json:6-11`、`.github/workflows/*` |
| P1-5 | CI 无 `pull_request` 触发器 | `build-ios.yml:3-5` |
| P1-6 | 原生引擎（`dailyReturns`/`todayPnl`/`cashTotals`）无 Swift 单测，仅有 TS 端口测试 | `scripts/test-native.sh:6` 只编译 7 个核心文件；`tests/native/NativeTests.swift:66-98` |
| P1-7 | 质量门禁 Windows-only，且 CI 不跑它 | `scripts/hooks/pre-commit:11`（`powershell.exe`）；CI 无 `verify.ps1` 调用 |
| P1-8 | README 测试数过期（147 → 148） | `README.md:57`、`README.zh-Hans.md:57` |
| P1-9 | 英文模式下中文残留（导入提示、汇丰记录 note、PDF 提示） | `ImportView.swift:271,305`；`HSBCStatement.swift:122,144`；`StatementImport.swift` notice |
| P1-10 | 缺 Import 页截图（任务书 §13 明确要求） | `docs/screenshots/` 仅 5 张，无 import |
| P1-11 | 演示账本的日历/曲线数据是 harness 合成的 ±数字（−27 … +30），一眼假 | `tests/native/ScreenshotsApp.swift:63-76` |
| P1-12 | `AGENTS.md:85` 声称 CI 在 `deepseek-dev` 上跑，实际只有 `main` | `build-ios.yml:3-5` |

### P2 — Improvement（11）

| # | 问题 | 证据 |
| --- | --- | --- |
| P2-1 | `Ledger.format` 定义但从不校验 | `Models.swift:119` vs `Store.swift:13-17` |
| P2-2 | 节假日表只到 2028，之后 gap 检测退化 | `Engine.swift:168-176` |
| P2-3 | 原生备份导出无文件名 | `SettingsView.swift:63,140` |
| P2-4 | 恢复备份路径缺 `startAccessingSecurityScopedResource()`，与导入路径不对称（未实测） | `SettingsView.swift:112-119` vs `ImportView.swift:223` |
| P2-5 | iOS 死代码：`MarketClock.previousWeekday`、`QuoteService.parseYahoo`、`Engine.isBeforeOpening`、`Engine.monthStats`、`Appearance.themes`、`LedgerSecretsPlugin` | `QuoteService.swift:85-98,385-396`；`Engine.swift:136-140,304-311`；`RootView.swift:7`；`SceneDelegate.swift:35-70` |
| P2-6 | 无引用脚本：`customize-ios.mjs`、`make-icon.mjs`（且 `sharp` 不在 devDependencies） | 全仓 grep 无命中 |
| P2-7 | `version.test.ts` 硬编码版本号，发版必须改测试 | `tests/version.test.ts:12-13` |
| P2-8 | Web 侧 CSV 列数不符会整文件失败，与逐行错误粒度不一致 | `src/csv-import.ts:55` |
| P2-9 | Web `main.ts` 457 行、单行超 2000 字符、全量 `innerHTML` 重建 | `src/main.ts:115-161` |
| P2-10 | 双日期口径：设备本地 `today()` 与美东 `marketDate` 并存 | `src/ledger.ts:15,21` vs `src/market.ts:6` |
| P2-11 | `releases/` 双产品线混放，`publish-release.py` 全量遍历 | `releases/*.json`、`scripts/publish-release.py:97-99` |

### P3 — Optional（7）

无 CONTRIBUTING / SECURITY / CODEOWNERS / dependabot / PR 模板；README 无 badges；无 Demo Video 占位；次级文档全中文；`docs/archive/README.md` 陈旧；仓库根遗留中文任务书文件；`releases/` 命名与原生版本线未对齐（`native-v1.0.0` 标签 vs 新 `v1.0.0` 标签）；`previousClose` 仅内存导致冷启动短暂「待补全」。

---

## Recommended Phase 1 Preparation

> 只做设计，不实现。

### 直接结论：**Phase 1 可以被压缩，因为核心资产已经存在**

`LedgerStore.demo()` 已有完整示例账本（`Store.swift:40-74`），且 `AppState.init(ledger:settings:persist:)` 已经允许注入账本与持久化闭包（`Store.swift:120-122`）。**不需要新建 Demo Engine，也不需要新存储层**——只需要把「示例」从「替换生产账本」改成「挂在旁路的会话」。

### 逐条回答

**1. Demo Data 应该放在哪里？**

就地演进 `Store.swift:40-74` 的 `LedgerStore.demo()`，不要另建 `DemoData/` 目录。

- 它现在只有 5 笔交易 / 3 条现金 / 3 条报价，缺 `history`（`sessions` + `closes`）。
- Phase 1 应把它扩到任务书要求的规模（5 个持仓、30–50 笔交易、5–10 条分红、若干出入金、至少 1 个完全卖出 + 1 个部分卖出、正负收益各若干），并**补上与交易自洽的 `history`**。
- 这是修复 P1-1 与 P1-11 的关键：有了自洽 `history`，今日卡片不再显示 `Awaiting data`、日历不再是 ±27 的假数字。

**2. 是否应该使用独立 Storage？**

应该，但实现方式是「不落盘」而不是「第二个文件」。

- 推荐：Demo 会话 `persist` 注入一个**空实现**（或只写 `Demo/` 子目录），使示例数据永不触碰 `ledger-v2.json`。
- 这同时满足 Requirement 1（不覆盖真实数据）与 Requirement 2（退出即恢复）——因为真实账本从头到尾没被动过。

**3. 如何保证 Demo 不污染真实数据？**

- Demo 期间使用**独立 `AppState` 实例**（或同实例换 persist 闭包），并用 `@AppStorage("demo.active")` 标记会话。
- 退出 Demo = 丢弃该实例 + 重新 `LedgerStore.load()`。**禁止再出现 `replace()` 写盘路径。**
- 边界：`ledger-v2.json` 在 Demo 全程只读。

**4. 是否需要 Mock Market Data？**

需要，而且是 Requirement 4 的硬性要求。

- Yahoo 免密钥但有非官方限流风险；Finnhub 有 Key 与额度。
- 推荐：Demo 会话注入一份固定的 `QuoteService` 结果（或用 `AppState.setQuote` 写入示例报价），并在 Demo 期间**禁用自动刷新循环**（`RootView.swift:91-101`）。
- 示例 `history.sessions` 用固定日期表即可，不必联网。

**5. Demo Mode 最适合从哪里进入？**

两处，都不需要新页面：

1. 设置页现有按钮（`SettingsView.swift:84`）→ 改为「进入 Demo 会话」语义。
2. **空账本的首次进入态**：持仓页当前为空时，展示任务书 §6 的 `No portfolio data yet. / [Create Portfolio] [Try Demo] [Import Data]`（现有空态在 `HoldingsView.swift`，只需扩展）。

**6. 哪些现有模块可以直接复用？**

| 复用 | 位置 |
| --- | --- |
| 示例数据生成 | `LedgerStore.demo()`（扩充即可） |
| 注入式持久化 | `AppState.init(ledger:settings:persist:)` |
| 引擎与展示 | `Engine` / `LedgerDerived` 全部（Demo 与真实数据走同一套计算——这正是「Demo calculations are valid」的天然保证） |
| 截图 harness | `tests/native/ScreenshotsApp.swift`（已用 `LedgerStore.demo()` 出图） |
| 空态 | `HoldingsView` 现有空态 |
| 本地化 | `L10n`（新文案走 `L10n.tr`，顺带缓解 P1-9） |

**7. 哪些模块绝对不应该因为 Demo Mode 被修改？**

- `Engine.swift` —— 一行都不要动。Demo 必须走与真实数据**同一条计算路径**，否则「Demo calculations are valid」无从保证。
- `LedgerStore.load()/save()/write()` —— 只允许从**外部**传入不同的 persist，不允许改这些函数。
- `Models.swift` 的 `Codable` 结构 —— 不得为了 Demo 增删字段。
- `CsvImport.swift` / `HSBCStatement.swift` —— 与 Demo 无关。
- `Keychain` 路径 —— Demo 不得读写真实 Keychain 设置。

**8. 预计需要新增哪些文件？**

理想情况是 **0 个新增文件**（全部就地演进）。若为了清晰度拆分，最多 1 个：

- 可选：`DemoSession.swift`（承载 `demoLedger()` + `makeDemoState()`）。
- 不建议新建 `DemoData/` 目录树——与「最少文件」原则冲突，且 `Store.swift` 已有现成位置。

**9. 预计需要修改哪些文件？**

| 文件 | 改动性质 |
| --- | --- |
| `Store.swift` | 扩充 `demo()` 数据 + 增加「创建 Demo 会话」工厂（不碰 `load/save/write`） |
| `RootView.swift` | Demo 会话入口 + 全局 `DEMO` 标识 |
| `SettingsView.swift` | 按钮语义从「载入/退出并清空」改为「进入/退出 Demo」 |
| `HoldingsView.swift` | 空态三按钮 |
| `L10n.swift` | 新增文案词条（注意：**不要引入重复键**，`tests/l10n.test.ts` 会拦） |

**10. 最大 Regression Risk**

> **原生 Swift 侧没有覆盖 `Engine` 三大公式（`summary` / `dailyReturns` / `todayPnl`）的单测。**

具体传导链：

1. 为了做出好看的 Demo 截图，最容易的诱惑是「让 Demo 数据绕开引擎直接给出漂亮数字」——一旦这么做，Demo 与真实计算分叉，产品价值（真实口径）被悄悄削弱。
2. 为了补 `history`，会触碰 `LedgerHistory` 的构造；若格式写错，`dailyReturns` 的 gap/stray 检测会把所有日子标成「待补全」，而这**在 Swift 侧没有任何测试会失败**（只会在 CI 截图上表现为一堆 `—`，不是红灯）。
3. 同理，`AppState` 一旦被改成「可切换 ledger 来源」，`commit` 的「先落盘后改内存」不变量若被破坏，将直接撞上 P0-1。

**缓解建议（Phase 1 开工前或同时）**：把 `tests/native/NativeTests.swift` 的覆盖面扩到 `Engine.summary` 与 `dailyReturns` 的少量金标准断言（现成脚本 `scripts/test-native.sh` 已能编译运行，无需新框架）。这是**本仓库投入产出比最高的一步**。

---

## Do Not Touch

后续 Portfolio Polish 中，以下模块**原则上不要修改**。若确有改动需求，必须先说明收益与风险并单独立项。

| 模块 | 位置 | 理由 |
| --- | --- | --- |
| 投资组合计算引擎 | `Engine.swift:51-479` | 移动平均、已实现/浮动、每日收益、今日盈亏的唯一事实源；Web 与原生两侧口径一致，且是产品核心价值 |
| 交易数据模型 | `Models.swift:12-139` | `Codable` 结构即磁盘格式；任何字段增删都会破坏已有账本兼容性 |
| 账本持久化 | `Store.swift:7-38`（`LedgerStore`） | `.atomic` 覆盖语义 + 先落盘后改内存的不变量是数据安全的最后一道闸 |
| `commit` / `commitRefresh` | `Store.swift:152-179` | 并发 token 与后台编码逻辑；改动极易引入静默数据丢失 |
| 导入整批校验 | `CsvImport.swift:436-453`、`HSBCStatement.swift:49-200` | 超卖保护与 PDF 强完整性校验；放宽任何一条都会让脏数据进入账本 |
| Keychain 访问路径 | `QuoteService.swift:100-143` | service/account/可访问性变更会导致用户已保存的 API Key 失效 |
| 备份 / 恢复格式 | `SettingsView.swift:63-119`、`LedgerStore.exportText/encoded` | 用户唯一的外部数据保险 |
| 已归档文档 | `docs/archive/**` | 历史记录，任务书明确「旧标签及 Release 不改写」 |
| 已发布 Release 与标签 | `releases/v1.1.0`–`v1.26.0`、`v1.0.0`、`native-v1.0.0` | 同上 |

### 允许修改（Portfolio Polish 范围内）

- `README.md` / `README.zh-Hans.md` / 新增 `docs/*.md` / `LICENSE`
- `docs/screenshots/*`（重出图）
- `SettingsView.swift` / `HoldingsView.swift` / `RootView.swift` 的**展示层**（Demo 入口、空态、文案）
- `L10n.swift`（新增词条）
- `Store.swift` 的 `demo()` 数据与**新增**的 Demo 会话工厂（不改 `load/save/write`）
- `.github/workflows/*`（增加 PR 触发、接入 E2E）
- `package.json` scripts（新增 `e2e` / `lint`）
- `tests/**`（新增测试，禁止删除或放宽现有断言）
- `AGENTS.md`（修正与 CI 事实不符的描述）

---

## 审计方法与局限

- 方式：三名并行只读审计（Web 源码 / 原生 Swift / 测试与 CI 与文档）+ 关键路径人工复核（`Store.swift`、`Engine.swift:51-75`、`TradesView.swift:286-313`、`SettingsView.swift`、`README.md`）。
- 证据：所有结论附 `文件:行号`；凡未实际运行验证的推测均标注「未验证」。
- 局限：
  - 未在真机或模拟器上运行原生应用，**行为层结论来自代码阅读**。
  - macOS-only 的 Swift 测试与截图链路无法在本次 Windows 环境本地执行，其结论引自 CI 历史与脚本源码。
  - 未做全量 Git 历史的熵扫描；秘密检查为「文件名后缀 + 关键字 grep + 高风险模式」范围，非穷尽。
- 本阶段**未修改任何现有业务代码、配置、测试与工作流**；唯一新增文件为本审计报告。
