#!/bin/sh
# Builds dist/AgentMonitor.app (ad-hoc signed) and dist/AgentMonitor.zip. Usage:
# scripts/bundle.sh [version]. With full Xcode the binary is universal (Apple Silicon + Intel);
# with only the Command Line Tools it is built for this Mac's architecture.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
ARCHS=""
if xcodebuild -version >/dev/null 2>&1; then ARCHS="--arch arm64 --arch x86_64"; fi
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/AgentMonitor"
APP=dist/AgentMonitor.app
rm -rf dist && mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AgentMonitor"
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
echo "built $APP [$(lipo -archs "$APP/Contents/MacOS/AgentMonitor")] ($(du -sh "$APP" | cut -f1)) and dist/AgentMonitor.zip"
