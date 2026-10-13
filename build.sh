#!/bin/zsh
# Builds TweetBar.app. Usage: ./build.sh            -> build/TweetBar.app
#                             ./build.sh install    -> also copies it to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/TweetBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TweetBar "$APP/Contents/MacOS/TweetBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.alikhundmiri.tweetbar</string>
    <key>CFBundleName</key><string>TweetBar</string>
    <key>CFBundleDisplayName</key><string>TweetBar</string>
    <key>CFBundleExecutable</key><string>TweetBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x TweetBar 2>/dev/null || true
    rm -rf /Applications/TweetBar.app
    cp -R "$APP" /Applications/
    open /Applications/TweetBar.app
    echo "Installed to /Applications and launched."
fi
