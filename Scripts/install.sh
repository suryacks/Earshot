#!/usr/bin/env bash
# Installs Earshot.app into /Applications and the CLI into /usr/local/bin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Earshot.app"
CLI="$ROOT/build/earshot"

[ -d "$APP" ] || { echo "Not built yet. Run ./Scripts/build-app.sh first."; exit 1; }

echo "==> Installing Earshot.app to /Applications"
# Quit a running copy first, or the replace will fail silently.
osascript -e 'quit app "Earshot"' 2>/dev/null || true
sleep 1
rm -rf /Applications/Earshot.app
cp -R "$APP" /Applications/

if [ -f "$CLI" ]; then
    echo "==> Installing earshot CLI to /usr/local/bin (may ask for your password)"
    sudo mkdir -p /usr/local/bin
    sudo cp "$CLI" /usr/local/bin/earshot
fi

echo
echo "Done. Launching Earshot…"
open /Applications/Earshot.app
echo
echo "macOS will ask for Bluetooth permission the first time. Without it,"
echo "devices that are not connected cannot report their battery."
