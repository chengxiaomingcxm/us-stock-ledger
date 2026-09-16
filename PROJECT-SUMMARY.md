# 美股持仓账本｜项目摘要

更新：2026-09-16。当前界面版本 **1.22**，内部版本 **1.22.0（build 5）**。

## 仓库与文件
- GitHub：https://github.com/chengxiaomingcxm/us-stock-ledger
- 正式下载：https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.22.0
- 本地工程：C:/Users/PC/Desktop/New folder (2)/stock-ledger
- Git 跟踪副本：C:/Users/PC/Desktop/New folder (2)/stock-ledger-github
- 本地安装包：stock-ledger/delivery/1.22.0/StockLedger-1.22.0-unsigned.ipa
- 技术：TypeScript、Vite、Capacitor；最低 iOS 16；应用标识 com.personal.stockledger。

## 1.22 已完成
- 按用户参考图将首页改为浅灰背景、白色圆角收益卡片、蓝色操作控件和紧凑持仓列表。
- 底栏顺序为持仓、交易、记一笔、收益、设置；中央记账按钮在各页可用，已移除顶部和持仓标题旁的重复入口。
- 首页大号区域显示持有收益（浮动收益），不是今日涨跌；配套显示持仓市值、成本及收益概览。
- 首页只留一行行情状态，点开查看具体失败原因；长篇说明统一收进设置 → 帮助文档，可离线查看。
- 新增首页/持仓详情金额隐藏、全部/盈利/亏损/待报价筛选、代码/市值/收益排序和持仓详情弹窗。
- 保留 1.21 的双击缩放防护、玻璃底栏、API 配置、盘中估值与历史收益隔离。

## 数据与行情约定
- 用户已有真实账本，不能清空。保持应用身份、原存储键、核心 version: 1 和交易格式稳定。
- 保留买卖、成本、已实现与浮动收益、编辑删除、手动报价、示例模式、收益日历和本机恢复记录。
- 完整备份含历史行情；通用备份只含交易、报价与备注；继续兼容 .json / .js 文件名的 JSON 备份。
- 最新报价可选 Finnhub 或符合标准协议的自定义 HTTPS API；密钥保存在独立 Preferences，不进入备份，非加密保险库。
- 盘中价仅在当前会话内用于估值，失败保留本次会话旧价，重启重新请求；同日手动报价优先。
- 每日收益、收盘曲线及交易日历仍使用 Yahoo 已完成日线，API 设置不切换历史供应商。
- 金额隐藏、筛选和排序只影响显示，不改账本；隐藏仅作用于首页与持仓详情，交易和收益页仍显示金额。
- 升级前导出完整备份，用原签名账号及应用身份覆盖安装，不先卸载旧版。

## 验证与发布
- 59 项单元测试、11 项浏览器流程通过；生产构建和原生资源同步通过。
- 320 / 402 / 430 / 1280 像素宽度无横向溢出；中央按钮至少 44px，几何居中，各页面点击可用。
- 云端构建：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35062418368
- IPA 源码：55ae76a00d8be417151575389552928ebe88b938。
- 已验证 ARM64 / iPhoneOS、1.22.0 / build 5、原应用标识与缩放配置，内置网页与本地测试构建完全一致，包含中央按钮和离线帮助。
- IPA 555772 字节；SHA-256 588ce0f688674e05a32cef5a6cac952d569a435a672dc6ed822cac4400ebe14a。
- Release 已发布 IPA、校验文件和升级说明，公开附件摘要与版本标签已核对。
- 发布流程：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35062629682
- 尚未在用户 iPhone 17 / iOS 27 真机验证手势、键盘、安全区、分享及覆盖安装。玻璃风格为 WebView CSS 实现，不是 SwiftUI 原生 Liquid Glass。

## 主要文件
- src/main.ts、src/style.css、src/home.css：首页、导航和交互。
- src/help.ts、HELP.md：应用内离线帮助和 GitHub 帮助文档。
- src/quote-api.ts、API-SETTINGS.md：最新报价、接口设置与协议。
- src/market.ts：Yahoo 收盘历史。
- src/ledger.ts、src/history.ts、src/storage.ts：账本、历史收益、存储与恢复。
- DATA-COMPATIBILITY.md、DAILY-RETURNS.md、STATUS.md、CHANGELOG.md、releases/：兼容、计算和发布记录。

## 后续
优先收集本次真机覆盖安装与页面体验反馈。保持原账本兼容，后续更新继续同步代码、测试、文档及正式安装包到 GitHub。
