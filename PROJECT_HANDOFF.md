# 持仓账本项目总结与新窗口交接

更新日期：2026-09-26
用途：供新的 Codex / DeepSeek 对话先读取，再根据实际仓库状态继续工作。本文是项目过程摘要，不代替 `AGENTS.md`、代码、测试或 CI；如有冲突，以当前仓库事实和用户当轮明确要求为准。

## 1. 当前结论

- 2026-09-26 用户最终确认日历口径：**每日收盘浮盈快照**（该日剩余持仓市值减剩余成本），日期格子显示同日收盘值，不是每日投资收益或每日浮盈变化；可切换金额/百分比（浮盈÷剩余成本）。月份下方恢复**全月每日投资盈亏合计，包含当月买卖影响**，不累加快照。日历明细只含当日收盘仍持仓的股票。首页每日盈亏及累计收益曲线仍使用原每日投资收益口径；详见 `DAILY-RETURNS.md`。下文旧包/旧日历记录为历史过程，不代表最终日历定义。

- 当前源码版本：**原生版 1.1.0**；应用“关于”页仅显示 `1.1.0`，Xcode 内部构建号为 10。
- 1.1.0 是用户测试包目标，不代表已发布 GitHub Release；最新已发布 Release 仍为 `v1.0.2-build9`。
- 当前 UI：SwiftUI 原生 iPhone App，支持 iOS 16+。
- 最终 1.1.0 IPA 对应的源码提交：`2201daed82537efc20908b87b944ede842d792e6`；早期 1.1.0 测试包源码 `ac2b795` 为历史记录。
- build 9 源码提交：`639ca4bbe4a0adb845a91148b8ec66256f90e9e1`。
- GitHub 当前只保留一个 Release：`v1.0.2-build9`。
- Release：https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.0.2-build9
- `v1.0.2-build9` 未签名 IPA SHA-256：`7caac8451e4d21d8b23d53de25e1ece6cccdc69d1d7ac8e42cd22519850bfbc8`（历史发布资产）。
- 最终 1.1.0 unsigned 测试 IPA：GitHub Actions run `36215253909`，SHA-256 `a665d7f14f73176add3e821d4666fe59b7c8dbac65623729e8e1b7692a121a36`；本地 `build/1.1.0-final-2201dae/StockLedger-unsigned.ipa`，未创建 Release。
- 应用标识保持 `com.personal.stockledger`；账本仍为 `Documents/ledger-v2.json`、`format: 2`。
- 旧标签和 Git 历史保留，没有重写；旧 build 8 Release、资产和本地 build 8 IPA 已删除。
- `deepseek-dev` **没有在最后一次发布后同步**，不得声称它与 main 一致。

开始任何新任务前，必须重新执行只读检查，不能仅凭本文推断：

```powershell
git status --short --branch
git log -5 --oneline --decorate
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
```

## 2. 工作目录与 Git 约定

- Codex 正式工作目录：`C:/Users/PC/Desktop/开发/stock-ledger-recovered`。
- DeepSeek 工作目录：`C:/Users/PC/Desktop/开发/stock-ledger-deepseek`，长期分支 `deepseek-dev`。
- 正式构建和发布只能来自 Codex 工作目录的 `main`。
- DeepSeek 完成修改后，应先在 `deepseek-dev` commit/push；Codex 只读审核、测试，通过后再合并 main。
- 不得在 DeepSeek 工作目录制作正式包或发布。
- 不使用 `git add .`；只暂存明确文件。
- 不重写旧标签、历史或覆盖旧发布资产。
- `node_modules` 是指向 DeepSeek 工作目录的 junction，不要安装、清理或覆盖。
- 保留根目录三份未跟踪的 1.26 BUG 文档和未跟踪的嵌套 `stock-ledger-recovered/` 目录，不删除、不提交。

注意：当前 `AGENTS.md` 的 Portfolio 工作流段落写有“不要直接改 main”，而用户此前又明确规定 Codex 的正式修改只在 recovered/main 完成。这是现实存在的规则冲突。本文本次新增由用户明确授权；以后再修改代码时，应先读取实际 `AGENTS.md`，并以用户当轮对分支的明确授权为准，必要时先确认，不要自行猜测。

## 3. 产品定位与范围

这是个人使用的中文 iPhone 美股、ETF 记账 App，不是券商交易客户端。

已支持：

- 股票和 ETF 买卖、碎股、手续费、备注、交易筛选。
- 移动平均成本、已实现收益、浮动收益、账户总收益。
- 期初现金、入金、出金、分红、预扣税和账户费用。
- 今日／最近收盘收益、收益日历、累计收益曲线。
- Tiingo、Yahoo、Nasdaq 历史收盘兜底；Yahoo、Finnhub、自定义 HTTPS 最新报价。
- 自动、最近收盘、接口最新报价三种报价模式和前台定时刷新。
- CSV 字段映射、预览、错误提示、重复识别。
- 汇丰投资服务综合结单 PDF 导入。
- 备份恢复、深浅色、中英文、红涨绿跌／绿涨红跌、收益正负号。
- 示例模式；示例账本与真实账本隔离。

明确不支持：

- 券商下单或券商账户自动同步。
- 多币种换算。
- 做空和期权。
- 自动处理任意公司行动；拆股仍需按产品现有方式核对。
- 扫描版 PDF、任意其他机构 PDF、银行往来账户流水。

## 4. 数据和财务规则

后续修改不得破坏以下规则：

1. 入金、出金和期初现金不属于投资收益。
2. 分红净额、账户费用和证券收益各按自身口径计算，不能重复计入。
3. 买入费用进入成本；卖出费用从收入扣除；成本基础使用移动平均法。
4. 缺失行情必须显示“待补”，不能以零价或零收益伪装完整数据。
5. 不根据历史交易擅自推算真实现金余额。
6. 导入确认前不能修改正式账本；验证或保存失败不能部分写入。
7. 同日交易顺序会影响移动平均成本和已实现收益，不能随意重排。
8. 重复导入必须同时考虑银行编号和疑似手工重复。
9. 历史行情和报价失败时保留已有有效值，不以失败结果覆盖。
10. 更改恢复、导入或计算逻辑时，必须考虑旧数据、备份、交易顺序和重复记录。

## 5. 主要开发与问题处理经过

### 5.1 原生版基线：1.0.0 build 5

原生开发阶段曾使用 2.0.0 build 4。用户确认代码可用后，将其重新定义为原生版 1.0.0 build 5；这只是产品版本重新编号，没有把存储降回旧 Web 1.0，也没有改变收益口径。

- 基线标签：`native-v1.0.0`。
- 当时 main：`a7651d6`；设备包源码：`2d8fed3`。
- 构建记录：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35318039958
- 当时 IPA SHA-256：`6dc944aad6874073f6e1abede7a3642dead23cfe92b1a9ba8a541fcbd53f1e60`。

这一阶段确认了存储兼容边界：原生测试版 format 2 继续使用；旧 Web 版 1.26 及更早版本不自动迁移，也不复用旧版双槽恢复机制。

### 5.2 收益页性能和收益日历

曾出现收益页滚动卡顿：

- 将统计计算移到后台并复用账本计算缓存。
- 报价和现金变化尽量复用历史统计。
- 累计曲线使用保留的 Core Animation 图层和预计算路径，减少滚动时重建。

结论边界：后台计算耗时和模拟器截图不能当作真机帧率证明。

收益日历曾出现只显示第一周：

- 改为非懒加载的完整月份 Grid，按实际周数布局。
- 人工检查过四周、五周、六周月份，以及深色、大字体、缺行情、空数据和长列表来回滚动。
- 旧异常没有在模拟器稳定复现，因此不能宣称已经证明所有触发原因，只能说修改后检查通过。

### 5.3 收盘日期口径

亚洲日期跨日后，旧逻辑可能错误要求一个尚未产生的美股新交易日收盘价。之后改为按实际美东报价日期判断。

需要始终区分：

- Finnhub Key 影响最新报价来源。
- 固定收盘模式和收益历史并不会因为填写 Finnhub Key 就自动改用 Finnhub。
- 历史日线是单独的数据链路。

### 5.4 汇丰 PDF 导入边界

支持带文字层的汇丰投资服务综合结单：读取美元股票交易、关联费用和派付分红，预览确认后整体写入。

- 支持多文件和本机密码解锁。
- 已识别银行编号重复的记录禁止重复导入。
- 疑似手工重复默认不勾选，需要人工核对。
- 港币基金等不支持内容会排除。
- 结单没有的入金、出金和期初现金不能自动推算。
- 只有分红到账金额时不猜税率。
- 真实 PDF、CSV、交易数据和 API Key 不得提交到仓库或测试夹具。

### 5.5 Portfolio Polish：1.0.1 build 6

这一阶段主要改善作品集展示和工程闭环，没有改变核心收益口径：

- 示例模式与真实账本隔离。
- 错误提示可读化，系统原始错误只进入本机诊断。
- 修复窄屏横向溢出和英文文案遗漏。
- 设置页重组，账本信息只读。
- 增加 `checks` CI、E2E、架构和案例文档。
- 完成一次历史 secret 扫描；该结论只代表当时可达历史和扫描规则，不能绝对证明未来或所有不可达对象。

### 5.6 最终封版审计

用户要求只审计、不修改，唯一新增 `FINAL_RELEASE_AUDIT.md`。审计当时结论为：

- P0：0
- P1：2
- P2：6
- P3：1
- Verdict：`READY WITH KNOWN ISSUES`

两项 P1：

1. CSV/PDF 同日批量选择“插入之前”时，新记录内部顺序会反转，可能改变移动平均成本和已实现收益。
2. 备份页按记录数量缓存导出文本；恢复一份记录数量相同但内容不同的账本后，可能导出旧快照。

审计还记录了 SPY 历史收盘、重复 sequence、备份业务校验、安全作用域、表单保存失败反馈、PDF 临时副本清理和历史 secret 绝对措辞等 P2/P3。它们是审计时点的记录，并非 build 9 的重新审计结论；继续处理前必须对当前代码逐项复核，不能机械照搬旧行号或状态。

### 5.7 修复两个 P1：1.0.1 build 7

源码提交：`97c36ee`。

- CSV 和 HSBC PDF 共用的合并逻辑保留导入批次内部顺序。
- 点击导出时直接序列化当前 `state.ledger`，删除过期页面缓存。
- 增加手算场景、默认追加、空账本、跨日期、sequence、PDF 共用路径和备份接线回归测试。
- 不自动重排此前已经错误写入的历史记录；曾使用“插入同日之前”的用户仍需按原始凭据核对。

详细记录：`docs/BUILD_7_P1_FIXES.md`。

### 5.8 2026-09-22 收盘价缺失问题：build 8

用户在 2026-09-24 晚上发现多只股票仍显示“缺少 2026-09-22 收盘价”，反复刷新无效。最初解释不能只归因于市场尚未收盘：现实时间已经是 9 月 24 日，9 月 22 日应当已有正式收盘数据。后续排查确认这是历史数据源缺口／响应空值与应用兜底不足的问题。

build 8（源码 `2e91c8a`）增加了：

- Yahoo 某交易日明确为空时，尝试以 Nasdaq 同日历史收盘补洞。
- 手动“同步行情”同时同步收益历史。
- 后续刷新中的缺口不覆盖已经补齐的上一收盘基准。

但单靠另一个免费来源仍不能从产品层面保证未来永不缺数，因此 build 8 被后续 build 9 取代。

### 5.9 最终历史行情方案：1.0.2 build 9

源码提交：`639ca4b`；发布追踪文档提交：`c8b78c7`。

自动链路：

1. 用户配置 Tiingo EOD Key 后，以 Tiingo 日线为主。
2. Tiingo 失败时自动退回 Yahoo。
3. Yahoo 明确为空且前两者都未补齐的日期，再由 Nasdaq 补洞。
4. 任一来源失败都保留缓存，不写零价。

人工最终兜底：

- 在收益日历点开缺失日期，手工填写股票、日期和正式收盘价。
- 只允许账本已有股票、日历已有交易日和有效正价格。
- 手工值保存为 `source: "manual"`，优先于后续自动同步；可以再次录入修正。
- 这样不能保证第三方服务永远在线，但能保证用户不必无限等待数据源恢复，仍可依据可靠来源完成账本。

兼容性：`PricePoint` 只增加可选 `source` 元数据，旧账本缺字段按 `nil` 读取，仍为 format 2，不迁移文件。Tiingo Key 继续使用现有 iOS Keychain，不进入账本或备份。

## 6. 当前验证和发布证据

build 9 已通过：

- Vitest：149 项。
- Playwright E2E：26 项。
- 原生测试：505 项断言（其中固定断言 452 项，另含 heartbeat 检查）。
- TypeScript 类型检查和 Vite 构建。
- 原生日历渲染和英文界面截图检查。
- iPhoneOS ARM64 未签名 IPA 构建与结构校验。

CI：

- Checks：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35994735513
- Build unsigned iOS IPA：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35994735550
- Publish verified IPA release：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35996962476

本地已验证 IPA：

- 路径：`build/build9-verified/StockLedger-unsigned.ipa`（被忽略，不提交）。
- 版本：1.0.2 build 9。
- bundle id：`com.personal.stockledger`。
- 平台：iPhoneOS ARM64，最低 iOS 16。
- 大小：1,488,543 bytes。
- SHA-256：`7caac8451e4d21d8b23d53de25e1ece6cccdc69d1d7ac8e42cd22519850bfbc8`。

IPA 未签名，需要用户自行签名。覆盖安装前建议先导出备份，不要先卸载旧版。

## 7. CI 和本地验证方式

Windows 本机没有 Swift 工具链，不能把本地 Node 测试当作 iOS 构建证明。

本地质量门禁：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
```

主要命令：

```powershell
pnpm.cmd test
pnpm.cmd build
pnpm.cmd e2e
```

macOS / CI：

```bash
bash scripts/test-native.sh
bash scripts/test-calendar-rendering.sh
bash scripts/test-screenshots.sh
bash scripts/build-unsigned-ios.sh
```

新增 Swift 产品文件时，必须同时登记：

1. `ios/App/App.xcodeproj/project.pbxproj` 的四处 Xcode 项目引用。
2. `scripts/test-native.sh` 的显式 Swift 文件列表。

否则可能出现脚本测试通过、Xcode 构建却找不到类型的“假绿”。

## 8. 文档与发布现状

当前面向 build 9 的主要文档：

- `README.md`、`README.zh-Hans.md`
- `CHANGELOG.md`
- `HELP.md`
- `API-SETTINGS.md`
- `DAILY-RETURNS.md`
- `DATA-COMPATIBILITY.md`
- `docs/ARCHITECTURE.md`
- `docs/DEVELOPMENT.md`
- `docs/CASE_STUDY.md`
- `releases/v1.0.2-build9.md`

旧 Web 文档保存在 `docs/archive/`，只作历史参考。GitHub 当前只保留 build 9 Release；旧 Release 和资产已清理，但旧标签与提交历史保留。`CHANGELOG.md` 仍保留版本沿革，这是历史记录，不属于需要删除的旧 Release 文档。

`FINAL_RELEASE_AUDIT.md` 是 2026-09-22 的时点报告，其中两个 P1 已由 build 7 修复，因此不要把它原样当作当前发布结论。

## 9. 已踩过的协作和判断错误

- 不能只凭旧摘要断言仓库状态；每个新窗口都应先看实际分支、HEAD、工作树、远端和 `AGENTS.md`。
- 不能看到 API Key 已填写就假设所有历史行情也使用该 API；最新报价和历史日线是不同链路。
- 判断“收盘价尚未产生”必须核对现实日期、美东交易日和页面显示日期。2026-09-24 晚上仍缺 9 月 22 日收盘，不是正常等待现象。
- 测试通过不等于财务逻辑必然正确；最终审计的两个 P1 都曾处于测试全绿状态。
- 不能把模拟器截图或后台计算耗时当作真机帧率证据。
- 不能因旧异常无法稳定复现就宣称已证明全部根因。
- 数据供应商没有永久可用保证；可靠产品应有多源自动兜底和人工校正路径，而不是承诺某个免费接口永不失败。
- 发布必须闭环到源码提交、CI、IPA、校验和 Release；不能只说“Actions 已启动”。
- 同一分支连续 push 会取消前一轮 CI，必须等待最后提交对应的 run。
- 审核任务默认只读；只有用户明确授权实施时才修改、合并或发布。

## 10. 新窗口建议的第一条指令

可以在新窗口直接粘贴：

> 继续维护“持仓账本”。先完整读取仓库根目录 `AGENTS.md` 和 `PROJECT_HANDOFF.md`，然后在 `C:/Users/PC/Desktop/开发/stock-ledger-recovered` 只读核对当前分支、HEAD、工作树、origin/main、GitHub Release 和最近 CI。不要仅凭交接文档推断现状，不要删除或提交既有未跟踪文件。核对完成后先报告实际状态，再按我接下来的要求工作。

## 11. 1.1.0 测试包任务状态

最终提交 `2201daed82537efc20908b87b944ede842d792e6` 的 Checks（`36215253902`）与 Build unsigned iOS IPA（`36215253909`）均成功；本地 155 项测试及质量门禁通过，CI 原生测试、模拟器日历渲染、金额/百分比两种英文日历截图和 unsigned arm64 IPA 均通过。最终口径见第 1 节，不能再以旧日历定义继续修改。测试包版本仍为 1.1.0，未创建 GitHub Release。已校验包结构与 SHA-256，但最终真机验收需用户安装后确认。旧 build 9 标签、Release 和历史记录保留，不得改写。
