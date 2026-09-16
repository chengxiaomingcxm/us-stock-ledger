# 行情来源与 API 设置

点首页或收益页的「行情状态 → 更换行情来源」，选择来源、测试连接后保存。无需重装。

| 来源 | 配置 | 用途 |
| --- | --- | --- |
| Yahoo Finance（默认） | 无需密钥 | 已完成交易日收盘价；延续旧版本行为 |
| Finnhub | 自己申请的 API Key | 最新报价；实际延迟与权限由供应商决定 |
| 自定义 API | HTTPS URL，包含 `{symbol}`；可选 Bearer Key | 返回下述标准 JSON 的服务或适配网关 |

Finnhub 请求固定发送至 `https://finnhub.io/api/v1/quote?symbol=AAPL`，密钥通过 `X-Finnhub-Token` 请求头传递。依据 [官方 API](https://finnhub.io/docs/api/quote)，读取 `c` 当前价和 `t` Unix 秒时间。没有内置共享密钥，也没有保证免费账户的延迟或权限。

自定义地址示例：`https://your-service.example/quote?symbol={symbol}`。

```json
{
  "symbol": "AAPL",
  "currency": "USD",
  "price": "230.50",
  "timestamp": "2026-09-16T14:30:00Z"
}
```

- GET 请求，必须返回 HTTP 200 和 JSON 对象。时间使用 ISO 8601 并携带时区；价格为正数或数字字符串。股票代码必须匹配请求，币种为 USD。
- 密钥为空时不发送 Authorization；填写后发送 `Authorization: Bearer <key>`。切换供应商会清空表单中的密钥，请重新填写。
- 任意第三方 API 不一定直接返回此结构；需由服务端适配到上述协议。只有 URL 可更换，不代表自动识别所有供应商响应。
- 测试连接使用 AAPL，不改变账本。错误提示不会回显请求地址、密钥或供应商的原始错误正文。
- 网页测试需接口支持 CORS。安装后的 iOS 使用 Capacitor 原生 HTTP。只支持 HTTPS，不降低系统证书校验。

## 刷新与数据边界

最新报价可设每 60 秒、每 5 分钟，或关闭定时刷新。仅在前台刷新，打开/返回前台会检查，另可点「更新收益」。最多两个并发请求；同一批不会重叠。接口限流时可延长间隔。刷新间隔不代表供应商数据本身的更新速度。

页面显示各股票实际报价日期和设备本地时间；超过 15 分钟标为「较早报价」，休市期间较早报价属正常情况。过时的响应不会倒退当前会话中的报价时间。同日手动报价及日期较新的已保存报价优先。

盘中价只用于当前估值，保存在当前运行会话内存中；本次请求失败保留上次报价，重启后重新获取。尚无盘中价时使用已保存的手动/收盘报价，并显示对应来源。每日收益、收盘曲线与历史日历仍使用 Yahoo 收盘历史，不能通过此入口更换历史数据供应商。

API 配置与交易账本分开保存。密钥在 iPhone 上保存在系统钥匙串，在浏览器预览时保存在本机 Preferences；两者都不进入账本备份、GitHub 源码或日志。导入旧备份不改变 API 设置；换设备后需重新填写。应用不会发送交易数量、成交金额或备注给行情服务。

## 界面与验证边界

1.21 参考 [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials) 和 [Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)：玻璃效果集中于导航与控件，财务内容使用清晰的实体背景，支持减少动态效果、减少透明度及提高对比度的媒体查询。

项目仍是 Capacitor + WebView，使用 CSS 模拟液态玻璃样式，不是 SwiftUI 原生 Liquid Glass 材质，也不声称读取 iOS 27 系统的玻璃强度设置。原生配置关闭页面缩放，CSS 禁用双击缩放，输入控件保持 16px；系统辅助功能缩放不由应用关闭。

已进行自动化测试和手机尺寸浏览器检查；iPhone 17 / iOS 27 的真机手势、键盘、安全区及原生分享仍需覆盖安装后确认。
