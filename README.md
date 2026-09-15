# 持仓账本 / Stock Ledger

个人自用的中文美股持仓账本。iOS 16 或更高版本，美元计价。

## 已实现功能

- 买入 / 卖出：代码、日期、碎股数量、成交单价、自动计算成交金额、手续费、备注。
- 自动持仓：移动平均成本，买入手续费计入成本；部分卖出按平均成本扣减。
- 收益：已实现收益扣除卖出手续费；手动填写股价及报价日期后计算市值、浮动收益。
- 编辑 / 删除：全量重算历史交易，拒绝导致任一历史时点超卖的变更。
- 备份：JSON 导出、文件导入校验、预览和确认替换；所有报价及备注保留。
- 本机持久化：iOS UserDefaults，通过 Capacitor Preferences 写入；两份交替存储，最新副本损坏时回退，并提示核对。两份均损坏时禁止写入，不静默清空账本。
- 独立示例模式：虚构交易仅保存在内存，不污染真实账本。

## 范围与计算口径

此版本支持最多 5,000 笔交易。股数和金额输入支持 8 位小数，计算使用 decimal.js（40 位精度），只在展示时四舍五入。成交金额由数量乘单价计算，不独立改写。日期按所填交易日排序，同日按录入顺序计算，编辑保留原顺序。

不含自动行情、券商同步、分红、拆股、做空、期权、多币种或税务成本计算。收益页面不是税务报表。未填写所有持仓报价时，总市值和总浮动收益显示为缺失，不以零估价。已有报价会一直沿用，并显示日期。

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

1. 把项目上传到你自己的 GitHub 私有仓库，包含 `.github/workflows/build-ios.yml`。
2. 打开仓库的 **Actions → Build unsigned iOS IPA → Run workflow**（推送 main 分支也会触发）。
3. 工作流在 GitHub 的 macOS 26 环境安装锁定依赖、运行测试、构建网页资源并同步 iOS 工程。
4. Xcode 编译真机 ARM64 程序，禁用构建时签名。脚本验证可执行文件架构、iPhoneOS 平台和内置界面资源，再包装 `Payload/App.app`。
5. 下载 `StockLedger-unsigned-IPA` 产物，解压得到 `StockLedger-unsigned.ipa` 及 SHA-256 校验值。
6. 用 Sideloadly 和你自己的 Apple 账号签名安装。

编译不需要你的 Apple 账号、密码或证书。GitHub Actions 计算资源会计入你账号的配额；私有仓库的计费取决于账号设置。

**未实际运行 macOS 工作流前，不能声称 IPA 已构建成功。**本地生成的 `dist` 是预览资源，不是 IPA。真机安装、原生文件分享和原生存储仍需在签名后验证。

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

技术：TypeScript + Vite + Capacitor 8 + decimal.js + Lucide。没有账户登录、后台服务、遥测或行情网络请求。依赖分别遵守其原有许可证。
