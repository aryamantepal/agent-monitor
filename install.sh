#!/bin/sh
# Installs (or updates) Agent Monitor from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/aryamantepal/agent-monitor/main/install.sh | sh
#
# Files fetched with curl aren't quarantined the way browser downloads are, so Gatekeeper
# doesn't block the app even though it isn't notarized.
set -eu

URL="https://github.com/aryamantepal/agent-monitor/releases/latest/download/AgentMonitor.zip"
APP="AgentMonitor.app"

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then
  echo "Agent Monitor needs macOS 14 or later (this Mac has $(sw_vers -productVersion))." >&2
  exit 1
fi

dest=/Applications
[ -w "$dest" ] || dest="$HOME/Applications"
mkdir -p "$dest"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading the latest release…"
curl -fsSL "$URL" -o "$tmp/AgentMonitor.zip"
ditto -x -k "$tmp/AgentMonitor.zip" "$tmp"

pkill -x AgentMonitor 2>/dev/null || true
rm -rf "${dest:?}/$APP"
mv "$tmp/$APP" "$dest/$APP"
# In case an earlier browser download left the flag behind.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

open "$dest/$APP"
echo "Installed to $dest/$APP. It's in your menu bar; tick \"Open at login\" in its menu to keep it there."
