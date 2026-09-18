#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/calendar-render
ROOT="$PWD/build/calendar-render"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
UDID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for devices in d["devices"].values() for v in devices if v["name"] == "iPhone 17"))')"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
trap 'xcrun simctl shutdown "$UDID" || true' EXIT
xcrun simctl status_bar "$UDID" override --time '9:41' --batteryState charged --batteryLevel 100

build_app() {
  local variant="$1"
  local app="$ROOT/$variant.app"
  mkdir -p "$app"
  local sources=()
  for source in ios/App/App/StockLedger/*.swift; do
    if [[ "$variant" == baseline && "$source" == */InsightsView.swift ]]; then
      git show e2b38f6:ios/App/App/StockLedger/InsightsView.swift > "$ROOT/BaselineInsights.swift"
      sources+=("$ROOT/BaselineInsights.swift")
    else
      sources+=("$source")
    fi
  done
  xcrun swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK" \
    -target "$ARCH-apple-ios16.0-simulator" "${sources[@]}" \
    tests/native/CalendarRenderApp.swift -o "$app/CalendarRender"
  cat > "$app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.stockledger.calendar-$variant</string>
<key>CFBundleExecutable</key><string>CalendarRender</string>
<key>CFBundleName</key><string>CalendarRender</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>16.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
EOF
  codesign --force --sign - "$app"
  xcrun simctl install "$UDID" "$app"
}

capture() {
  local variant="$1" month="$2" appearance="$3" size="$4"
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl ui "$UDID" content_size "$size"
  xcrun simctl launch --terminate-running-process "$UDID" "com.stockledger.calendar-$variant" "$month"
  sleep 4
  xcrun simctl io "$UDID" screenshot "$ROOT/$variant-$month-$appearance-$size.png"
  xcrun simctl terminate "$UDID" "com.stockledger.calendar-$variant"
}

build_app baseline
capture baseline 2026-09 light large
build_app fixed
capture fixed 2026-09 light large
capture fixed 2026-08 light large
capture fixed 2026-02 dark large
capture fixed 2026-09 light extra-extra-extra-large
capture fixed empty light large
echo 'Production calendar screenshots ready for visual review (not an FPS benchmark).'
