#!/bin/zsh
# Packages the built app into a styled, distributable DMG
# (dist/Vorssaint-<version>.dmg): a window with the app icon, an arrow and
# the Applications folder for drag-and-drop install. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Vorssaint"
APP="build/stage/$APP_NAME.app"
VOLUME="$APP_NAME"

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found — run ./build.sh first" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/Vorssaint-$VERSION.dmg"

echo "▸ Rendering installer background…"
swift Tools/MakeDMGBackground.swift build/dmg-background.png

echo "▸ Staging DMG contents…"
STAGING="$(mktemp -d)"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp build/dmg-background.png "$STAGING/.background/background.png"

echo "▸ Creating writable image…"
WORK="$(mktemp -d)"
RW="$WORK/rw.dmg"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov -quiet "$RW"
hdiutil attach "$RW" -nobrowse -quiet
MOUNT="/Volumes/$VOLUME"

echo "▸ Arranging window (icons, arrow, background)…"
# Finder automation lays out the window; best-effort so a headless hiccup never
# fails the release (the DMG is still valid, just unstyled that once).
osascript <<APPLESCRIPT || echo "  (window styling skipped)"
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set theOptions to the icon view options of container window
        set arrangement of theOptions to not arranged
        set icon size of theOptions to 128
        set text size of theOptions to 13
        set background picture of theOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet

echo "▸ Compressing…"
mkdir -p dist
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet

rm -rf "$STAGING" "$WORK"
echo "✓ DMG ready: $OUT"
