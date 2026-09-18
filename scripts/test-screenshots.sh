#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/screenshots
ROOT="$PWD/build/screenshots"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
UDID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for devices in d["devices"].values() for v in devices if v["name"] == "iPhone 17"))')"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
trap 'xcrun simctl shutdown "$UDID" || true' EXIT
xcrun simctl status_bar "$UDID" override --time '9:41' --batteryState charged --batteryLevel 100

APP="$ROOT/AppScreens.app"
mkdir -p "$APP"
sources=(ios/App/App/StockLedger/*.swift)
echo "Compiling screenshot harness"
xcrun swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK" \
  -target "$ARCH-apple-ios16.0-simulator" "${sources[@]}" \
  tests/native/ScreenshotsApp.swift -o "$APP/Screens"

cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.stockledger.screens</string>
<key>CFBundleExecutable</key><string>Screens</string>
<key>CFBundleName</key><string>Screens</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>16.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
xcrun simctl install "$UDID" "$APP"

for screen in holdings trades returns settings calendar; do
  xcrun simctl launch --terminate-running-process "$UDID" "com.stockledger.screens" "$screen" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$ROOT/$screen.png"
  xcrun simctl terminate "$UDID" "com.stockledger.screens" 2>/dev/null || true
done

echo 'English UI screenshots ready.'
