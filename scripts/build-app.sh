#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP_PATH="$PROJECT_ROOT/build/Parsec.app"
cd "$PROJECT_ROOT"
swift build -c "$CONFIGURATION"
BINARY_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/Parsec"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/Parsec"
cp Support/Info.plist "$APP_PATH/Contents/Info.plist"
cp -R Support/Resources/. "$APP_PATH/Contents/Resources/"
STATE_FILE="$HOME/Library/Application Support/Parsec/state.json"
SELECTED_ICON="$(/usr/bin/plutil -extract settings.appIconID raw -o - "$STATE_FILE" 2>/dev/null || echo default)"
SELECTED_ICON_PNG="Support/Resources/AppIcons/$SELECTED_ICON.png"
if [[ -f "$SELECTED_ICON_PNG" ]]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for SIZE in 16 32 64 128 256 512; do
        sips -z $SIZE $SIZE "$SELECTED_ICON_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
        sips -z $((SIZE * 2)) $((SIZE * 2)) "$SELECTED_ICON_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --options runtime --entitlements Support/Parsec.entitlements "$APP_PATH"
echo "$APP_PATH"
