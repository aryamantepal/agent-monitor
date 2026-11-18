#!/bin/sh
# Builds dist/AgentMonitor.app (ad-hoc signed) and dist/AgentMonitor.zip. Needs only the
# Command Line Tools. Usage: scripts/bundle.sh [version]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
swift build -c release
APP=dist/AgentMonitor.app
rm -rf dist && mkdir -p "$APP/Contents/MacOS"
cp .build/release/AgentMonitor "$APP/Contents/MacOS/AgentMonitor"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Monitor</string>
  <key>CFBundleDisplayName</key><string>Agent Monitor</string>
  <key>CFBundleIdentifier</key><string>io.github.aryamantepal.agent-monitor</string>
  <key>CFBundleExecutable</key><string>AgentMonitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
(cd dist && ditto -c -k --keepParent AgentMonitor.app AgentMonitor.zip)
echo "built $APP ($(du -sh "$APP" | cut -f1)) and dist/AgentMonitor.zip"
