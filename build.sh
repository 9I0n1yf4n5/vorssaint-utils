#!/bin/zsh
# Builds Vorssaint, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Vorssaint"
EXECUTABLE="Vorssaint"
TARGET="arm64-apple-macosx14.0"

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi

echo "▸ Compiling (release) against $(basename "$SDK")…"
rm -rf build
mkdir -p build
swiftc -O -target "$TARGET" -sdk "$SDK" \
    Sources/Vorssaint/**/*.swift \
    -o "build/$EXECUTABLE"

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset

echo "▸ Assembling and signing bundle…"
STAGE="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
iconutil -c icns build/AppIcon.iconset -o "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
xattr -cr "$STAGE"

# Sign with the stable self-signed identity when it's available. A constant
# signing identity gives the bundle a constant designated requirement, so macOS
# keeps granted permissions (Accessibility, Screen Recording) across updates —
# ad-hoc signing changes the cdhash every build and silently drops them.
# Falls back to ad-hoc on a fresh clone without the identity.
#
# The name stays "Vorssaint Utils Signing" deliberately: the released app's
# designated requirement is pinned to this certificate, so renaming it would
# drop every user's permissions. It is the one pre-rename name kept on purpose,
# and it is never shown outside the keychain.
SIGN_IDENTITY="Vorssaint Utils Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "  signing with stable identity: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" "$STAGE"
else
    echo "  signing ad-hoc (stable identity not installed — run Tools/setup-signing.sh)"
    codesign --force --sign - "$STAGE"
fi
codesign --verify --strict "$STAGE"

mkdir -p "build/stage"
rm -rf "build/stage/$APP_NAME.app"
ditto "$STAGE" "build/stage/$APP_NAME.app"
echo "✓ Bundle ready: build/stage/$APP_NAME.app"

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ Installing into /Applications…"
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    # Remove the pre-rename apps so two menu bar items never coexist. Same bundle
    # id, so macOS keeps the granted permissions for the new bundle.
    for legacy in "Vorss:Vorss" "Vorssaint Utils:VorssaintUtils"; do
        name="${legacy%%:*}"; proc="${legacy##*:}"
        if [[ -d "/Applications/$name.app" ]]; then
            pkill -x "$proc" 2>/dev/null || true
            rm -rf "/Applications/$name.app"
            echo "  (legacy $name.app removed)"
        fi
    done
    sleep 0.5
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$STAGE" "/Applications/$APP_NAME.app"
    echo "✓ Installed: /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
fi
