# 交付状态

更新：2026-09-15

## 1.2.0 / build 3

- 每日收益、收益日历、收盘累计曲线、本机恢复记录已实现。
- 52 项单元测试通过，包括真实 v1.0/v1.1 解析器与新版备份互操作。
- 5 项浏览器流程通过，覆盖历史修改重算、两种导出、本机恢复及原有升级流程。
- TypeScript、生产构建和原生资源同步通过。
- 真实网络检查：AAPL 与 SPY 各取得 63 个已完成日线，最新日期 2026-09-14。
- 云端 Xcode 构建成功：[运行记录](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/34974847468)。
- 二进制源码提交：0d67d852ee73ad9852bc76e438869e77e60220d0。
- 已核对 iPhoneOS / ARM64、1.2.0 / build 3、原应用标识与 AppPlugin。所有内置网页文件与本地测试通过的最终 dist 完全一致。
- IPA 546,910 字节；SHA-256：`56b271203131c31069d88d4dbeab50dc8487a116cd9ca1b46324be0a7cb79987`。
- 外层 ZIP 摘要与 GitHub artifact digest 一致：`1047d388788622b6e4807cfcf2431b9266d1bf8419d576415e1e7bf1140316f0`。
- [v1.2.0 正式 Release](https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.2.0) 已发布 IPA、同名 .sha256 与 UPGRADE-1.2.0.md；已核对公开附件摘要及版本标签准确指向构建源码。
- [自动发布流程](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/34975480297)成功；已发布 v1.1.0 保持原样。
- 未在用户 iPhone 上验证本次覆盖安装和原生分享。升级前导出备份，保持相同签名账号及应用标识，不先卸载旧版。

## 1.1.0 / build 2

- 用户已确认使用「早上打开 App 自动更新 + 手动刷新」，不要求后台定点执行。
- 39 项计算、存储、旧备份兼容、交易时段及报价更新测试通过。
- 4 项浏览器流程测试通过，包括第一版原存储直接升级、自动更新、失败保留、旧备份恢复、编辑时响应保护、Logo 失败回退和原有记账流程。
- TypeScript 类型检查、生产构建和原生工程同步通过。
- 实际网络检查：新版解析逻辑成功读取 AAPL、MSFT、NVDA 的 2026-09-14 收盘价；Financial Modeling Prep 的 AAPL 图片返回有效 PNG。实际界面确认 AAPL / MSFT / NVDA Logo 显示。
- 云端 Xcode 编译成功，已下载并验证 iPhoneOS / ARM64、1.1.0 / build 2、原应用标识及内置资源。
- IPA 内所有网页文件与本地通过测试的生产文件完全一致；原生 AppPlugin 已包含。
- 构建记录：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/34968514231
- 二进制对应提交：9fb091d6bb58d5d2ff63ea209bab1a2346b8b2e9
- 产物名称：StockLedger-unsigned-IPA；IPA 541,732 字节，未签名。
- IPA SHA-256：e245713be61edc64fcce534f0a8f744af12b659e6171eb2fcc6c5052dad768c9
- 外层 ZIP SHA-256：8bc85eb2340b78d6ce166612afa4fb98240f3c59872dc127f38cdd37eedb28c7，与 GitHub 产物摘要一致。
- 尚未在用户 iPhone 上验证本次覆盖安装、原生前台唤醒和实际网络连接；签名后需核对第一版持仓、成本与交易笔数。

## 第一版记录

用户报告第一版已安装并录入基础数据。

- 构建：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/34961045118
- 二进制对应提交：e06032994ca92d78bd343275accb1f66cb92cb80
- 第一版 IPA SHA-256：37bb3a0d6ff63e208123060ff940c0c30151d835a1a0062ad6977b97f1ae4415

新旧版本均使用 com.personal.stockledger；安装新版前先导出备份，不要卸载旧版。


## 仓库公开与正式发布

- 已确认仓库为 Public（公开）。此前检查 6 次提交的历史文本，未发现密钥或真实账本；备份样本为虚构测试数据。
- v1.1.0 正式 Release：https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.1.0
- 已附带 StockLedger-1.1.0-unsigned.ipa、同名 .sha256 校验文件及 UPGRADE-1.1.0.md。
- Release IPA SHA-256 与上方原交付文件一致；版本标签对应原始构建提交 9fb091d6bb58d5d2ff63ea209bab1a2346b8b2e9。
- 正式附件不受 Actions 临时构建产物的 14 天过期设置影响。
- 已上传可重复使用的发布工作流、发布校验脚本及版本清单。历史版本首次归档使用 GitHub 页面完成，原因及处理方式见 README。
- 重跑发布流程已成功，确认已发布版本的标签与 IPA 摘要，未替换附件。验证记录：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/34970988375 （第 2 次运行）。
- 本次仅调整仓库与发布管理，App 功能版本仍为 1.1.0，无需因此重新安装。
