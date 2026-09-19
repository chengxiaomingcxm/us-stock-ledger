# 持仓账本

这是我自己用的美股记账 App，用来记录买卖、核对现金和查看收益。界面用 SwiftUI 开发，数据保存在 iPhone 本机，不用注册账号、不连云、不追踪。

> **English 主 README：[README.md](README.md)。** This is the Chinese version; see [README.md](README.md) for the English main readme.

## 解决什么问题

券商 App 只会展示当下的持仓，很少回答个人投资者真正关心的问题：

- **我到底花了多少钱？** 多笔买入按加权平均成本计，手续费算进成本。
- **我到底赚了多少？** 已实现收益、浮动收益、分红（扣税）、账户费用分开算，入金和出金绝不计成盈亏。
- **今天、以及每一天涨跌多少？** 今日盈亏对照上一收盘，加上每日收益日历和累计收益曲线。
- **和券商对得上吗？** 导入券商 CSV 或汇丰投资结单 PDF，先预览再写入，重复记录不会漏进账。
- **我的现金在哪？** 期初余额、入金、出金、分红、费用，买卖现金流自动联动核对。

不连接券商下单，不做多币种换算、做空、期权或自动拆股处理。

## 功能

- 美元美股、ETF 的买卖、手续费和备注。
- 持仓：平均成本、已实现与浮动收益、当前市值、报价来源与新旧。
- 今日盈亏：上一收盘 + 当前价格 + 当日买卖和手续费；缺行情显示「待补全」，不以零代替。
- 现金账本：期初余额、入金、出金、手动分红（含税费）和账户费用。
- 每日收益日历和累计收益曲线（每周刻度 + 零轴）。
- 行情：Yahoo 日线收盘、Finnhub 或自定义 HTTPS 接口；API Key 存 iOS 钥匙串。
- 导入带预览确认：券商交易/资金 CSV 和汇丰投资结单 PDF。
- 本地 JSON 备份与恢复；超过 30 天未备份有提醒。
- 深/浅色、红涨绿跌／绿涨红跌、动态字体和 VoiceOver。

## 先体验示例账本

安装后打开 **设置 → 载入示例账本**，无需注册即可浏览一套示例持仓（买卖、分红、费用、期初余额）；准备录自己的数据时用「退出示例并清空账本」。

## 安装（不懂代码也能装）

1. 从最新 [Release](https://github.com/chengxiaomingcxm/us-stock-ledger/releases)（例如 `v1.0.0`）下载 `StockLedger-unsigned.ipa`。
2. 在电脑上装一个免费签名工具，例如 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/)。
3. 连上 iPhone，打开工具，把 IPA 拖进去，用你自己的 Apple ID 登录。
4. 保持应用标识 `com.personal.stockledger`，选**覆盖安装**——不要先卸载旧版，否则会丢账本。
5. 定期在 **设置 → 导出账本备份** 备份，文件存到应用之外。

IPA 未签名，因为没有付费的 Apple 开发者账号；每个 Release 旁边有校验和，可核对下载文件。

## Release 版本

用正式语义化版本号（`v1.0.0`、`v1.1.0`…）。见 [Release 页面](https://github.com/chengxiaomingcxm/us-stock-ledger/releases) 和 [CHANGELOG.md](CHANGELOG.md)。

## 技术栈

| 层 | 技术 |
| --- | --- |
| 原生 iOS App | SwiftUI，iOS 16+，Swift 5 |
| 存储 | Documents 本地 JSON；API Key 存 iOS 钥匙串 |
| 结单 | PDFKit（汇丰投资结单） |
| 旧网页引擎（保留用于构建/测试） | TypeScript、Vite、Capacitor |
| 测试 | Vitest（148 项）+ Swift 原生测试 + 模拟器日历渲染 + Playwright E2E（26 项） |
| CI | GitHub Actions：`checks` 跑在 ubuntu-latest，iOS 构建跑在 macos-26 |

## 目录

- `ios/App/App/StockLedger/` — 原生 SwiftUI App。
- `src/`、`tests/` — 旧网页引擎及其测试。
- `scripts/` — 原生测试、模拟器渲染、IPA 构建与校验脚本。
- `releases/` — 各版本发布说明。
- `docs/archive/` — 旧网页版文档归档。

## 开发

```sh
pnpm install --frozen-lockfile
pnpm test
bash scripts/test-native.sh              # macOS
bash scripts/test-calendar-rendering.sh  # macOS
bash scripts/build-unsigned-ios.sh       # macOS，产出 IPA
```

开发在 `deepseek-dev` 上进行；审核通过后合并到 `main`，正式 IPA 只从 `main` 构建发布。

## 测试与 CI

推 `main` / `deepseek-dev` / `portfolio/**`，以及**任何 PR**，都会在 GitHub Actions 上跑同一套检查 —— 全部复用 `package.json` 里已有的 script，没有为 CI 另造新命令：

```sh
pnpm install --frozen-lockfile
pnpm test     # vitest run —— 148 项，13 个文件
pnpm build    # tsc --noEmit && vite build
pnpm e2e      # playwright test —— 26 项
```

`.github/workflows/checks.yml` 在 `ubuntu-latest` 上跑上面这条链；`.github/workflows/build-ios.yml` 另外在 `macos-26` 上跑 Swift 原生测试、模拟器日历与截图渲染、未签名 IPA 构建。iOS 只能在 macOS runner 上构建，而且产物是**未签名**的 —— 要装到真机仍需你自己的签名身份。

> 只改 Markdown（`**/*.md`）的提交不会触发这两个工作流，只改 Markdown 的 PR 同理。

### 静态检查：有意不引入 ESLint

任务书 §11 要求 CI 跑 Lint。本仓库**没有 ESLint、没有 eslint 配置、也没有 `lint` script**，`AGENTS.md` 明确禁止在仓库本就不存在的情况下自行引入这类工具。所以 CI 不跑 Linter —— 这是**有意偏离，不是遗漏**：

- `package.json` 没有新增 `lint` script，也**没有**把类型检查改名叫假的 `lint`。
- 静态检查就是现有 `pnpm build` 已经在做的 **`tsc --noEmit`**（`strict: true`，覆盖 `src/`、`tests/` 与 `capacitor.config.ts`；不覆盖 `e2e/` 与 shell 脚本）。
- 将来若要引入 Linter，应当单独决策（依赖 + 配置 + 人对接下新报出的问题），而不是为了勾选清单。

## 截图

| 持仓 | 交易 | 收益 | 设置 | 日历 |
| --- | --- | --- | --- | --- |
| ![持仓](docs/screenshots/holdings.png) | ![交易](docs/screenshots/trades.png) | ![收益](docs/screenshots/returns.png) | ![设置](docs/screenshots/settings.png) | ![日历](docs/screenshots/calendar.png) |
