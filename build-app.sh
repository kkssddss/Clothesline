#!/bin/bash
# Packages the program as Clothesline.app, installs it in Applications, and reopens it
# Usage: run ./build-app.sh in the project folder
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=".build/Clothesline.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Clothesline "$APP/Contents/MacOS/Clothesline"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Clothesline</string>
    <key>CFBundleIdentifier</key>
    <string>local.clothesline</string>
    <key>CFBundleExecutable</key>
    <string>Clothesline</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Reads the screenshots and screen recordings on your Desktop to hang them on the clothesline.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Quit the old version if it's running, install into Applications, and open it again.
# Without permission to write to /Applications, install into your own ~/Applications instead
DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
pkill -x Clothesline 2>/dev/null || true
rm -rf "$DEST/Clothesline.app"
cp -R "$APP" "$DEST/"
open "$DEST/Clothesline.app"
echo "Done. Installed $DEST/Clothesline.app and opened it."
