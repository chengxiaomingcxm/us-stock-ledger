# 交付状态

更新：2026-09-15

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
