# 持仓账本 / Stock Ledger

个人自用的中文美股持仓账本，当前版本 **1.1.0（build 2）**。iOS 16 或更高版本，美元计价。

## 已实现功能

- 买入 / 卖出：代码、日期、碎股数量、成交单价、自动计算成交金额、手续费、备注。
- 自动持仓：移动平均成本，买入手续费计入成本；部分卖出按平均成本扣减。
- 收益：已实现收益扣除卖出手续费；打开 App / 返回前台时自动读取最近已完成交易日的收盘价并重算市值、浮动收益；支持手动刷新及手动报价。
- 公司 Logo：按股票代码加载 Financial Modeling Prep 公司图片；加载失败时保留代码首字母，不影响记账。
- 编辑 / 删除：全量重算历史交易，拒绝导致任一历史时点超卖的变更。
- 备份：JSON 导出、文件导入校验、预览和确认替换；所有报价及备注保留。
- 本机持久化：iOS UserDefaults，通过 Capacitor Preferences 写入；两份交替存储，最新副本损坏时回退，并提示核对。两份均损坏时禁止写入，不静默清空账本。
- 独立示例模式：虚构交易仅保存在内存，不污染真实账本。

## 范围与计算口径

此版本支持最多 5,000 笔交易。股数和金额输入支持 8 位小数，计算使用 decimal.js（40 位精度），只在展示时四舍五入。成交金额由数量乘单价计算，不独立改写。日期按所填交易日排序，同日按录入顺序计算，编辑保留原顺序。

不含券商同步、分红、拆股、做空、期权、多币种或税务成本计算。收益页面不是税务报表。未填写所有持仓报价时，总市值和总浮动收益显示为缺失，不以零估价。已有报价会一直沿用，并显示日期。

## 在 Windows 预览

需要 Node.js 24 与 pnpm 11.19.0。

```sh
pnpm install --frozen-lockfile
pnpm dev
```

打开终端显示的本机地址。也可以运行 `pnpm build` 后用 `pnpm exec vite preview --host 127.0.0.1` 查看生产版本。

预览版数据仅保存在该浏览器中，不会自动同步到 iPhone。正式 iOS 应用使用原生持久化存储。

## 生成待签名 IPA

本项目包括完整 iOS Xcode 工程。Windows 可以生成网页资源和同步工程，但无法执行 Xcode 编译。

1. 把项目上传到你自己的 GitHub 仓库，包含 `.github/workflows/build-ios.yml`。
2. 打开仓库的 **Actions → Build unsigned iOS IPA → Run workflow**（推送 main 分支也会触发）。
3. 工作流在 GitHub 的 macOS 26 环境安装锁定依赖、运行测试、构建网页资源并同步 iOS 工程。
4. Xcode 编译真机 ARM64 程序，禁用构建时签名。脚本验证可执行文件架构、iPhoneOS 平台和内置界面资源，再包装 `Payload/App.app`。
5. 下载 `StockLedger-unsigned-IPA` 产物，解压得到 `StockLedger-unsigned.ipa` 及 SHA-256 校验值。
6. 用 Sideloadly 和你自己的 Apple 账号签名安装。

编译不需要你的 Apple 账号、密码或证书。GitHub Actions 计算资源会计入你账号的配额；私有仓库的计费取决于账号设置。

本地生成的 `dist` 是预览资源，不是 IPA。真机安装、原生文件分享和原生存储仍需在签名后验证。

有 Mac 时也可执行：

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm build
pnpm exec cap sync ios
bash scripts/build-unsigned-ios.sh
```

## 签名及数据保留

应用标识：`com.personal.stockledger`。覆盖升级请保持相同 Apple 账号和应用标识，不要先卸载旧版。免费个人签名需定期续签。卸载会删除本机数据，请先在“备份”页导出到“文件”中的安全位置。备份 JSON 未加密。

## 检查

```sh
pnpm test
pnpm build
pnpm exec playwright test
```

Windows 界面测试使用默认安装位置的 Chrome；其他系统先运行 `pnpm exec playwright install chromium`。测试覆盖买卖、手动股价、重载持久化、修改重算、超卖删除拦截、备份导出及替换恢复、损坏备份拦截、示例数据隔离和移动端溢出检查。

技术：TypeScript + Vite + Capacitor 8 + decimal.js + Lucide。没有账户登录、后台服务器或遥测。行情和 Logo 请求只发送股票代码，不上传账本、数量、金额或备注。依赖分别遵守其原有许可证。


## 1.1 升级与收盘收益同步

1. **先在第一版导出 JSON 备份到 iPhone「文件」中。** 保留这份备份，直到核对新版的数据。
2. 新 IPA 使用原来的 Apple 账号、签名工具和最终应用标识进行**覆盖安装**，不要卸载第一版。工程标识仍为 `com.personal.stockledger`。
3. 早上打开 App，持仓页「收盘行情」会自动更新；停留在后台后返回 App 也会检查。同一次运行中，15 分钟内不重复自动请求，可点「更新收益」手动刷新。
4. 每只股票显示**纽约交易日期**。周末、节假日延用最近交易日；未完成的日线不参与更新；当天收盘后等待 15 分钟再采用当天收盘价（支持夏令时和提前收盘）。
5. 更新只改变持仓报价，自动重算**持仓市值、浮动收益、累计投资收益**。已实现收益仍来自买卖记录。此版本没有每日收益历史曲线，也不会自动录入交易、分红或拆股。
6. 请求失败、限流或无匹配股票时保留原报价并显示原因；日期不同的报价可能共同参与总估值，请查看日期。报价距纽约当天超过 4 个自然日时显示「日期较早」，这不是交易所休市日历判断。
7. 同日手动报价优先，更早的自动报价也不会覆盖手动价格；之后交易日的收盘价会继续更新。编辑期间到达的行情批次不会覆盖正在编辑或刚保存的账本，可稍后手动重试。

### 行情来源与限制

当前使用 Yahoo Finance 公共 chart 数据接口（非承诺稳定的正式开发者 API），无需填写密钥。此接口可能变更、限流、延迟或不可用；不承诺连续服务。读取未复权的日线 close，按服务返回的价格精度处理。仅自动匹配纽约时区、美元计价的股票与 ETF，并校验返回代码；例如 `BRK.B` 对应请求 `BRK-B`。不使用盘前盘后报价作为当天收盘价。

iOS 通过 [Capacitor 原生 HTTP](https://capacitorjs.com/docs/apis/http) 请求行情；Windows 普通浏览器可能受行情站点跨域限制，届时仍能记账和手动输入价格。没有代理服务器，也不绕过服务方限流。行情数据说明见 [Yahoo 的交易所及数据来源](https://help.yahoo.com/kb/SLN2310.html)。

Logo 使用 [Financial Modeling Prep 的公司图片](https://financialmodelingprep.com/image-stock/AAPL.png)，按代码请求；覆盖范围由服务方决定，冷门代码、改名及网络失败时可能没有图片。图片加载使用无 referrer 请求，系统可能缓存图片；不保证离线首次可见。

### 第一版备份兼容

- JSON 主格式仍为 `version: 1`、`currency: USD`、`method: moving-average`。交易字段、金额字符串精度、排序和成本算法不变。
- 原生存储键仍是 `stock-ledger-v1-0` / `stock-ledger-v1-1`，不清空或搬迁已有账本。
- 旧报价 `{symbol, price, date}` 完整支持；新增自动报价可附带 `source: yahoo-close` 和 `fetchedAt`，备份时一起保留。第一版也能读新版备份的交易和价格（会忽略新增来源字段）。
- 文件选择器接受 `.json` 和误命名的 `.js` 文件，但**内容必须是 JSON**。不会执行 JavaScript 代码，不支持 `const data = ...` 之类脚本。
- 导入仍先完整校验与预览，再由你确认替换。测试使用虚构的第一版格式样本，未上传你的真实账本。

详细更新记录见 [CHANGELOG.md](CHANGELOG.md)，构建验证状态见 [STATUS.md](STATUS.md)。


## 正式版本下载与持续发布

正式 IPA 在 [GitHub Releases](https://github.com/chengxiaomingcxm/us-stock-ledger/releases) 下载。每个版本附带版本化 IPA、SHA-256 校验文件及独立升级说明，标签指向该 IPA 的原始构建提交。Release 附件不受本项目 Actions 构建产物的 14 天自动过期设置影响，除非维护者删除发布记录或附件。

后续版本发布流程：

1. 更新应用版本和 build 号，完成旧备份兼容性检查，推送代码并等待 `Build unsigned iOS IPA` 成功。
2. 新建 `releases/v版本号.md`，写明更新内容、升级步骤、已验证项目及限制。
3. 参照 `releases/v1.1.0.json`，记录版本、build、该构建的 commit / run_id / artifact 和实际 IPA SHA-256。
4. 将两个发布文件提交到 main，自动触发 `Publish verified IPA release`。也可在 Actions 手动重跑此工作流。
5. 发布程序核对构建成功状态、提交、IPA 架构、应用标识、版本、build 和校验值，先创建草稿并上传全部附件，再正式发布。
6. 已发布版本不覆盖：重跑会核对现有标签和 IPA 摘要并跳过；新修复使用新版本号。若源构建已过期且未发布，需重新构建并记录新的 run_id 与真实校验值。

发布时使用 GitHub Actions 自带的临时令牌，仅发布任务具备 contents:write / actions:read；不需要上传个人 Token、Apple 密码、签名证书或真实账本。主分支普通构建仍只读仓库；公开访问不授予访客写入权限。

个人备份、签名文件和 `.env` 已加入忽略规则。测试中的账本均为虚构数据，不要将真实备份提交到公开仓库。
