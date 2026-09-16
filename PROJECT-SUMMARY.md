# 美股持仓账本｜项目摘要

更新：2026-09-16。当前界面版本 **1.23**，内部版本 **1.23.0（build 6）**。

## 仓库与文件
- GitHub：https://github.com/chengxiaomingcxm/us-stock-ledger
- 正式下载：https://github.com/chengxiaomingcxm/us-stock-ledger/releases/tag/v1.23.0
- 本地工程：C:/Users/PC/Desktop/New folder (2)/stock-ledger
- Git 跟踪副本：C:/Users/PC/Desktop/New folder (2)/stock-ledger-github
- 本地安装包：stock-ledger/delivery/1.23.0/StockLedger-1.23.0-unsigned.ipa
- 技术：TypeScript、Vite、Capacitor；最低 iOS 16；应用标识 com.personal.stockledger。

## 1.23 已完成
- 设置新增「显示与提醒」：外观跟随系统 / 浅色 / 深色、涨跌颜色绿涨红跌 / 红涨绿跌、备份提醒每 7 天 / 每 30 天 / 关闭；偏好保存在本机并重启保留。
- 行情 API 密钥在 iOS 上改存系统钥匙串（本地 Swift 插件 LedgerSecretsPlugin），旧值首次使用自动迁移，写入先校验再清理旧位置；浏览器端继续用 Preferences。
- 交易表单新增一半 / 全部快捷卖出、最近股票代码下拉、手续费默认沿用上一笔；保存后可撤销刚新增的交易；首页在需要备份时显示提醒条。
- 保留 1.22 的卡片首页、金额隐藏、筛选排序、持仓详情、离线帮助、玻璃底栏与双击缩放防护。

## 数据与行情约定
- 用户已有真实账本，不能清空。保持应用身份、原存储键、核心 version: 1 和交易格式稳定。
- 保留买卖、成本、已实现与浮动收益、编辑删除、手动报价、示例模式、收益日历和本机恢复记录。
- 完整备份含历史行情；通用备份只含交易、报价与备注；继续兼容 .json / .js 文件名的 JSON 备份。
- 最新报价可选 Finnhub 或符合标准协议的自定义 HTTPS API；密钥在 iOS 上保存在系统钥匙串，在浏览器端保存在 Preferences，都不进入备份。
- 盘中价仅在当前会话内用于估值，失败保留本次会话旧价，重启重新请求；同日手动报价优先。
- 每日收益、收盘曲线及交易日历仍使用 Yahoo 已完成日线，API 设置不切换历史供应商。
- 金额隐藏、筛选和排序只影响显示，不改账本；隐藏仅作用于首页与持仓详情，交易和收益页仍显示金额。
- 升级前导出完整备份，用原签名账号及应用身份覆盖安装，不先卸载旧版。

## 验证与发布
- 65 项单元测试、13 项浏览器流程通过；生产构建和原生资源同步通过。
- 320 / 402 / 430 像素宽度、深浅色各页无横向溢出；中央按钮至少 44px，交易流程与偏好重启保留均通过浏览器验证。
- 云端构建：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/35073759877
- IPA 源码：fceca08461a1dc2cc7f3d5045d0f8d44cdf88ff0。
- 已验证 iPhoneOS / ARM64、1.23.0 / build 6、com.personal.stockledger；钥匙串插件随原生工程编译通过。
- IPA 567506 字节；SHA-256 2afcdd83d24484d728bfc319d03130d796b358917c86cd78f412d0ba166b3078。
- Release 说明与升级文档已准备，待发布流程核对后公开 IPA、校验文件和升级说明。
- 尚未在用户 iPhone 17 / iOS 27 真机验证手势、键盘、安全区、分享、外观切换与钥匙串迁移。

## 主要文件
- src/main.ts、src/style.css、src/home.css：首页、导航和交互。
- src/help.ts、HELP.md：应用内离线帮助和 GitHub 帮助文档。
- src/quote-api.ts、API-SETTINGS.md：最新报价、接口设置与协议。
- src/preferences.ts、src/secure-settings.ts、src/appearance.css：外观偏好、iOS 钥匙串与主题样式。
- src/market.ts：Yahoo 收盘历史。
- src/ledger.ts、src/history.ts、src/storage.ts：账本、历史收益、存储与恢复。
- DATA-COMPATIBILITY.md、DAILY-RETURNS.md、STATUS.md、CHANGELOG.md、releases/：兼容、计算和发布记录。

## 后续
优先在真机确认覆盖安装、外观切换与钥匙串迁移。保持原账本兼容，后续更新继续同步代码、测试、文档及正式安装包到 GitHub。
