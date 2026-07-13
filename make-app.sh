#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Mark-It-Down"
BUNDLE="$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)
echo "==> Binary: $BIN_PATH/MarkItDown"

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/MarkItDown" "$BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist.tmpl "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Done: $BUNDLE"
echo "To run: open '$BUNDLE'  (or drag to /Applications)"