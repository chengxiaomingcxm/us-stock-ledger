# US Stock Ledger — Case Study

> A native iOS personal-finance application: a complete software engineering project with real business logic, data processing, API integration, a UI, tests and a release pipeline.
> Every technical claim below is traceable to this repository — code, tests, CI logs or `docs/PHASE_*_REVIEW.md`. Nothing here is invented.

## Problem

Individual investors who track their own US stock portfolio hit the same wall. Broker apps are built to show *today's positions*; they are not built to answer the questions that decide whether a year went well:

- What did I actually pay, after fees, across a dozen separate buys?
- How much did I really make — and how much of what landed in my account was a deposit rather than a gain?
- What changed today, and on each day before that?
- Does my own record still agree with the broker's statements?
- Where is my cash, and how much of it moved because of trading rather than because I wired money in?

A spreadsheet can answer some of this and then becomes unmaintainable: average cost, realized gains, dividends net of withholding, account fees, daily returns and cash flow all interact, and a single mistyped fee silently corrupts everything downstream.

## Goal

Build an application that is honest about money and private by construction:

- One reliable, auditable place for trades, cash, dividends and fees.
- Returns that separate *investment* performance from *cash movements*, so a deposit never looks like a profit.
- Import paths for the statements a broker actually produces, with a review step before anything is written.
- No account, no server, no telemetry: financial data stays on the phone.
- Small enough that one developer can keep the whole thing correct.

Explicitly out of scope, from the start: order placement, brokerage synchronization, multi-currency FX, options, short selling and automatic corporate-action processing.

## Solution

A native SwiftUI app for iPhone with a deliberately boring architecture: four layers, one write path, one file.

- **`Engine`** is a pure calculator. Given the ledger and cached quotes, it derives positions, weighted-average cost, realized and unrealized returns, cash totals, today's P&L and the daily-return series. No I/O, no global state, easy to test against golden ledgers.
- **`AppState`** is the only mutation path: validate, write to disk, then update memory.
- **`LedgerStore`** persists one versioned JSON document in the app's own `Documents` folder, written atomically.
- **Views** render a cached derived snapshot and dispatch intents. They never compute money.

Statements are handled by two importers (broker CSV and HSBC investment-statement PDF) that parse, normalize and validate a whole batch before the user confirms it. Historical closes prefer Tiingo with Yahoo and Nasdaq fallbacks; intraday quotes use Yahoo Finance, Finnhub or a user-supplied HTTPS endpoint. API keys stay in the iOS Keychain.

## Key Features

| Capability | What it demonstrates |
| --- | --- |
| Weighted-average cost, realized / unrealized / total return | Business logic with real accounting rules |
| Cash ledger: opening balance, deposits, withdrawals, dividends (with tax), fees, automatic buy/sell cash flow | Business logic that must not confuse cash with P&L |
| Today's P&L against the previous close, in US-Eastern terms | Time-zone-correct analytics |
| Daily-return calendar and cumulative-return curve | Data visualization over a recomputed time series |
| Chart interactions and per-day detail | UI work, not just data work |
| Broker CSV import with field mapping, duplicate detection and a preview | File processing and validation |
| HSBC investment-statement PDF import via PDFKit | Unstructured document parsing |
| Quote providers with normalization, caching and graceful degradation | External API integration |
| Local JSON persistence with backup and restore | Local data management and data integrity |
| Demo Mode with an isolated ledger | Product thinking: first-run experience without risking user data |
| Light/dark, color-scheme choice, Dynamic Type, VoiceOver | Accessibility |
| Vitest, native Swift suites, simulator render guards, Playwright, two CI workflows | Testing and release engineering |
| Unsigned-IPA release pipeline with checksums and manifest verification | Shipping a real artefact |

## Technical Challenges

Each of these is a real problem this project hit, and each left a fix and a test behind.

### 1. A missing quote must never become zero

The naive implementation is `quote ?? 0`, which turns "I don't know" into "your position is worth nothing" and poisons every downstream total. Modelling value as `Decimal?` through the whole computation forces every consumer to decide what to show. The app reports `nil` and renders "waiting for data" instead of a number it cannot justify.

### 2. Reconciling with the broker to the cent

Summing *quantity × price + fee* across many fills can land half a cent away from the settlement amount printed on the statement. Since that number is what the user compares against, the model carries the broker's `settlementAmount` when it is known and prefers it, instead of re-deriving it. All money is `Decimal` — never `Double` — from the model through the engine to formatting.

### 3. A ledger that could be silently lost

The original load path returned an empty ledger when the JSON file failed to parse, and a later save would then overwrite the real file with that empty ledger: a silent, unrecoverable data-loss path with no user-visible signal. Fixed by surfacing a readable error plus technical detail in the on-device diagnostics log, and by making saves **write to disk first and only then update memory**, so a failed write cannot leave the app believing data was stored.

### 4. Demo Mode that overwrote real data

The first version of the sample ledger wrote straight into the live ledger and "exited" by clearing it — an unacceptable first-run experience for a finance app. The fix reuses the existing dependency-injection point in `AppState`: Demo Mode runs on its own state, is flagged globally so the UI can say so, and never touches the user's file.

### 5. A screenshot harness that rendered an empty screen

The screenshot pipeline launches a small SwiftUI harness in the simulator and saves PNGs. The calendar screen came out empty while still producing a perfectly plausible 100 KB+ file, because the rendering helper never subscribed to the app's observable state, so SwiftUI had no reason to re-render when the derived data arrived. Two guards came out of this: screenshots must exceed a minimum size **and** the harness must log a `HARNESS derived screen=… days=N months=M` marker that the script asserts on. A blank render now fails the build instead of shipping into the README.

### 6. A 320 px layout bug that only existed on Linux

`pnpm e2e` passed 26/26 on Windows, then failed in CI on one case: the returns page overflowed horizontally at a 320 px viewport. Instrumenting the assertion to report *which element* overflowed (same pass/fail rule, better diagnostics) showed the cause: `.cash-totals` used `grid-template-columns: repeat(2, 1fr)`, and `1fr` resolves to `minmax(auto, 1fr)`, whose `auto` minimum is the cell's min-content size. Unbreakable money strings like `$20,000.00` pinned the grid to 285.7 px, which with its 34 px offset needed 319.72 px of a 320 px viewport — **0.28 px of slack**, so a font with marginally wider digits was enough to break it. The fix is `minmax(0, 1fr)`, consistent with the calendar grid already in the codebase, and the E2E assertion now names the offending element when it fails.

### 7. Error messages that leaked system text — and 61 that were never translated

Error paths originally surfaced raw system errors, and a translation sweep found 61 messages missing from the English catalogue. Worse, 15 of them interpolated values into the lookup key, so the dictionary could never match and the user always saw the fallback. Fixed by converting those to `{}` placeholder lookups, translating the static ones, and routing raw system text into the diagnostics log while the UI shows a human sentence.

### 8. Parsing a bank's PDF statement

An investment-statement PDF is a text layer plus a grid that arrives as positional fragments. The importer extracts text with PDFKit, reconstructs rows, classifies each line as a trade, a dividend or a fee, parses localized number formats, and rejects rows it cannot classify rather than guessing. The result is a reviewable report — valid, skipped, duplicate, error — which the user confirms before anything is written.

### 9. Keeping a 4,000-session history responsive

Recomputing the whole daily-return series on every UI update is not acceptable. Derived state is precomputed off the main thread into a cached snapshot, keyed on the ledger's revision, so it is reused while the ledger is unchanged. A CI load test covers 25,000 closes across 4,000 sessions and 1,000 trades and currently completes in about 0.25 s.

### 10. Two runtimes in one repository

The project began as a TypeScript/Vite web prototype and was rewritten in SwiftUI. What remains is unusual and deliberate: the web engine is still built, still bundled, and still tested by 148 Vitest cases and 26 Playwright cases, because it is the fastest place to regression-test ledger maths and import rules — while the shipping UI is Swift. The README states this plainly so nobody mistakes the web code for the product.

### 11. A false-green test setup

The native Swift suites are compiled by `swiftc` from an explicit file list, while the app builds from the Xcode project. A new file that is missing from one of them compiles locally (because the local list happens not to include it) and fails only in CI with `cannot find 'X' in scope`. The repository handles this by documenting the two registration points and by keeping the native suites on the CI macOS runner, where the real project is compiled too.

## Engineering Decisions

| Decision | Why |
| --- | --- |
| `Decimal`, never `Double`, for money | Financial arithmetic must not accumulate binary-floating-point error |
| A pure `Engine` with no I/O | The valuable logic is testable against golden ledgers without a simulator or a file system |
| One `AppState` write path, disk before memory | A single place to validate and persist; a failed write can never be mistaken for a success |
| One JSON document, atomic writes, no schema field | The file name carries the format generation, and format 2 is the **1.0 baseline** — so a 1.0 ledger keeps loading across upgrades instead of anyone's data being cleared (pre-1.0 beta files are not compatibility targets) |
| API keys in the Keychain, never in the ledger or a backup | Secrets belong in the platform secret store, and a backup file is meant to be copied around |
| Missing data stays missing (`Decimal?`) | "Unknown" and "zero" are different facts, and conflating them produces confidently wrong totals |
| Demo Mode isolated from day one of any feature work | A finance app must never risk a user's real data to show a sample |
| Imports validate the full batch before writing | Half-imported statements are worse than a rejected one |
| No linter introduced to satisfy a checklist | The repository had none; adding tooling to tick a box produces unowned configuration. Type checking is `tsc --noEmit` and is called exactly that |
| The legacy web engine is frozen, not migrated | Keeping it costs almost nothing and buys a fast, independent regression net |
| Two CI workflows on two runners | The fast checks run in about a minute on `ubuntu-latest`; the 14-minute macOS build with native tests and simulator renders runs on the same pushes but not on pull requests |
| Documentation states limitations plainly | A clear scope reads as engineering judgement; hidden gaps read as inexperience |

## Testing

Four layers, each catching a different class of mistake:

| Layer | Size | Catches |
| --- | --- | --- |
| Vitest (web engine) | 148 cases / 13 files | Ledger maths, cash rules, trade ranges, today's P&L, CSV import rules, storage and recovery, localization |
| Native Swift suites | 452 fixed assertions | The real engine against golden ledgers, safety and recovery paths, diagnostics, Demo Mode, CSV import, error paths, plus a 25,000-close load test |
| Simulator renders | 6 screens + calendar | Screens that render nothing, empty state shown as if it were data, regressions in the render harness |
| Playwright | 26 cases | Full user journeys against the built app, including layout overflow at 320 / 402 / 430 px |

This layering is not theoretical — each layer has caught something real: the native suites caught error-path regressions and a batch-oversell case in CSV import; the simulator guards caught the empty calendar screenshot; the Playwright overflow assertion caught the 320 px grid bug that had shipped invisibly; and CI itself caught two Swift compile errors that a local run reported as passing.

## Privacy

Financial data is treated as data that never leaves the device:

- The ledger is a single JSON file in the app's own `Documents` folder. There is no server component and no account.
- Quote requests send **only ticker symbols** to Tiingo, Yahoo Finance, Nasdaq, Finnhub or a user-supplied endpoint — never quantities, cost basis, cash records, manual prices or backups.
- No analytics, no crash reporting, no advertising SDK, no third-party tracking.
- Technical failures are recorded in a **local** diagnostics log; nothing is uploaded.
- API keys live in the iOS Keychain and are excluded from backups.
- The repository contains no key, token, secret or personal account information in the working tree **or anywhere in its git history** — the entire history was scanned for private-key blocks, `API_KEY` / `SECRET` / `TOKEN` / `PASSWORD` / `PRIVATE_KEY` patterns and credential-shaped files before publication.

## Result

A shipping-quality iOS application, built and maintained by one developer:

- Native SwiftUI app for iOS 16+, 17 source files, with a pure calculation engine, validated mutations, atomic local persistence and Keychain-backed secrets.
- Three independent test layers plus simulator render guards: 149 unit cases, 452 fixed native assertions, 26 end-to-end cases.
- Two CI workflows: a ~1-minute check chain on `ubuntu-latest` for every push and pull request, and a ~14-minute macOS pipeline that runs the native suites, renders the calendar and all README screenshots, and builds an unsigned IPA.
- A release pipeline that verifies the IPA against a manifest and publishes it with a checksum.
- Documentation that lets a stranger understand the product, the architecture and the limitations in a few minutes.

The most valuable outcome is not a feature list. It is that the risky parts now fail loudly: an unreadable ledger, a blank screenshot, an untranslated error, a 0.28 px layout margin — all of them have a guard that turns them into a build failure instead of a quiet defect.

## Lessons Learned

1. **A green local run is not evidence.** The 320 px bug passed 26/26 locally and failed on Linux because of nothing but font metrics; a Swift file missing from a `swiftc` list compiles locally and fails in CI. Verify on the platform that matters.
2. **An assertion should say why it failed.** Changing `toBe(true)` into "which element overflowed, and by how much" cost nothing and turned a mystery into a root cause in one CI run.
3. **Locally-correct and correct are different things.** The grid bug was not a flaky test — it was a real defect that a font with slightly wider digits could trigger on a real phone. The fix belonged in the CSS, not in the test.
4. **Test data must be able to fail.** A 100 KB blank PNG passes a size check; a "passing" suite that silently skips a file passes a compile check. Assertions need to test the thing, not a proxy for it.
5. **State limitations before someone finds them.** Falling interest, unsupported instruments and missing features are scope decisions. Documented scope reads as judgement; discovered gaps read as inexperience.
6. **Numbers in documentation must be re-derivable.** Test counts, timings and CI results in this repository come from actual runs, not from memory — anything that could not be verified was left out rather than estimated.
7. **Fix the root cause, not the symptom.** The tempting fix for the CI failure was to loosen the assertion. Finding the 0.28 px margin instead fixed a real bug and made the whole page robust to any font.
