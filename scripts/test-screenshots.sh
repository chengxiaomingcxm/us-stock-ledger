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

for screen in holdings trades returns settings calendar calendar-percent import; do
  echo "=== launching $screen ==="
  xcrun simctl launch --terminate-running-process "$UDID" "com.stockledger.screens" "$screen" >/dev/null
  sleep 8
  xcrun simctl io "$UDID" screenshot "$ROOT/$screen.png"
  xcrun simctl terminate "$UDID" "com.stockledger.screens" 2>/dev/null || true
done

# 崩溃或白屏同样会产出一个 PNG，所以逐张查是否真的渲染出了内容。
for screen in holdings trades returns settings calendar calendar-percent import; do
  png="$ROOT/$screen.png"
  [ -s "$png" ] || { echo "FAIL: $screen.png 缺失"; exit 1; }
  size="$(wc -c < "$png")"
  [ "$size" -ge 20000 ] || { echo "FAIL: $screen.png 只有 $size 字节，疑似空白画面"; exit 1; }
done

# 日历那一屏必须真的有收益数据：它曾因为没订阅 AppState 而停在空态，
# 而空态截图同样有 100+ KB，体积守卫拦不住。
if ! xcrun simctl spawn "$UDID" log show --last 5m \
  --predicate 'process == "Screens" AND eventMessage CONTAINS "HARNESS derived screen=calendar"' 2>/dev/null \
  | grep -qE 'days=[1-9][0-9]* months=[1-9][0-9]*'; then
  echo "FAIL: 日历屏没有收益数据（期望 days>0 且 months>0）"
  exit 1
fi

echo '--- last 3 minutes of Screens process log ---'
xcrun simctl spawn "$UDID" log show --last 3m --predicate 'process == "Screens"' 2>/dev/null | tail -120 || true
echo '--- HARNESS markers ---'
xcrun simctl spawn "$UDID" log show --last 5m --predicate 'process == "Screens" AND eventMessage CONTAINS "HARNESS"' 2>/dev/null | tail -60 || true
echo '--- recent crash reports ---'
for f in "$HOME"/Library/Logs/DiagnosticReports/Screens-*.ips; do
  [ -e "$f" ] || continue
  echo "=== $(basename "$f") ==="
  python3 - "$f" <<'PYEOF' || true
import json, sys
raw = open(sys.argv[1], 'rb').read()
idx = raw.find(b'\n')
try:
    body = json.loads(raw[idx+1:] if idx >= 0 else raw)
except Exception as e:
    print("parse error:", e)
    print(raw[:4000].decode('utf-8', 'replace'))
    sys.exit(0)
print("exception:", json.dumps(body.get("exception", {}), ensure_ascii=False))
print("termination:", json.dumps(body.get("termination", {}), ensure_ascii=False))
print("asi:", json.dumps(body.get("asi", {}), ensure_ascii=False))
ft = body.get("faultingThread", 0)
threads = body.get("threads", []) or []
if isinstance(ft, int) and ft < len(threads):
    t = threads[ft]
    print("faulting thread name:", t.get("name", ""))
    print("faulting thread frames:")
    for fr in t.get("frames", [])[:40]:
        print("  ", fr.get("imageIndex"), fr.get("symbol", ""), fr.get("sourceFile", ""), fr.get("sourceLine", ""))
PYEOF
done

echo 'English UI screenshots ready.'
