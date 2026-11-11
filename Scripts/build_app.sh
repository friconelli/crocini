#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Crocini"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"

echo "==> Building release binary (universale: Apple Silicon + Intel)"
cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
mkdir -p "$APP_DIR/Contents/Resources/Fonts"
cp "$ROOT_DIR"/Resources/Fonts/* "$APP_DIR/Contents/Resources/Fonts/"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    V="${VERSION#v}"
    echo "==> Version $V"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $V" "$APP_DIR/Contents/Info.plist"
fi
[[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]] && cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Code signing (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR"

ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/$APP_NAME")"
echo "==> Architetture: $ARCHS"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "ERRORE: il binario non è universale" >&2; exit 1; }

echo "==> Built: $APP_DIR"

if [[ "${1:-}" == "--zip" ]]; then
    echo "==> Creating Crocini.zip"
    (cd "$ROOT_DIR/.build" && rm -f "$APP_NAME.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")
fi

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
    echo "==> Installed: /Applications/$APP_NAME.app"
fi
