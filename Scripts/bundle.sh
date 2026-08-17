#!/usr/bin/env bash
#
# Monta dist/ClaudeTokenCounter.app a partir do binário do SwiftPM.
# Não usa Xcode: o bundle é montado à mão e assinado ad-hoc.

set -euo pipefail

APP_NAME="ClaudeTokenCounter"
BUNDLE_ID="com.synqo.claudetokencounter"
VERSION="1.0.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT"
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Claude Token Counter</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <!-- Agent app: vive só na menu bar, sem ícone no Dock. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"

# `--install` copia para /Applications. O launch at login precisa disso: o
# SMAppService registra um caminho, e um app que vive em dist/ tem o binário
# trocado a cada rebuild — o login item passaria a apontar para lixo.
if [ "${1:-}" = "--install" ]; then
    TARGET="/Applications/$APP_NAME.app"
    echo "==> Installing to $TARGET"
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    codesign --force --deep --sign - "$TARGET"
    echo "==> Installed: $TARGET"
fi
