#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == */CommandLineTools ]]; then
  for developer in /Applications/Xcode*.app/Contents/Developer; do
    if [[ -x "$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
      export DEVELOPER_DIR="$developer"
      break
    fi
  done
fi
swift build -c release
app=".build/UniversalControlHelper.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/UniversalControlHelper "$app/Contents/MacOS/UniversalControlHelper"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>UniversalControlHelper</string>
<key>CFBundleIdentifier</key><string>com.local.universalcontrolhelper</string>
<key>CFBundleName</key><string>Universal Control Helper</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "Built $app"
