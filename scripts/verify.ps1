# Stock Ledger Quality Gate (Windows)
#
# Unified pre-commit / pre-push / pre-release verification.
# Run it with:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
#
# Checks reflect what this repo actually has, not what a template assumes:
#   - git + pnpm availability
#   - no tracked build/generated artifacts (dist/, build/, *.ipa, ...)
#   - no debug/temp files that would enter the next commit (tracked, staged or untracked)
#   - known debug residue (log.txt, state.txt, ...) blocks the gate even if gitignored
#   - lint / test / build are read from package.json scripts and run when present
#   - native Swift/simulator checks are macOS-only and run in CI instead
#
# Exit code: 0 = QUALITY GATE PASSED, non-zero = FAILED.

param()

$ErrorActionPreference = 'Continue'
$script:failures = New-Object System.Collections.Generic.List[string]

function Pass($msg) { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:failures.Add($msg) }
function Skip($msg) { Write-Host "[SKIP] $msg" -ForegroundColor DarkGray }
function Info($msg) { Write-Host "[INFO] $msg" }

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

Write-Host ""
Write-Host "=== Stock Ledger Quality Gate ===" -ForegroundColor Cyan
Write-Host "repo: $repo"

# --- 1. tooling ---------------------------------------------------------
if (Get-Command git -ErrorAction SilentlyContinue) {
    Pass "git available"
} else {
    Fail "git is not installed or not on PATH"
}

# pnpm is installed as pnpm.CMD on this machine; pnpm.ps1 is blocked by the
# execution policy, so always prefer the .cmd shim.
$pnpm = $null
foreach ($candidate in @('pnpm.cmd', 'pnpm')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $pnpm = $candidate; break }
}
if ($pnpm) {
    Pass "pnpm available ($pnpm)"
} else {
    Fail "pnpm is not installed or not on PATH"
}

# --- 2. tracked build/generated artifacts --------------------------------
$forbiddenTracked = '^(dist/|build/|artifacts/|node_modules/|test-results/|playwright-report/|__pycache__/)|\.(ipa|p12|p8|mobileprovision|pyc|ips)$|(^|/)\.DS_Store$|^\.github/workflows/.*debug.*\.ya?ml$'
$tracked = @(git ls-files 2>$null)
$bad = @($tracked | Where-Object { $_ -match $forbiddenTracked })
if ($bad.Count -gt 0) {
    foreach ($f in $bad) { Fail "tracked build/generated artifact should not be committed: $f" }
} else {
    Pass "no tracked build/generated artifacts"
}

# --- 3. debug/temp files that would enter the next commit -----------------
# "debug" as a bare name segment is NOT flagged (a legit debug utility may be
# named debug.ts). Temp markers and known debug artifacts are, plus a workflow
# named *debug*.yml (a temporary debug workflow).
$debugUntracked = '(^|/)(log\d*\.txt|watch\d*\.txt|state\.txt|jobs\d*\.json|crash\w*\.(txt|log)|tmp|temp|scratch|draft|wip|junk)(\.|/|$)|\.(ips|tmp|bak|orig|rej|swp)$|^\.github/workflows/.*debug.*\.ya?ml$'
$status = @(git status --porcelain --untracked-files=all 2>$null)
$untracked = @($status | Where-Object { $_ -match '^\?\? ' } | ForEach-Object { $_.Substring(3) })
$stagedNew = @(git diff --cached --name-only --diff-filter=A 2>$null)
$badDebug = @(($untracked + $stagedNew) | Where-Object { $_ -match $debugUntracked })
if ($badDebug.Count -gt 0) {
    foreach ($f in $badDebug) { Fail "debug/temp file would be committed: $f" }
} else {
    Pass "no debug/temp files entering the commit"
}

# --- 4. known debug residue (blocks the gate, even though gitignored) ------
# These are developer temp files. If they are still present when a task ends,
# the working tree has not been cleaned up, so the gate must fail.
$knownResidue = @('log.txt', 'log2.txt', 'watch.txt', 'watch2.txt', 'state.txt', 'jobs.json', 'jobs2.json')
$residuePresent = @($knownResidue | Where-Object { Test-Path (Join-Path $repo $_) })
if ($residuePresent.Count -gt 0) {
    foreach ($f in $residuePresent) { Fail "debug residue still present, remove it: $f" }
} else {
    Pass "no debug residue in working tree"
}

# --- 5. scripts from package.json (not hardcoded) --------------------------
$pkg = $null
if (Test-Path (Join-Path $repo 'package.json')) {
    try {
        $pkg = Get-Content -Raw (Join-Path $repo 'package.json') | ConvertFrom-Json
        Pass "package.json loaded"
    } catch {
        Fail "package.json could not be parsed: $($_.Exception.Message)"
    }
} else {
    Fail "package.json not found"
}

$hasLint = ($null -ne $pkg) -and ($null -ne $pkg.scripts) -and ($null -ne $pkg.scripts.PSObject.Properties['lint'])
$hasTest = ($null -ne $pkg) -and ($null -ne $pkg.scripts) -and ($null -ne $pkg.scripts.PSObject.Properties['test'])
$hasBuild = ($null -ne $pkg) -and ($null -ne $pkg.scripts) -and ($null -ne $pkg.scripts.PSObject.Properties['build'])

# --- 6. lint --------------------------------------------------------------
if (-not $pnpm) {
    Fail "skipping lint: pnpm unavailable"
} elseif ($hasLint) {
    Write-Host ""
    Info "running: $pnpm lint"
    & $pnpm lint
    if ($LASTEXITCODE -eq 0) { Pass "pnpm lint" }
    else { Fail "pnpm lint failed (exit $LASTEXITCODE)" }
} else {
    Skip "no lint script in package.json; type checking is covered by the build step"
}

# --- 7. unit tests ---------------------------------------------------------
if (-not $pnpm) {
    Fail "skipping tests: pnpm unavailable"
} elseif ($hasTest) {
    Write-Host ""
    Info "running: $pnpm test"
    & $pnpm test
    if ($LASTEXITCODE -eq 0) { Pass "pnpm test" }
    else { Fail "pnpm test failed (exit $LASTEXITCODE)" }
} else {
    Skip "no test script in package.json"
}

# --- 8. build ---------------------------------------------------------------
if (-not $pnpm) {
    Fail "skipping build: pnpm unavailable"
} elseif ($hasBuild) {
    Write-Host ""
    Info "running: $pnpm build"
    & $pnpm build
    if ($LASTEXITCODE -eq 0) { Pass "pnpm build" }
    else { Fail "pnpm build failed (exit $LASTEXITCODE)" }
} else {
    Skip "no build script in package.json"
}

# --- 9. native Swift/simulator checks --------------------------------------
if ($env:OS -eq 'Windows_NT') {
    Skip "native checks (scripts/test-native.sh, test-calendar-rendering.sh, test-screenshots.sh) are macOS-only; covered by CI on macos-26"
} else {
    Info "running: bash scripts/test-native.sh"
    bash scripts/test-native.sh
    if ($LASTEXITCODE -eq 0) { Pass "native Swift tests" } else { Fail "native Swift tests failed (exit $LASTEXITCODE)" }
}

# --- summary ----------------------------------------------------------------
Write-Host ""
if ($script:failures.Count -gt 0) {
    Write-Host "QUALITY GATE FAILED - $($script:failures.Count) failure(s)" -ForegroundColor Red
    foreach ($f in $script:failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "QUALITY GATE PASSED" -ForegroundColor Green
exit 0
