# 交付状态

更新：2026-09-15

## 已完成

- 用户要求的五项功能及独立示例模式。
- 27 项账本计算、输入校验、备份和存储恢复测试通过。
- 2 项浏览器完整流程测试通过，覆盖买卖、修改重算、手动报价、导入导出和示例隔离。
- GitHub 私有仓库已建立并上传完整工程。
- 云端 Xcode 26.6 编译成功，生成 iPhone 真机 ARM64 IPA；最低 iOS 16.0。
- 下载后的外层 ZIP 校验值与 GitHub 产物摘要一致；IPA 校验值与云端输出一致。
- IPA 内容验证：真机平台、ARM64 可执行文件、应用标识、隐私文件及内置页面资源正确，不依赖开发服务器。

## 下载与签名

- 构建记录：https://github.com/chengxiaomingcxm/us-stock-ledger/actions/runs/34961045118
- 构建提交：e06032994ca92d78bd343275accb1f66cb92cb80
- 产物名称：StockLedger-unsigned-IPA
- IPA 文件：StockLedger-unsigned.ipa（未签名，需使用个人 Apple 账号签名后安装）。
- SHA-256：37bb3a0d6ff63e208123060ff940c0c30151d835a1a0062ad6977b97f1ae4415

## 待真机验证

尚未在用户 iPhone 上验证安装签名、原生持久化、系统分享与文件选择器。用户签名安装后可先使用独立示例模式检查界面，再建立正式账本。
