#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh
app=".build/Crossover.app"
identity="${SIGN_ID:--}"
codesign --force --deep -s "$identity" "$app"
codesign --verify --deep "$app"

info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info" 2>/dev/null || true)
if [[ -z "$version" ]]; then
  version="1.0.0"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$info"
fi
[[ "$version" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid bundle version: $version" >&2; exit 1; }

mkdir -p dist
dmg="dist/Crossover-$version.dmg"
pkg="dist/Crossover-$version.pkg"
workdir=$(mktemp -d "${TMPDIR:-/tmp}/crossover.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
rm -f "$dmg" "$pkg"

mkdir "$workdir/dmg"
cp -R "$app" "$workdir/dmg/"
ln -s /Applications "$workdir/dmg/Applications"
hdiutil create -volname "Crossover" -srcfolder "$workdir/dmg" -ov -format UDZO "$dmg"

pkgbuild --component "$app" --install-location /Applications "$workdir/unsigned.pkg"
if [[ -n "${SIGN_INSTALLER_ID:-}" ]]; then
  productsign --sign "$SIGN_INSTALLER_ID" "$workdir/unsigned.pkg" "$pkg"
else
  mv "$workdir/unsigned.pkg" "$pkg"
fi

echo "Built $dmg and $pkg"
