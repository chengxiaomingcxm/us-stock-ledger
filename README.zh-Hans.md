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
| 测试 | Vitest（147 项）+ Swift 原生测试 + 模拟器日历渲染 |
| CI | GitHub Actions（macOS） |

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

## 截图

即将补充（英文界面）。
