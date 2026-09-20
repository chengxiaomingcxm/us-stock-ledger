# Phase 3 — Error Handling · Review

> 基线：`portfolio/screenshots` @ `334878d`（Phase 2 收尾 + CI 自动触发）。
> 本阶段分支：`portfolio/error-handling`。**未触碰 `main`**。
> 范围：任务书 §8 Phase 3。

## §8 审计：四类关键流程

§8 要求审计 Data Import / Market Data / Backup / Storage 四条链路，并保证「不得把 `Unhandled Exception` 直接展示给最终用户」，用户可见文案要可读，同时开发环境保留详细日志（`Diagnostics.swift` 已存在）。

审计方式：把应用里所有 `errorMessage` / `error` 赋值点与 `throw` 点列出来，逐个确认「用户看到什么、日志里留了什么」。原始清单（`grep -n "errorMessage = |localizedDescription"`）共 24 处。

| 链路 | 失败路径 | 修复前的行为 | 判定 |
| --- | --- | --- | --- |
| Storage | 账本文件读不出来 | `.failed(reason)` 只用于 `loadFailure != nil` 与日志；界面显示 `LedgerStore.unreadableMessage`（可读 + 给出恢复入口） | ✅ 已达标（Phase 0.5 的成果） |
| Storage | 保存失败（`commit` / `commitRefresh`） | `errorMessage = error.localizedDescription` —— **系统异常原文直接进界面** | ❌ 已修 |
| Storage | 手动录入超卖 | 明确的中文文案 + 未改动账本 | ✅ 已达标（Phase 0.5） |
| Import | CSV 解析错误 | `CsvImportError.errorDescription` → `L10n.tr`，可读；但**英文模式下 4 类字段级报错是插值键**，永远查不到译文 | ❌ 已修 |
| Import | 选了非文本 / 不可读文件 | `error.localizedDescription` 原文进界面 | ❌ 已修 |
| Import | PDF 结单解析错误 | `LedgerError` 可读；**文件系统/PDFKit 原文会进界面**，且读取阶段**完全不写日志** | ❌ 已修 |
| Market Data | 429 / 401 / 403 / 无报价 | 有专门文案，错误信息**脱敏**（测试断言不含密钥） | ✅ 已达标 |
| Market Data | 其它请求错误 | `QuoteError` 可读；系统错误回退到原文 | ✅ 可读（系统网络文案本身面向用户），保留 |
| Backup | 恢复：文件不是账本备份 | 中文前缀 + `DecodingError` 原文拼接，**不写日志** | ❌ 已修 |
| Backup | 恢复：文件选择器失败 | `error.localizedDescription` 原文，**不写日志** | ❌ 已修 |
| Backup | 恢复：写盘失败 | 走 `commit` 的失败文案（见上） | ❌ 已修 |
| Backup | 导出失败 | **完全静默**：`try?` 把失败吞掉，按钮只是变灰，没有提示、没有日志（Phase 0 审计里记为 P2） | ❌ 已修 |

结论：§8 的两条硬要求里，「不复用系统异常原文」和「开发环境留详细日志」在**写入、导入、备份**链路上原本都不成立，本轮补齐。

## 修复内容

### 提交 1 — `5dad3d8` `fix(errors): keep raw system errors in the diagnostics log and show readable messages`

| 位置 | 变化 |
| --- | --- |
| `Store.swift` `commit` / `commitRefresh` | 写盘失败时：技术原文写 `Diagnostics.record("SAVE", …)`，界面统一显示「账本保存失败，磁盘上的原文件没有被改动；请重试。」 |
| `SettingsView.swift` 恢复 | 解码失败 / 选择器失败分别给可读文案，并把 `type(of:)` + 原文写 `Diagnostics.record("RESTORE", …)` |
| `SettingsView.swift` 导出 | 新增 `refreshExport()`：失败时置 `exportError`（数据分区页脚红字显示）+ 写 `Diagnostics.record("EXPORT", …)`，不再静默 |
| `StatementImport.swift` 读取阶段 | 新增 `Diagnostics.record("IMPORT", …)`；`LedgerError` 之外的系统错误不再直接进界面 |
| `ImportView.swift` | 新增 `readable(_:)`：`CsvImportError` 保留可读文案，其余系统错误只进日志、界面给通用文案 |
| `L10n.swift` | 新增 6 条错误文案（中英） |

### 提交 2 — `fix(l10n): make every error message translatable with placeholders instead of interpolation`

审计脚本（`.scratch/check-errors.mjs`）扫描全部 `LedgerError.message("…")` / `CsvImportError` / `QuoteError` 字面量，发现 **93 条错误文案里有 61 条没有英文译文**，其中 **15 处是把值插进 key**：

```swift
// 查不到译文：key 里含插入值，字典一定 miss，英文界面必然显示中文
throw CsvImportError.message("\(label)无效")
```

修复：44 条静态文案补齐英文；15 处插值键改成 `{}` 占位（`L10n.tr("{}无效", label)` 先成形，再交给单值关联的 `message(_:)`）；`HSBCStatement` / `QuoteService` 同类问题一并处理。修完 `check-errors.mjs` 报 **0 条缺译文**，并且全仓再 grep 不到「把插值写进 `L10n.tr` / `message` key」的调用点。

`{}` 占位是这个仓库既有做法（`L10n.tr("期初前有 {} 笔交易。", "3")`，见 `L10n.swift:24`），不是本轮新造的机制。

## 未做（明确留给后续）

- **英文文案的措辞复核**：本轮只保证「有译文、可翻译、不再是中文」，没有逐条打磨语气。属 §12 README/展示阶段。
- **错误 UI 的一致性**：目前恢复/导入用 alert，导出失败用页脚红字，账本读失败用顶部横幅。§8 没要求统一，本轮不动。
- **Phase 4 的测试覆盖**：本轮新增的失败路径（导出失败、恢复解码失败、保存失败的可读文案契约）**还没有原生断言**，属 §9 Phase 4；`SafetyTests` 里已有的「失败路径必须留下 `errorMessage`」契约断言仍然通过。

## 验证

- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1` → **QUALITY GATE PASSED**（`pnpm test` 148 用例、`tsc --noEmit && vite build`）。
- `node .scratch/check-l10n.mjs` → 486 词条、**无重复键**、除 1 条文档注释误报外无缺译文。
- `node .scratch/check-errors.mjs` → 错误文案字面量缺译文 **0**。
- 原生 Swift 无法在本机编译（Windows 无工具链）：改动的 `CsvImport.swift` / `HSBCStatement.swift` / `QuoteService.swift` / `L10n.swift` / `Store.swift` 都在 `scripts/test-native.sh` 的 `swiftc` 文件列表内，由 macOS CI 步骤实际编译。

## CI

| run | commit | 结果 |
| --- | --- | --- |
| `35441309443` | `5dad3d8` | 被同分支下一次 push 按 `concurrency` 取消（同 ref 只保留最后一次，取消不算失败） |
| `35441570618` | `6b59991` | **success** |

> 分支 `portfolio/error-handling` 的 push 会**自动**触发 `build-ios.yml`（本阶段起 `portfolio/**` 已加入触发条件），不需要手动 dispatch。
