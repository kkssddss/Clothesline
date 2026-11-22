#!/bin/bash
# 把程序打包成 Clothesline.app，装进“应用程序”文件夹，然后重新打开它
# 用法：在项目文件夹里运行  ./build-app.sh
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
    <string>读取桌面上的截图和录屏，挂到晾衣绳上。</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# 关掉正在运行的旧版本，装进“应用程序”，再打开
pkill -x Clothesline 2>/dev/null || true
rm -rf /Applications/Clothesline.app
cp -R "$APP" /Applications/
open /Applications/Clothesline.app
echo "做好了，已经装到 /Applications/Clothesline.app 并打开"
