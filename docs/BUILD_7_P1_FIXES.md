# 1.0.1 build 7：两项 P1 修复

日期：2026-09-22。基于 main `b6ee84d`，对应 [封版审计](../FINAL_RELEASE_AUDIT.md) 的 F01、F02。其余发现不在本次修复范围。

## 同日批次顺序

CSV 和汇丰 PDF 共用 `CsvImport.merge`。插入已有同日记录之前时，改为倒序遍历待插入批次，避免每次插入首位把新记录顺序反转。默认追加逻辑不变，仍按日期排列并统一重编 sequence。

独立手算回归：已有前一天 100 股 @10、当天 1 股 @10；将当天买 100 股 @20、卖 100 股 @30 插在已有当天记录之前。正确结果为已实现 1500、剩余成本 1510、持仓 101。修复前为 2000/2010/101。

原生测试覆盖上述金额、默认追加、空账本、跨日期、sequence 及 PDF 共用路径。

本次不会自动重排已经写入账本的历史记录。若曾使用“插入同日之前”导入过多笔同日交易，请先备份，再按原始凭据核对顺序；无法靠新版本自动还原当时的输入顺序。

## 备份当前快照

删除页面级 `exportText` 缓存与按记录数量刷新的监听。点击导出时直接序列化 `state.ledger`，成功才打开分享面板；编码失败仍显示既有错误说明并记录本机诊断。

原生测试检查恢复一份记录数量相同、价格与期初不同的账本后，导出 JSON 包含新内容。Vitest 接线检查保证实际 SwiftUI 按钮调用点击时序列化路径，不重新引入页面缓存；它不替代真机交互测试。

## 版本与兼容性

- MARKETING_VERSION / package.json：1.0.1。
- CURRENT_PROJECT_VERSION：7（Debug、Release 同步）。
- `com.personal.stockledger`、`Documents/ledger-v2.json`、format 2 与 Keychain 键不变。
- 最终 GitHub Release 使用新标签 `v1.0.1-build7`，旧标签和 Git 历史不改写。旧 Release 及资产已清理。
- 审计报告保留原审计日期与原结论，本文件记录后续修复。

## 验证

本地质量门禁通过：Vitest 149 项 / 14 文件，TypeScript 类型检查与 Vite 构建通过。

main 提交 `97c36ee` 的 [Checks](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35732783809) 通过：Vitest 149 项、Playwright 26 项、类型检查及构建全部成功。[Build unsigned iOS IPA](https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35732783834) 也已通过：原生 Swift 测试、日历渲染、英文界面截图、设备构建和 IPA 上传均成功。

下载后使用 `scripts/verify-ipa.py` 校验：版本 1.0.1、build 7、bundle id `com.personal.stockledger`、iPhoneOS ARM64、最低 iOS 16.0，不依赖外部开发服务器。IPA 未签名，需自行签名安装。

SHA-256：`705ee38a7597471c25174ffc4b873ecd5650e3b96822f8188a49cc8fb9b41648`。
