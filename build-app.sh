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
app=".build/Crossover.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Crossover "$app/Contents/MacOS/Crossover"
cp -R .build/release/Crossover_Crossover.bundle "$app/Contents/Resources/"
cp -R Sources/Crossover/Resources/Fonts "$app/Contents/Resources/Fonts"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Crossover</string>
<key>CFBundleIdentifier</key><string>com.local.crossover</string>
<key>CFBundleName</key><string>Crossover</string>
<key>CFBundleDisplayName</key><string>Crossover</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>ATSApplicationFontsPath</key><string>Fonts</string>
</dict></plist>
PLIST
echo "Built $app"
