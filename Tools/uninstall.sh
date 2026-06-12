#!/bin/zsh
# Cleanly removes Vorssaint Utils and every piece of system state it created:
# the login item, TCC permissions, preferences, saved state and (if present)
# the password-free closed-lid sudoers rule. Leaves no dead entries behind.
set -uo pipefail

APP_NAME="Vorssaint Utils"
APP="/Applications/$APP_NAME.app"
BUNDLE="com.vorssaint.utils"
EXECUTABLE="$APP/Contents/MacOS/VorssaintUtils"

echo "▸ Quitting…"
pkill -x VorssaintUtils 2>/dev/null || true
sleep 0.5

# Detach from the system from inside the bundle, while it still exists:
# unregisters the login item (no BTM tombstone) and restores normal sleep.
if [[ -x "$EXECUTABLE" ]]; then
    echo "▸ Detaching login item and restoring sleep…"
    "$EXECUTABLE" --uninstall || true
fi

echo "▸ Resetting permissions (Accessibility, Screen Recording)…"
tccutil reset All "$BUNDLE" >/dev/null 2>&1 || true

echo "▸ Removing app, preferences and saved state…"
rm -rf "$APP"
defaults delete "$BUNDLE" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE.plist"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState"

RULE="/etc/sudoers.d/vorssaint-utils-clamshell"
if [[ -f "$RULE" ]]; then
    echo "▸ Removing closed-lid sudoers rule (asks for your admin password)…"
    osascript -e "do shell script \"rm -f $RULE\" with administrator privileges with prompt \"Vorssaint Utils uninstaller\"" || true
fi

echo "✓ Vorssaint Utils fully removed."
