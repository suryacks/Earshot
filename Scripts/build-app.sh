#!/usr/bin/env bash
# Builds Earshot.app and the `earshot` CLI.
#
# A real .app bundle is not optional: macOS attaches Bluetooth and Automation
# permissions to a bundle identifier, so a bare executable can never hold them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Earshot.app"
VERSION="$(grep -m1 'let version = ' "$ROOT/Sources/EarshotCLI/main.swift" | sed 's/.*"\(.*\)".*/\1/')"

echo "==> Building Earshot $VERSION ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG" --product EarshotApp
swift build -c "$CONFIG" --product earshot

BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The executable is named EarshotApp in the build directory so it cannot
# collide with the lowercase `earshot` CLI on a case-insensitive filesystem.
# Inside the bundle it takes the proper name.
cp "$BIN/EarshotApp" "$APP/Contents/MacOS/Earshot"
cp "$BIN/earshot" "$ROOT/build/earshot"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Earshot</string>
    <key>CFBundleDisplayName</key><string>Earshot</string>
    <key>CFBundleIdentifier</key><string>app.earshot.Earshot</string>
    <key>CFBundleExecutable</key><string>Earshot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu bar agent: no Dock icon, no main window. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Earshot reads the battery level your AirPods broadcast over Bluetooth.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Earshot reads the battery level your AirPods broadcast over Bluetooth.</string>
    <!-- Only used for Now Playing, and only for Music and Spotify. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>Earshot asks Music or Spotify what is playing so it can show it.</string>
    <!-- Required. Reading Focus status without this key is an instant TCC kill,
         not a denied request: the app is terminated with SIGABRT on launch. -->
    <key>NSFocusStatusUsageDescription</key>
    <string>Earshot checks whether a Focus is active so it can stay quiet instead of sliding out the island.</string>
    <!-- earshot:// URLs, so Shortcuts can drive the app via "Open URL". -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>app.earshot.Earshot</string>
            <key>CFBundleURLSchemes</key><array><string>earshot</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signing is enough for local use and for the TCC prompts to appear.
# Distribution needs a real Developer ID; see README.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo
echo "Built:"
echo "  $APP"
echo "  $ROOT/build/earshot"
echo
echo "Install with:  ./Scripts/install.sh"
