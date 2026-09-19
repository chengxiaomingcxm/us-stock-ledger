# Portfolio Polish — 最终验收与 Feature Freeze

> 依据：任务书 §28（最终验收标准）、§29（Feature Freeze）、§30（执行要求）、§31（Git 工作流）、§32（AI Code Review）、§33（本轮最终目标）。
> 原则：每条结论都要能指向可复核的证据；**尚未验证的不写「已验证」**。

## §28 最终验收标准

### Product

| 要求 | 状态 | 证据 / 说明 |
| --- | --- | --- |
| 应用可以正常启动 | ⏳ 待真机确认 | CI 在模拟器上真实启动了 App（`Render English UI screenshots` 会 launch 6 次并断言非空），但不是真机 |
| 原有核心功能正常 | ✅ | 148 单元 + 362 原生断言 + 26 端到端用例全绿（run `35449140805` / `35449140797`） |
| Demo Mode 正常 | ✅ | 原生套件含 `DemoModeTests`；截图链路用示例账本渲染全部 6 屏并断言 `days=169 months=9` 非零 |
| Demo 不污染真实数据 | ✅ | 示例使用独立派生状态，不写 `ledger-v2.json`；原生套件断言账本文件未被改动 |
| 无明显 Crash | ⏳ 待真机确认 | 模拟器 6 次启动均存活到截图（`HARNESS alive+3s`），真机仍需你实测 |
| 无明显 UI Bug | ✅（有守卫） | 320 / 402 / 430px 无横向溢出断言；截图必须非空白 |

> 「待真机确认」的两项正是本轮索要 1.0.1 IPA 的原因；真机测完请把结果补进本表。

### Engineering

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| Unit Tests Pass | ✅ | Vitest 148 passed（13 文件），本地与 CI 一致 |
| E2E Tests Pass | ✅ | Playwright 26 passed（本地 44.0s；ubuntu-latest 12.0s） |
| Build Pass | ✅ | `tsc --noEmit && vite build`；macOS 侧 `xcodebuild` 未签名 IPA 构建成功 |
| CI Pass | ✅ | `checks` 与 `build-ios` 在 `d400111` 双绿；版本号改动后 `8ee1fb9` 再次触发 |
| 不存在新增 Secret | ✅ | 全历史 secret 扫描无命中（私钥块、`ghp_` / `github_pat_`、AWS key id、JWT、Slack token、`sk-`；凭据类文件名）。`secrets*.txt` 从未进入 git 历史 |
| 不存在 Debug Data 泄漏 | ✅ | 临时文件全部落在已忽略的 `.scratch/`；质量门禁会拦「被跟踪的构建产物」与「会进提交的散落调试文件」；API Key 只在钥匙串且不进备份 |

### Portfolio

「第一次打开 GitHub 的人能在 30 秒内理解」——逐条对应到 README 的哪一节：

| §28 要求 | 在哪回答 |
| --- | --- |
| 1. 这是什么软件 | 标题 + §12 给定的一句介绍 + Hero 截图（首屏） |
| 2. 解决什么问题 | `## Features` 开头的五个问题式要点 |
| 3. 有哪些核心功能 | `## Features` 的条目清单 |
| 4. 软件长什么样 | Hero 截图 + `## Screenshots` 六张（含 Import） |
| 5. 使用什么技术 | `## Tech Stack` 表 |
| 6. 如何测试 | `## Testing`（三套件规模 + CI 命令 + 耗时） |
| 7. 如何运行 | `## Getting Started`（真机安装 + 源码运行），细节在 `docs/DEVELOPMENT.md` |

补充：`## Architecture` 含 Mermaid 图；`## Data & Privacy`、`## Limitations`、`## Roadmap`、`## Disclaimer`、`## License` 均在首屏下不远处可见。

## §29 Feature Freeze

本轮（Portfolio Polish）交付完成后进入 **FEATURE FREEZE**。

**之后只接受：**

- Critical Bug / Security Fix / Data Integrity Fix / Compatibility Fix
- 小范围 UX 改善
- 文档改进、测试改进

**原则上拒绝：**

- 大型新功能、架构重写
- 新的交易类产品能力（期权、做空、券商自动下单）
- AI 投资功能、券商自动化

理由：§33 的目标是「让陌生人确认这是一个完整的软件工程项目」，而不是把产品做成券商 App。功能继续膨胀会稀释这个目标，也会让已有测试矩阵失去意义。

## §30 执行要求对照

「不要一次性改整个仓库，严格分阶段」——本轮的实际情况：

| Phase | 分支 | 产物 | CI |
| --- | --- | --- | --- |
| 0 审计 | `portfolio/audit` | `docs/PORTFOLIO_AUDIT.md`（P0×3 / P1×12 / P2×11 / P3×7） | — |
| 0.5 核心安全 | `portfolio/core-safety` | `docs/PHASE_0_5_REVIEW.md` | ✅ |
| 1 Demo Mode | `portfolio/demo-mode` | `docs/PHASE_1_REVIEW.md` + `DemoData.swift` + `DemoModeTests` | ✅ |
| 2 截图与展示 | `portfolio/screenshots` | `docs/PHASE_2_REVIEW.md` + 渲染守卫 | ✅ |
| 3 错误处理 | `portfolio/error-handling` | `docs/PHASE_3_REVIEW.md` + 61 条英文文案 | ✅ |
| 4 测试覆盖 | `portfolio/error-handling` | `docs/PHASE_4_REVIEW.md` + `CsvImportTests` / `ErrorPathTests` | ✅ |
| 5 CI | `portfolio/error-handling` | `docs/PHASE_5_REVIEW.md` + `checks.yml` | ✅ |
| 6 README / 文档 | `portfolio/readme` | `docs/PHASE_6_REVIEW.md` + 三份 docs + LICENSE | ✅ |
| 发布准备 | `portfolio/readme` | 1.0.1 / build 6 + `releases/v1.0.1.*` | ✅ |

每个 Phase 都单独提交、单独跑门禁、单独出复核文档；没有一次跨阶段大改动。

**偏离一处**：§30 建议的 Phase 划分是「Phase 2 = UI / Error Handling」「Phase 3 = Testing / CI」，本轮把它拆成了 2 / 3 / 4 / 5 四个更小的阶段（截图 → 错误处理 → 测试 → CI）。理由是每个阶段的验证手段不同（渲染守卫 / 文案扫描 / 覆盖率 / 工作流），合在一起会让「测试结果」无法归因。

## §31 Git 工作流

- 每个 Phase 独立分支，命名 `portfolio/*`；**`main` 全程未被直接修改**（`git log main` 不含本轮任何提交）。
- 分支按任务书建议使用；`portfolio/readme` 同时承载 §16/§18/§25 的文档（任务书里叫 `portfolio/documentation` 与 `portfolio/case-study`），合并为一个阶段执行。
- 每个 Phase 完成后：本地门禁 → commit → push → 等远端 CI 绿 → 出复核文档。**没有以「CI 已启动」当作完成**。
- 变更不直接进 `main`：按你的流程，由 Codex 审查后再由你手动同步。

## §32 AI Code Review

**当前状态：等待 Codex 审查。** 本轮已交付的内容在 `portfolio/readme`（tip `8ee1fb9`）。

建议 Review 重点（§32 给定）：Regression / Data Integrity / Calculation Error / Security / Privacy / Error Handling / Code Duplication / Unnecessary Complexity / Dead Code / Test Coverage。

需要特别复核的三处，因为它们改了行为而不只是文案：

1. `src/v126.css` 的 `.cash-totals` 从 `1fr` 改为 `minmax(0,1fr)`——请确认宽屏下列宽与视觉未变（本地实测 360/402px 与修改前一致 141/162px）。
2. `e2e/preferences.spec.ts` 的溢出断言改成返回越界元素描述——**判定口径未变**（仍是 `scrollWidth <= innerWidth`），确认不是放宽断言。
3. 示例模式的隔离（Phase 1）——确认它确实不写 `ledger-v2.json`。

若 Review 建议「重构整个项目」，按 §32 默认拒绝，除非有明确收益与明确问题。

## 更新提醒：CI 产物有效期

`build-ios.yml` 的产物设置是 `retention-days: 14`，而 `scripts/publish-release.py` 需要**从 Actions 下载该产物**才能发布。因此：**1.0.1 的审查与 `main` 同步建议在 14 天内完成**，否则产物过期、发布脚本会取不到包（届时重新 push 触发一次构建即可，manifest 里的 `run_id` 与 `sha256` 需同步更新）。

## 尚未完成 / 明确不在本轮交付

诚实列出，避免把「计划」写成「已完成」：

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 真机验收（§28 Product 两项） | ⏳ 待你实测 | 已提供 1.0.1 的未签名 IPA 与安装步骤 |
| 正式 Release（§24） | ⏳ 待 Codex 审查后同步 `main` | `releases/v1.0.1.json` 清单已就绪；`publish-release.yml` 只在 `main` 上触发，届时自动发布，无需手工重建 |
| 演示视频（§14） | ⏳ 未录制 | README 只预留了位置；视频本体属于素材制作，不是仓库代码 |
| Codex 代码审查（§32） | ⏳ 等待中 | 见上节「需要特别复核的三处」 |
| 13 天后再看 CI 产物 | ⚠️ 提醒 | 产物 14 天后过期；若发现过期，重新 push 触发一次构建并更新 manifest 的 `run_id` 与 `sha256` |

## §33 本轮最终目标

> 让一个完全不了解开发者的人打开 GitHub Repository 后，在几分钟内确认：这个开发者能够从需求出发，完成一个具有真实业务逻辑、数据处理、API 集成、测试、UI 和发布流程的软件项目。

对应到本轮的可见产出：真实业务逻辑（成本/收益/现金口径与不变式）、数据处理（CSV 与 PDF 导入 + 校验 + 预览）、API 集成（三家行情源 + 归一化 + 降级）、UI（SwiftUI 四页 + 图表 + 日历 + 无障碍）、测试（四层，362/148/26）、发布流程（双 workflow + 校验式发布脚本 + 带校验和的未签名 IPA）。

达到该目标后：**停止继续开发新功能**（见 §29）。下一步资源投入：Portfolio → Freelance Platform → Client Acquisition → First Paid Project。
