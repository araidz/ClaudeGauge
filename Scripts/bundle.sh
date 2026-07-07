#!/bin/bash
# Builds ClaudeGauge.app from the SwiftPM release binary.
# Usage: Scripts/bundle.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="ClaudeGauge.app"
BID="io.github.araidz.claudegauge"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ClaudeGauge" "$APP/Contents/MacOS/ClaudeGauge"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudeGauge</string>
    <key>CFBundleDisplayName</key><string>ClaudeGauge</string>
    <key>CFBundleIdentifier</key><string>${BID}</string>
    <key>CFBundleExecutable</key><string>ClaudeGauge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: no Developer ID, but a stable identity for Keychain/WebKit.
codesign --force --sign - "$APP"
echo "built $APP ($VERSION)"
