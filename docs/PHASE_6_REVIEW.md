# Phase 6 — README 重构 / 文档 · Review

> 基线：`portfolio/readme`（从 Phase 5 的 `portfolio/error-handling` @ `7ced65e` 切出）。
> 范围：任务书 §12（README 重构）、§13（截图）、§14（Demo Video 占位）、§16（ARCHITECTURE）、§17（架构图）、§18（DEVELOPMENT）、§19（隐私/安全 + secret 扫描）、§20（免责声明）、§21（限制）、§22（Roadmap）、§25（CASE_STUDY）、§26（Portfolio 定位）。
> 原则：文档里出现的每个数字都必须可复核；核不到的一律不写（§27 禁止虚构）。

## §12 要求的结构 vs 实际章节

| §12 要求的顺序 | README.md 实际 | README.zh-Hans.md 实际 |
| --- | --- | --- |
| 标题 + 一句英文介绍 | `# US Stock Ledger` + 给定原句 | 同名 + 中文一句介绍 |
| Hero Screenshot | `holdings.png`（`<img width="330">`） | 同 |
| Features | L13 | `## 功能` L13 |
| Screenshots | L36（6 张，两行三列） | `## 截图` L36 |
| Demo | L48（+ `### Demo video (planned)`） | `## 示例模式` L48 |
| Architecture | L56（含 Mermaid，L58-77） | `## 架构` L56 |
| Tech Stack | L118 | `## 技术栈` L118 |
| Testing | L131 | `## 测试` L131 |
| Getting Started | L169 | `## 快速开始` L169 |
| Data & Privacy | L201 | `## 数据与隐私` L201 |
| Limitations | L223 | `## 当前限制` L223 |
| Roadmap | L237 | `## Roadmap` L237 |
| License | L270 | `## 许可` L270 |

额外两节：`## Disclaimer`（§20，L264）在 License 前；`### Static checks: no ESLint, by design`（L161）保留在 Testing 下，把 §11 的偏离继续留在对外可见处。

**中文版与英文版章节顺序逐节对齐**（同一行号区间），不是各自重写一遍结构。

## §13 截图

- `docs/screenshots/` 现有 6 张：`holdings` / `trades` / `returns` / `settings` / `calendar` / `import` —— 覆盖 §13 要求的 dashboard / portfolio / transactions / calendar / performance / import。
- README 一次展示 **6 张**（在 §13 给的 4–6 张上限内），切分成两行三列，不是一长条大图。
- 与上一版的差别：**补上了 `import.png`**（上一版 README 只有 5 张，缺 Import）。
- 每张都来自模拟器真实渲染、英文界面、含真实示例数据（CI 的 `Render English UI screenshots` 步骤会断言非空白且 `HARNESS derived … days=N months=M`，N/M 均非 0）。

## §16/§17/§18/§25 文档

| 文件 | §要求 | 内容 |
| --- | --- | --- |
| `docs/ARCHITECTURE.md` | §16 System Overview / Data Flow | 两个运行时、分层表（带真实文件名）、6 条代码强制的口径不变式、三条数据流（账本写入 / 行情 / 导入）、存储格式、错误模型（用户文案 vs 本机诊断）、测试架构 |
| `README.md` 的 `## Architecture` | §17 架构图 | Mermaid `flowchart TD`，节点与 `ARCHITECTURE.md` 的分层表一一对应，没有为了画图改代码 |
| `docs/DEVELOPMENT.md` | §18 | 环境要求、Setup、安装依赖、开发构建、跑测试（含 macOS-only 脚本）、E2E、构建、质量门禁、发布、仓库约定、两个一次性脚本 |
| `docs/CASE_STUDY.md` | §25 + §26 | Problem / Goal / Solution / Key Features / Technical Challenges（11 条）/ Engineering Decisions / Testing / Privacy / Result / Lessons Learned |

## §19 隐私与安全

README 新增 `## Data & Privacy`，三段对应 §19 要求：Data Storage（数据在哪）、External APIs（什么会离开设备）、API Keys（不提交任何密钥）。

**全历史 secret 扫描**（`.scratch/secret-scan.mjs`，工具输出 `.scratch/secret-history.txt`）：

- 扫全部 `git log --all -p` 的新增行，匹配：GitHub PAT（`ghp_` / `github_pat_`）、AWS access key id、私钥块、OpenAI 风格 `sk-`、Slack token、JWT。
- 扫历史中出现过的敏感文件名（`secret` / `.env` / `credential` / `password` / `token` / `key`，排除源码后缀）。
- 单独确认已删除文件：`secrets1.txt` / `secrets2.txt` **从未进入 git 历史**（`git log --all -- <path>` 为 0 条），磁盘上也不存在。
- 工作区引用项复核：`TEST-ONLY-SECRET`（e2e 占位符）、`${{ github.token }}`（workflow 内置变量）、Keychain 常量、PDF 密码输入框文案 —— 均为良性。

**结论：工作区与全部 132 个提交中都没有真实凭据。** 未删除任何 git history（§19 明确禁止自动删历史）。

## Files Changed

| 文件 | 变化 | 说明 |
| --- | --- | --- |
| `README.md` | 重构 | 按 §12 顺序重排；补 Hero 截图、架构（含 Mermaid）、数据与隐私、限制、Roadmap、免责声明、License；补 6 张截图（新增 `import.png`） |
| `README.zh-Hans.md` | 同步重构 | 与英文版逐节对齐 |
| `LICENSE` | 新增 | MIT（用户 2026-09-19 选定） |
| `docs/ARCHITECTURE.md` | 新增 | §16 |
| `docs/DEVELOPMENT.md` | 新增 | §18 |
| `docs/CASE_STUDY.md` | 新增 | §25 / §26 |

未改动：任何产品代码、任何测试、任何依赖、`package.json`、任何 workflow。

## 与上一版 README 的事实性修正

| 位置 | 上一版 | 本版 | 依据 |
| --- | --- | --- | --- |
| 标题 | `# Stock Ledger` | `# US Stock Ledger` | §12 要求的结构 |
| 介绍句 | 自述式（"A personal US-stock ledger for iPhone…"） | §12 给定的原句 | §12 |
| 测试数 | `Vitest (148) + native Swift tests + …`（无原生断言数） | 补 **362 assertions** 与 **25,000 closes / 4,000 sessions / 1,000 trades** | CI 日志 `PASS: 362 assertions; 25,000 closes / 4,000 sessions / 1,000 trades: 0.252s` |
| 免责声明 | 无 | §20 原文 blockquote | §20 |
| License | 无 | MIT + `LICENSE` 文件 | 用户选定 |
| 截图 | 5 张，无 Import | 6 张，含 Import | §13 |
| Demo Video | 无 | `### Demo video (planned)` 占位 | §14 |

**修掉的两处不准确表述（自检时发现）**：

1. 初稿在 `docs/ARCHITECTURE.md` 与 `docs/CASE_STUDY.md` 里写了账本"有 schema version、可在载入时迁移"。核对代码后确认：`Models.swift` **没有** `version` / `schema` 字段，`Store.swift:4` 的注释说明原生 1.0 是**继续沿用** `ledger-v2.json`，而 L10n 明确写着旧 Web 版 1.26 及更早**不自动迁移**。已改为「文件名承载格式代际 + 原生版刻意沿用 2.0 测试版文件、不自动迁移旧 Web 格式」。
2. 分层表里曾写 `LedgerDerived` 是 `revision` 比对复用但暗示 `revision` 属于 `Ledger`；实际 `revision` 是 `LedgerDerived` 自身的 `UUID`（`Engine.swift:519`），视图用 `data.revision` 决定是否重绘（`InsightsView.swift:317/530`）。已改为不指定归属的表述。

## 验证

- `scripts/verify.ps1` → **QUALITY GATE PASSED**（`pnpm test` 148 项、`tsc --noEmit && vite build`）；commit 时 pre-commit hook 又跑了一遍，同样 PASSED。
- 本轮只改 `.md` 与 `LICENSE`：产品代码与测试零改动，Vitest 148 / 原生 362 / Playwright 26 的既有结论不受影响。
- 提交前核对 `git status --porcelain`：暂存区恰好是本表 6 个文件，任务书 `.md` 仍为未跟踪（按要求不提交、不删改）。
- 推送后远端确认：`git ls-remote origin refs/heads/portfolio/readme` = `d400111`（与本机一致）。

## Regression Risk

| 风险 | 评估 |
| --- | --- |
| 文档与代码不一致 | 中低。已用代码/CI 日志逐条核对；主动删掉了两处核不到的表述。剩余风险是细节描述随代码演进而过期——这也是把 `docs/` 纳入版本控制的原因 |
| README 图片路径失效 | 低。6 张图均在 `docs/screenshots/` 内且已跟踪，路径为相对路径，GitHub 与本地渲染一致 |
| 新增 `LICENSE` 改变仓库授权状态 | **有意为之**（用户选定 MIT）。注意：MIT 允许他人自由使用/修改/分发本项目源码 |
| 加了非 `.md` 文件导致本轮触发 CI | 预期内：`LICENSE` 不在两个 workflow 的 `paths-ignore` 里，所以本次 push 会跑 `checks` 与 `build-ios`。这是有意让该分支自己也有一条绿记录 |

## CI 记录

| run | commit | 工作流 | 结果 |
| --- | --- | --- | --- |
| 35449140805 | `d400111` | Checks | ✅ 59 秒（14:34:14Z → 14:35:13Z）：`pnpm test` **148 passed**（13 文件）→ `pnpm build` → `pnpm e2e` **26 passed (12.0s)** |
| 35449140797 | `d400111` | Build unsigned iOS IPA | ✅ 约 18 分钟（14:34:14Z → 14:52:01Z）：15 步全过，含原生 `swiftc` 套件（362 断言）、模拟器日历渲染、6 张截图渲染与未签名 IPA 上传 |

两次都是本分支自己的 run（`headBranch=portfolio/readme`），不是从 `portfolio/error-handling` 继承的旧记录。

## 尚未完成 / 不在本轮范围

按 §30「每个 Phase 完成后不要自动进入下一 Phase」，以下留给后续确认，本轮未做：

- §23 GitHub Repository Description 与 Topics —— 需要在 GitHub 仓库设置里改，不是仓库文件。建议值：description 用 §23 给的那句；topics 建议 `portfolio` / `stocks` / `investment-tracker` / `swiftui` / `ios` / `finance` / `portfolio-tracker` / `open-source`。
- §24 正式 Release（v1.x.x）—— 需要版本号决策与真实云端构建产物，且 `AGENTS.md` 禁止擅自改版本号/tag/Release。
- §14 演示视频本体 —— 只按 §14 预留了 README 位置。
- §11 之外的 §28–§33 验收与 Feature Freeze 宣布。
