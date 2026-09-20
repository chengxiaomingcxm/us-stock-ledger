# Development

> How to clone this repository and actually run it. Every command below exists in `package.json`, `scripts/` or `.github/workflows/` — nothing here is aspirational.

## Development Environment

| Piece | Version / note |
| --- | --- |
| Node | 24 (CI uses Node 24) |
| pnpm | 11 (CI pins 11.19.0; `pnpm.ps1` is blocked by PowerShell execution policy — use `pnpm.cmd` on Windows) |
| Xcode | Required for the native app, simulator renders and IPA builds — **macOS only** |
| Playwright | `@playwright/test` 1.58; uses the bundled Chromium, except on Windows where `playwright.config.ts` points at an installed Google Chrome |

There is an important split: the **web engine, unit tests, E2E and type checking run anywhere** (including Windows), while the **Swift app, native test suites and IPA builds need macOS**. CI reflects that: `checks.yml` runs on `ubuntu-latest`, `build-ios.yml` runs on `macos-26`.

## Project Setup

```sh
git clone https://github.com/chengxiaomingcxm/us-stock-ledger.git
cd us-stock-ledger
git config core.hooksPath scripts/hooks      # enable the tracked pre-commit hook
```

The hook is a tracked file, so it has to be enabled once per clone. After that, `git commit` refuses to commit when the quality gate fails.

## Install Dependencies

```sh
pnpm install --frozen-lockfile
```

CI uses the same command, so a lockfile change is the only way dependency versions move.

## Run the Development Build

```sh
pnpm dev        # vite --host 127.0.0.1
```

This serves the **legacy web engine**, not the shipping app. It is still the quickest way to iterate on the ledger maths and the import screens. The Playwright suite does **not** drive it: `playwright.config.ts` starts `vite preview` on `127.0.0.1:4183` against the built `dist/` output, so run `pnpm build` first (see below).

To run the real app, open the Xcode project:

```sh
pnpm build          # tsc --noEmit && vite build
pnpm ios:sync       # cap sync ios — copies the built assets into the iOS project
open ios/App/App.xcodeproj
```

Then run on a simulator or your own device. The bundle identifier is `com.personal.stockledger`.

## Run Tests

```sh
pnpm test                          # Vitest — 148 cases in 13 files
bash scripts/test-native.sh        # macOS — native Swift suites (429 fixed assertions)
bash scripts/test-calendar-rendering.sh   # macOS — renders the calendar on a simulator
bash scripts/test-screenshots.sh          # macOS — renders all six README screenshots
```

The native number is quoted as **fixed assertions**. The harness prints `PASS: N assertions; … main actor heartbeats: K`, and `N` includes one assertion per heartbeat of the 25,000-close reload loop, so `N` moves with machine speed (observed 25–68 across runs). What never varies is `N − K`: 413 for the 1.0.1 build, 429 since the synthetic-statement fixture landed. Per-commit arithmetic lives in `docs/ENGLISH_UI_FINAL_AUDIT.md` §3.

`test-native.sh` compiles `tests/native/*.swift` together with the app sources through `swiftc`. It uses an **explicit file list**, and the native Swift test files live outside the Xcode project, so:

- adding a **new app source file** requires registering it in `ios/App/App.xcodeproj/project.pbxproj` in **four** places (`PBXBuildFile`, `PBXFileReference`, its `PBXGroup`, and the `PBXSourcesBuildPhase`) **and** adding it to the `swiftc` list in `scripts/test-native.sh`;
- adding a **new native test file** requires adding it to `NativeTests.swift` and to the `swiftc` list in `scripts/test-native.sh` (no Xcode registration needed).

Skipping the `test-native.sh` list gives the worst possible failure mode: the suite compiles what it knows about, prints a pass, and CI later fails on `cannot find 'X' in scope`. `AGENTS.md` documents this trap.

The simulator scripts expect an available `iPhone 17` simulator and write their evidence around blank-render guards: a missing, tiny or empty-state PNG fails the run.

## Run E2E Tests

```sh
pnpm e2e        # playwright test
```

`playwright.config.ts` starts `vite preview` on `127.0.0.1:4183` (`reuseExistingServer: true`) against the built `dist/` output — so run `pnpm build` first; a plain `pnpm dev` server does not serve that port. Specs live in `e2e/` — 26 cases covering the full user journeys, including "no horizontal overflow" at 320 / 402 / 430 px, which is what caught a real narrow-screen layout bug.

To run a subset:

```sh
pnpm exec playwright test preferences          # one spec
pnpm exec playwright test --headed             # watch it happen
```

## Build

```sh
pnpm build                              # type check + production build of the web engine
bash scripts/build-unsigned-ios.sh      # macOS — the unsigned IPA, with a .sha256 next to it
```

`build-unsigned-ios.sh` produces `build/StockLedger-unsigned.ipa`. `scripts/verify-ipa.py` checks that IPA's structure (Mach-O / ARM64, bundle id, embedded `public/index.html`) and compares it with the `.sha256` written next to it; matching an IPA against `releases/*.json` is `scripts/publish-release.py`'s job.

## Quality Gate

Before committing, or before calling anything done:

```sh
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
```

It checks what this repository actually has: git and pnpm are available, no build artefacts are tracked, no stray debug files would enter a commit, `pnpm test` passes, and `pnpm build` passes. Native and simulator checks are macOS-only and run in CI instead. There is **no lint step** — this repository has no linter by design (see the README, "Static checks: no ESLint, by design").

There is deliberately no `--no-verify` escape hatch documented here: if the gate fails, the fix is a real fix.

## Release

```sh
python3 scripts/publish-release.py
```

The script reads `releases/vX.Y.Z.json`, compares it with the tag and the uploaded assets, calls `scripts/verify-ipa.py` to validate the IPA, and publishes the release. `releases/vX.Y.Z.md` holds the human-readable notes (highlights, improvements, known limitations); `CHANGELOG.md` holds the running history.

`releases/*.json` is the pipeline's input list, and every manifest is walked on each run: one entry whose tag, assets or digest do not match a published release stops the whole run. `v1.0.0` predates the pipeline (published by hand, so its release carries no `UPGRADE-` asset and its tag sits at the commit that added the manifest), which is why it keeps its notes file and has no manifest.

`.github/workflows/publish-release.yml` runs the same script on dispatch, or on a push to `main` that touches `releases/**` or the release script itself. Versioning is semantic and follows the existing tags — do not renumber an existing release.

## Repository Conventions

- **Branches**: long-lived `main` and `deepseek-dev`; work happens on `portfolio/*` branches. `main` is not edited directly.
- **CI triggers**: pushes to `main`, `deepseek-dev` and `portfolio/**`, plus every pull request, run `checks.yml`; the macOS `build-ios.yml` runs on the same pushes but not on pull requests, to avoid burning macOS minutes on every PR.
- **Markdown-only changes** trigger neither workflow.
- **Same-branch pushes cancel each other**: `concurrency: checks-${{ github.ref }}` with `cancel-in-progress: true` means only the last push on a branch produces a trustworthy result. Wait for a run before pushing again if you need that specific commit verified.
- **`portfolio/*` branches have no upstream configured**, so a bare `git push` fails; use `git push origin <branch>` and verify with `git ls-remote origin refs/heads/<branch>`.

## One-off Scripts

Two scripts exist for setup tasks rather than routine development:

- `scripts/customize-ios.mjs` — sets the deployment target to iOS 16.0 in the Xcode project and adjusts `Info.plist` (arm64, `zh_CN`). Run once after regenerating the iOS project.
- `scripts/make-icon.mjs` — regenerates the app icon and splash images from `scripts/icon.svg` using Sharp. The generated PNGs are committed, so this only needs to run when the icon changes.
