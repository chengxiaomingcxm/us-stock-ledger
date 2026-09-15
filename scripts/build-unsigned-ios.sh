#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS compilation requires macOS with Xcode. Use the GitHub Actions workflow."
  exit 1
fi
cd "$(dirname "$0")/.."
xcodebuild -version
xcodebuild -resolvePackageDependencies -project ios/App/App.xcodeproj -scheme App
xcodebuild -project ios/App/App.xcodeproj -scheme App \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  build
APP_PATH="build/DerivedData/Build/Products/Release-iphoneos/App.app"
test -d "$APP_PATH"
test -f "$APP_PATH/App"
file "$APP_PATH/App"
xcrun lipo -verify_arch arm64 "$APP_PATH/App"
/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP_PATH/Info.plist" | grep -qx 'iPhoneOS'
test -f "$APP_PATH/public/index.html"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/stockledger-ipa.XXXXXX")"
mkdir -p "$STAGING/Payload"
ditto "$APP_PATH" "$STAGING/Payload/App.app"
OUTPUT="$PWD/build/StockLedger-unsigned.ipa"
(cd "$STAGING" && /usr/bin/zip -q -r -y StockLedger-unsigned.ipa Payload)
mv "$STAGING/StockLedger-unsigned.ipa" "$OUTPUT"
unzip -t "$OUTPUT"
(cd build && shasum -a 256 StockLedger-unsigned.ipa > StockLedger-unsigned.ipa.sha256)
echo "Created real-device IPA at $OUTPUT. Sign it before installing on iPhone."
