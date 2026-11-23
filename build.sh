#!/bin/bash
# Bouwt Sluiter.app. Met --install wordt hij ook in /Applications gezet en gestart.
set -euo pipefail
cd "$(dirname "$0")"

APP="Sluiter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/Sluiter" $(ls *.swift | grep -v makeicon.swift)

# App-icoon (.icns) maken
TMP="$(mktemp -d)"
swift makeicon.swift "$TMP/icon.png"
ICONSET="$TMP/Sluiter.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Sluiter.icns"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sluiter</string>
  <key>CFBundleDisplayName</key><string>Sluiter</string>
  <key>CFBundleIdentifier</key><string>local.sluiter</string>
  <key>CFBundleExecutable</key><string>Sluiter</string>
  <key>CFBundleIconFile</key><string>Sluiter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Snel apps en vensters sluiten.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier local.sluiter "$APP" >/dev/null 2>&1 || true
echo "Gebouwd: $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Sluiter 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  touch "/Applications/$APP"   # Finder/Dock het nieuwe icoon laten oppikken
  open "/Applications/$APP"
  echo "Geïnstalleerd in /Applications en gestart."
fi
