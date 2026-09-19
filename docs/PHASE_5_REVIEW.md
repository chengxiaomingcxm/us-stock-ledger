# Phase 5 — GitHub Actions / CI · Review

> 基线：`portfolio/error-handling`（Phase 4 之后）。
> 范围：任务书 §11 Phase 5。
> 原则（用户 2026-09-19 明确要求）：**只复用仓库现有命令，不自行发明新的工程规范；不为满足 checklist 引入依赖。**

## §11 逐条对照

| §11 要求 | 处置 | 位置 |
| --- | --- | --- |
| 每次 **Push** 自动：安装 → Lint → 单测 → 构建 → E2E | ✅ 已有 + 本轮补齐 E2E；Lint 见下方偏离说明 | `.github/workflows/checks.yml` |
| 每次 **Pull Request** 自动跑同一套 | ✅ 本轮新增（此前 PR 完全不触发任何 CI） | 同上（`on.pull_request`） |
| 不要为了 CI 大规模修改项目 | ✅ 只加了 1 个 workflow 文件 + 1 个 npm script（`e2e`）+ 文档；没有动产品代码、没有换构建方式 | — |
| 某些平台 Build 无法在 GitHub Runner 执行时，在 README 明确说明 | ✅ README「Testing & CI」写明：iOS 只能在 macOS runner 构建，且产物未签名 | `README.md` / `README.zh-Hans.md` |

CI 实际执行的命令（**全部是仓库已有 script**，没有为 CI 另造命令）：

```sh
pnpm install --frozen-lockfile
pnpm test     # vitest run
pnpm build    # tsc --noEmit && vite build
pnpm e2e      # playwright test
```

### 为什么之前的 E2E 进不了 CI

不是配置写死 Windows 路径那么简单：`playwright.config.ts` 只在 `process.platform === 'win32'` 时用写死的 Chrome 路径，其余平台走 Playwright 自带 chromium。真正的缺口是三点：没有 npm script、CI 不安装浏览器、CI 不跑它。

**接入前先实测**（不能让一个从没跑过的套件直接进 CI）：本机 Windows 实测 `pnpm e2e` → **26 passed (50.6s)**。CI 上 `ubuntu-latest` 装 `chromium` 后跑同一命令。

## §11 与 `AGENTS.md` 的冲突与偏离

用户明确要求逐条报告，这里如实列出。

### 1. Lint：**直接冲突，按 `AGENTS.md` 处理并在 README 记录**

- §11 字面要求 CI 执行 Lint；
- 本仓库没有 ESLint、没有 eslint 配置、`package.json` 里也没有 `lint` script；
- `AGENTS.md` 明确写着「**没有配置。不要自创**」（并且禁止为了门禁变绿而降低标准、也禁止发明不存在的东西）；
- 因此：**不新增 ESLint / eslint config / lint script / 任何仅为满足 checklist 的依赖**；
- 静态检查由现有 `pnpm build` 里的 **`tsc --noEmit`**（`strict: true`，覆盖 `src/`、`tests/`、`capacitor.config.ts`）承担；
- **没有**把 type-check 改名成假的 `lint` script —— 类型检查就叫类型检查；
- 这是为了遵守 repository-level instructions 的**有意偏离**，已在 README 「Static checks: no ESLint, by design」一节写明（中英两版）。

> `tsc --noEmit` 的实际覆盖范围：`tsconfig.json` 的 `include` 是 `["src", "tests", "capacitor.config.ts"]`，**不含 `e2e/`**（Playwright 用例由 `playwright test` 自己编译执行）与 `scripts/`（shell / Python）。README 里也照此写明了覆盖边界。

### 2. PR 触发：不是冲突，是 `AGENTS.md` 的事实过期

`AGENTS.md` 原写「PR 不触发任何 CI」。§11 要求 PR 也跑检查链，于是新增 `checks.yml` 覆盖 PR —— 这是**有意变更事实**，不是与指令冲突；已在 `AGENTS.md` 的 CI 事实一节同步（PR 触发 `checks.yml`，但仍不触发 16 分钟的 `build-ios.yml`，避免每个 PR 消耗 macOS 额度）。

### 3. E2E：同样不是冲突，是事实过期

`AGENTS.md` 原写「E2E 没有 npm script、CI 不跑它」。本轮补上 `pnpm e2e` 并接入 `checks.yml` 后，该描述不再成立，已改为「`pnpm e2e` 已在 `package.json`；`checks.yml` 在 ubuntu 上用自带 chromium 跑它们；改用例时必须真的跑一遍」。

### 4. 其余 checklist 项与 `AGENTS.md` 无冲突

- 「安装依赖 / 单测 / 构建」= `AGENTS.md` 里既有的命令表，直接复用；
- 「不要大规模修改项目」与 `AGENTS.md` 的最小改动/删繁就简原则一致；
- 「无法在 runner 上执行的构建要在 README 说明」与 `AGENTS.md` 的「不得凭空描述 CI 事实」一致。

## Files Changed

| 文件 | 变化 | 说明 |
| --- | --- | --- |
| `.github/workflows/checks.yml` | 新增 | push + PR：安装 → `pnpm test` → `pnpm build` → 装 chromium → `pnpm e2e`；失败时上传 Playwright 报告（保留 7 天） |
| `package.json` | +1 script | 新增 `"e2e": "playwright test"`（`docs/PORTFOLIO_AUDIT.md` 的允许改动清单里已列 `e2e` script） |
| `README.md` / `README.zh-Hans.md` | 新增「Testing & CI」一节 + 修正过期事实 | CI 命令、iOS 只能在 macOS runner 构建且未签名、Lint 偏离的完整说明；顺带把 `Vitest (147)` 更正为 148、CI 一行补上 ubuntu 的 checks |
| `AGENTS.md` | 修正 CI 事实 | 新增 `checks.yml` 说明；「PR 不触发任何 CI」→「PR 触发 checks.yml，但不触发 build-ios.yml」；E2E 段落更新 |

未改动：`build-ios.yml` 的步骤链、任何产品代码、任何依赖。

## 验证

- **E2E 本地实测**：`pnpm e2e` → **26 passed (50.6s)**（Windows + 配置里的 Chrome 路径分支）。
- `scripts/verify.ps1` → **QUALITY GATE PASSED**（`pnpm test` 148 项、`tsc --noEmit && vite build`）。
- 本次 push 会同时触发 `checks.yml`（新工作流验证自身）与 `build-ios.yml`。

## CI 记录

| run | commit | 结果 |
| --- | --- | --- |
| 见 `git log`（`portfolio/error-handling` tip） | — | 待本轮 push 后填入 |
