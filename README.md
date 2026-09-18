# Stock Ledger

A personal US-stock ledger for iPhone. Record your buys and sells, reconcile cash and dividends, and see your real returns — privately, entirely on your device. No account, no cloud, no tracking.

> **中文版见 [README.zh-Hans.md](README.zh-Hans.md)。** / Chinese version: [README.zh-Hans.md](README.zh-Hans.md).

## What this solves

Broker apps show you today's positions, but they rarely answer the questions that actually matter to an individual investor:

- **What did I actually pay?** Weighted-average cost across many buys, with fees included.
- **What have I really made?** Realized gains, open gains, dividends (net of withholding), account fees — separated so deposits and withdrawals are never mistaken for profit.
- **What changed today, and every day since?** Today's P&L against the previous close, a daily-returns calendar, and a cumulative-return curve.
- **Does it match the broker?** Import trade CSVs or HSBC investment-statement PDFs with a preview before anything is written, so duplicates never sneak in.
- **Where is my cash?** Opening balance, deposits, withdrawals, dividends and fees — with buy/sell cash flow reconciled automatically.

The app never places orders, never touches multi-currency FX, shorting, options, or automatic corporate-action processing.

## Features

- US stocks and ETFs in USD, with fees and notes.
- Holdings: average cost, realized and unrealized return, current value, quote source and age.
- Today's P&L: previous close + current price + today's trades and fees; shows "waiting for data" instead of a fake zero when a quote is missing.
- Cash ledger: opening balance, deposits, withdrawals, manual dividends (with tax) and account fees.
- Daily-return calendar and cumulative-return curve (weekly axis marks and a zero line).
- Quotes: Yahoo daily closes, Finnhub, or a custom HTTPS endpoint; API keys stay in the iOS Keychain.
- Imports with preview and confirmation: broker trade/cash CSVs and HSBC investment-statement PDFs.
- Backup and restore as a local JSON file; export reminders after 30 days.
- Light/dark mode, "green up / red up" color schemes, Dynamic Type and VoiceOver support.

## Try the demo

No sign-up and no data required. After installing, open **Settings → Load demo ledger** to explore a sample portfolio (trades, dividends, fees and an opening balance). Clear it with **Exit demo and clear ledger** when you're ready to enter your own numbers.

## Install (no coding required)

1. Download `StockLedger-unsigned.ipa` from the latest [Release](https://github.com/chengxiaomingcxm/us-stock-ledger/releases) (e.g. `v1.0.0`).
2. Install a free signing tool such as [Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/) on your computer.
3. Plug in your iPhone, open the tool, drag the IPA in, and sign in with your own Apple ID.
4. Keep the bundle identifier `com.personal.stockledger` and use an **update/overlay install** — do **not** uninstall the old version first, or you'll lose your ledger.
5. Back up regularly from **Settings → Export ledger backup**, and keep the file outside the app.

The IPA is unsigned because it is built without a paid Apple Developer account; the checksum next to each release lets you verify the file you downloaded.

## Releases

Releases use proper semantic versioning (`v1.0.0`, `v1.1.0`, …). See the [release page](https://github.com/chengxiaomingcxm/us-stock-ledger/releases) and [CHANGELOG.md](CHANGELOG.md).

## Tech stack

| Layer | Technology |
| --- | --- |
| Native iOS app | SwiftUI, iOS 16+, Swift 5 |
| Storage | Local JSON in Documents; API keys in the iOS Keychain |
| Statements | PDFKit (HSBC investment statement) |
| Legacy web engine (retained for build/test) | TypeScript, Vite, Capacitor |
| Tests | Vitest (147) + native Swift tests + simulator calendar rendering |
| CI | GitHub Actions on macOS |

## Project layout

- `ios/App/App/StockLedger/` — the native SwiftUI app.
- `src/`, `tests/` — the legacy web engine and its test suite.
- `scripts/` — native test, simulator render, IPA build and verification scripts.
- `releases/` — per-version release notes.
- `docs/archive/` — documentation from the old web version.

## Development

```sh
pnpm install --frozen-lockfile
pnpm test
bash scripts/test-native.sh              # macOS
bash scripts/test-calendar-rendering.sh  # macOS
bash scripts/build-unsigned-ios.sh       # macOS, produces the IPA
```

Development happens on `deepseek-dev`; reviewed changes are merged to `main`, and official IPA builds run from `main` only.

## Screenshots

Coming soon (English UI).
