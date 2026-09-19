# Phase 4 — Test Coverage · Review

> 基线：`portfolio/error-handling`（Phase 3 之后）。
> 范围：任务书 §9 Phase 4（§10 的 Demo Mode 测试在 Phase 1 已完成，见 `docs/PHASE_1_REVIEW.md`）。

## §9 逐条对照

原则先说清：§9 明确「不要为了追求 Coverage Percentage 大量编写没有意义的测试」。所以这一轮只补**真实缺口**，已经覆盖的不重写。

| §9 要求 | 现状 | 位置 |
| --- | --- | --- |
| Portfolio Calculation：Average Cost / Realized / Unrealized / Fees / Taxes / Dividends | ✅ 已覆盖（Phase 0.5） | `tests/native/EngineGoldenTests.swift`（14 组金标准，期望值全部人工推导后写成字面量） |
| Transactions：Buy / Sell / Partial Sell / Full Sell | ✅ 已覆盖（Phase 0.5） | 同上（多笔买入 / 部分卖出 / 全部卖出 / 缺行情） |
| Cash Flow：Deposit / Withdrawal | ✅ 已覆盖（Phase 0.5） | 同上（`Engine.cashTotals` 组：分红、税费、出入金、现金流隔离） |
| Import：Valid / Invalid / Missing Fields / Duplicate | ❌ **原生侧原本没有** → 本轮补齐 | `tests/native/CsvImportTests.swift`（新增） |
| PDF Import：条件句「如果当前适合自动化测试，则增加相应测试」 | ✅ 已适合且已覆盖 | `tests/native/NativeTests.swift` 里的 HSBC 段：运行时用 CoreGraphics 生成 PDF → PDFKit 提取 → 解析；含乱序内容流、HKD 排除、只读预览、批量导入、未知预扣税、银行四舍五入、重复识别、过期预览拒绝，以及约 10 条 `rejects`（空文件 / 错银行 / 坏日期 / 坏金额 / 缺参考号 / 交收额不符 / 未知收入 / 税行不支持 / 缺买入） |

### 为什么 CSV 导入必须**在原生侧**再测一遍

`tests/csv-import.test.ts` 已有 23 个用例，但它测的是 **Web 引擎**（`src/*.ts`）。审计 (`docs/PORTFOLIO_AUDIT.md`) 已确认：原生与 Web 是**两套独立实现**，共享的只有概念口径、不是代码 —— Web 的用例证明不了 Swift 这一侧。所以 §9 的 Import 四类在原生侧是真实空白。

## 新增测试

### `tests/native/CsvImportTests.swift`

| 组 | 断言要点 |
| --- | --- |
| 合法 CSV | 8 列识别、两行进入预览、状态为可导入且默认勾选、整批校验通过、行号为真实文件行号、七个字段逐一取值正确；`detectMode` 能区分成交明细与资金流水 |
| 缺字段 | 行内缺代码 → 该行「无法导入」且带可读原因、不带交易、不影响同文件其它行；**整列缺失 → 整批拒绝**（不把空值当 0 写进去） |
| 非法 CSV | 空文件 / 只有表头 / 无法识别的编码 → 抛错；数量非数字、日期晚于今天 → 变成「无法导入」的行（而不是终止预览） |
| 重复数据 | ① 成交编号已在账本 → 已导入且默认不勾选；② 六项签名全同 → 疑似重复；③ 文件内重复编号 → 第二条起跳过 |
| 整批超卖 | 单行合法但与账本叠加后超卖 → 整批拒绝并给出说明；卖满持仓不算超卖 |
| 错误文案 | 英文模式下可翻译；带 `{}` 占位的整句不再是中文；中文模式原样返回 |

### `tests/native/ErrorPathTests.swift`

Phase 3 改动的直接守卫：注入一个必失败的 `persist` → 保存返回 false、内存账本不变、`errorMessage` 等于**可读文案**（不是系统异常原文），且诊断日志里留下 `SAVE` 与异常类型。

两个文件都已登记进 `NativeTests.main()` 与 `scripts/test-native.sh`（漏登记会「假绿」，见 `AGENTS.md`）。

## 过程记录：两次 CI 红与本地检查器

这一轮的两个新文件连续两次把 CI 弄红，都是**同一类错误**，也都暴露了「本机没有 Swift 工具链 → 只能靠 CI 编译」这个约束下的自检不足：

| run | 错误 | 根因 |
| --- | --- | --- |
| `35442564945` | `CsvImportTests.swift:24-29` | `run()` 调用会 `throws` 的私有辅助函数漏写 `try` |
| `35443500817` | 同文件 `:29`（`messages()`）+ `:101` | 第一次只补了前五个、漏了第六个；另外把会抛的 `CsvImport.decode` 塞进了 `NativeTests.check(...)` —— 它的参数是**非抛出的 `@autoclosure`** |

补救（提交 `c4fb28c`、`96101c5`）：补 `try`、把会抛的调用先取出来再断言，并新增本地检查器 `.scratch/check-swift-throws.mjs`：

- 同文件内声明为 `throws` 的函数，调用点必须带 `try`（跨文件只按名字比对会误报，因为 `amount`/`save`/`date` 这类同名方法遍地都是）；
- `check(...)` 里不许有裸 `try`，也不许调用任何会抛的函数（跨文件比对，只在这一条生效）。

它现在报 `OK throws 对齐检查通过（26 个文件）`，而这两条规则正好覆盖上述两次红。已写进仓库记忆的推送前预检清单。

## 未做

- **不追求覆盖率数字**：没有为凑百分比补测试；`Engine` 的边界组合（拆股、多币种、极大账本）仍由既有金标准与 CI 的大历史用例覆盖。
- **UI 层测试**：`SettingsView` 的导出/恢复文案契约只测到状态层（`ErrorPathTests`），视图层仍靠 Phase 2 的截图产物人工核对。
- **iOS E2E**：仍按 `docs/PHASE_1_REVIEW.md` 的豁免处理，留 Phase 5 复评。

## CI

| run | commit | 结果 |
| --- | --- | --- |
| `35442564945` | `f625594` | failure（编译错误，见上表） |
| `35443500817` | `c4fb28c` | failure（同上，漏改一处） |
| `35444435278` | `96101c5` | **success**，19/19 步，16.0 分钟 |
