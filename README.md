# 持仓账本

这是我自己用的美股记账 App，用来记录买卖、核对现金和查看收益。界面用 SwiftUI 开发，数据保存在 iPhone 本机，不用注册账号。

当前版本是 **原生版 1.0.0（build 5）**，支持 iOS 16 及以上。这一版以已验收的 2.0.0 build 4 为基础重新编号，功能和计算方式不变。旧 Web 版的版本号、标签和发布记录保留，和原生版分开看。

## 日常使用

- 记录美元美股、ETF 的买卖、手续费和备注，查看持仓成本、已实现和浮动收益。
- 设置期初现金，记录入金、出金、分红、税费与账户费用。入金和出金不计入收益。
- 查看每日收益日历和累计曲线；缺少行情的日期会标为待补。
- 导入券商 CSV，或汇丰投资服务综合结单 PDF；先核对预览，再确认写入。
- 使用 Yahoo 收盘价、Finnhub 或自定义报价接口，选择自动、收盘或最新报价模式。
- 导出和恢复账本，切换深浅色及红涨绿跌／绿涨红跌。收益始终保留正负号。

目前不连接券商下单，不做多币种换算、做空、期权或自动拆股处理。汇丰投资结单不等同于银行现金账户流水，不能据此自动补出所有入金、出金和真实现金余额。

## 安装与数据

IPA 需要自行签名后安装。应用标识仍为 `com.personal.stockledger`，现有原生账本文件和 API 设置位置不变。覆盖安装前导出备份，并保持原签名身份，不要先卸载。

此前标为 2.0 的原生测试版账本继续使用。旧 Web 版 1.26 及更早版本的账本不会自动迁移到原生版；应用版本改为 1.0 不代表存储格式也回到旧版。

[使用帮助](HELP.md) · [行情设置](API-SETTINGS.md) · [收益口径](DAILY-RETURNS.md) · [数据兼容](DATA-COMPATIBILITY.md) · [更新记录](CHANGELOG.md)

## 开发

原生代码在 `ios/App/App/StockLedger/`，入口使用 SwiftUI。仓库还保留 TypeScript / Vite / Capacitor 工程，用于旧网页实现、测试和现有打包流程；`pnpm dev` 展示的是网页版本，不是原生界面。

Node.js 24、pnpm 11.19.0：

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm build
```

macOS / Xcode 上运行原生验证和打包：

```sh
bash scripts/test-native.sh
bash scripts/test-calendar-rendering.sh
pnpm exec cap sync ios
bash scripts/build-unsigned-ios.sh
```

GitHub Actions 从 `main` 测试并构建设备包，IPA 在构建任务的 `StockLedger-unsigned-IPA` 附件里。日历截图使用合成数据，保存在 `Calendar-rendering` 附件中，需人工核对。

Codex 使用 `stock-ledger-recovered` 的 `main`；DeepSeek 使用 `stock-ledger-deepseek` 的 `deepseek-dev`。开发分支先提交并推送，审核后合并到 main；正式包只从 main 构建和发布，发布后再同步开发分支。
