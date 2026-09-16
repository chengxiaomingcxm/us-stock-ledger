# 美股持仓账本｜项目摘要

更新：2026-09-16。当前界面版本 **1.21**，内部版本 **1.21.0（build 4）**。

## 仓库与文件
- GitHub：https://github.com/chengxiaomingcxm/us-stock-ledger
- 正式下载：https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.21.0
- 本地工程：C:/Users/PC/Desktop/New folder (2)/stock-ledger
- Git 跟踪副本：C:/Users/PC/Desktop/New folder (2)/stock-ledger-github
- 本地安装包：stock-ledger/delivery/1.21.0/StockLedger-1.21.0-unsigned.ipa
- 技术：TypeScript、Vite、Capacitor；最低 iOS 16；应用标识 com.personal.stockledger。

## 1.21 已完成
- 液态玻璃风格浮动导航、控件和弹窗；财务内容保持可读性，适配减少动态效果、减少透明度及提高对比度。
- CSS touch-action: manipulation 防双击缩放，iOS zoomEnabled: false；输入字号至少 16px。
- 设置中的行情 API 入口：Yahoo 收盘价、Finnhub 最新价、自定义 HTTPS JSON；可测试连接，设置密钥及 60 秒 / 5 分钟 / 关闭定时刷新。
- 最新报价只用于当前估值，实际时间可见，接口失败保留当前会话的旧报价；同日手动报价优先。
- 盘中报价在内存，API 设置在独立 Preferences 键；不进入交易备份，不污染收盘收益历史。
- 每日收益日历与累计收盘曲线仍使用 Yahoo 完成日线；此版本未提供历史行情供应商切换。

## 原有功能与数据约定
- 买卖交易、平均成本、已实现及浮动收益、编辑删除、手动报价、示例模式。
- 每日收益、三个月历史尝试补齐、缺失数据标记、本机恢复记录（5 份 / 8 MB）。
- 用户旧版已有真实数据，不能清空。保持原应用身份、存储键、交易格式和核心 version: 1。
- 继续兼容 .json / .js 文件名的 JSON 备份。完整备份包含历史；通用备份保留交易、报价、备注；旧版再次导出不保留新历史字段。
- API 配置和密钥不进入备份；换设备需重新填写。密钥保存在本机 Preferences，并非加密保险库。
- 升级先导出完整备份，原签名账号覆盖安装，不先卸载旧版。

## 验证与发布
- 59 项单元测试、8 项浏览器流程通过；生产构建和原生资源同步通过。
- 402 × 874 手机尺寸浏览器检查通过；真实 API Key 的服务权限未测试。
- 云端构建：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35043696558
- IPA 源码：83377bb0397988e6904369f3abad1792b153ff7a。
- 已验证 ARM64 / iPhoneOS、1.21.0 / build 4、应用标识、缩放配置、内置网页与本地构建完全一致。
- IPA 551077 字节；SHA-256 c753104f3016ab02e4e7b0f3dfff6ef29dc4993d4a92887fd13f341d9b971ae7。
- Release 已发布 IPA、校验文件、升级说明，公开附件摘要已核对。
- 尚未在用户 iPhone 17 / iOS 27 验证手势、键盘、安全区、分享与覆盖安装。界面为 WebView CSS 玻璃样式，不是 SwiftUI 原生 Liquid Glass，也不读取系统玻璃强度设置。

## 主要文件
- src/main.ts、src/style.css：界面及交互。
- src/quote-api.ts：最新报价、自定义接口、独立 API 设置。
- src/market.ts：Yahoo 收盘历史。
- src/ledger.ts、src/history.ts、src/storage.ts：账本、历史收益、持久化与恢复。
- API-SETTINGS.md：接口协议和配置边界。
- DATA-COMPATIBILITY.md、DAILY-RETURNS.md、STATUS.md、CHANGELOG.md、releases/：兼容、计算、验证与版本记录。

## 后续建议
优先根据真机覆盖安装反馈核对缩放、键盘和 API 连通性。新功能仍需维护旧账本兼容；每次更新同步代码、测试、文档和正式安装包到 GitHub。
