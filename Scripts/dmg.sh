#!/usr/bin/env bash
#
# Monta dist/ClaudeTokenCounter-<versão>.dmg a partir do .app já empacotado.
#
# Usa só `hdiutil`, que vem no macOS — nada de `create-dmg` do Homebrew. O DMG
# abre numa janela com o app e um atalho para /Applications, que é o ritual de
# instalação que o usuário de macOS já conhece.
#
# ATENÇÃO: o DMG melhora a instalação, não resolve o Gatekeeper. O app continua
# assinado ad-hoc, então a primeira abertura ainda exige o passo documentado no
# README. Notarizar é o que remove aquele diálogo, e exige conta paga da Apple.
#
# Uso: ./Scripts/dmg.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/ClaudeTokenCounter.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/ClaudeTokenCounter-$VERSION.dmg"
STAGE="$(mktemp -d)"

[ -d "$APP" ] || { echo "erro: $APP não existe — rode ./Scripts/bundle.sh antes" >&2; exit 1; }

# `ditto` em vez de `cp -R`: preserva symlinks internos do bundle e os metadados
# que a assinatura cobre. `cp -R` pode invalidar a assinatura.
ditto "$APP" "$STAGE/ClaudeTokenCounter.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "Claude Token Counter" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -quiet \
    "$DMG"

rm -rf "$STAGE"

# Confere que a assinatura sobreviveu ao empacotamento — um DMG que entrega um
# app com assinatura quebrada é pior que nenhum DMG: o macOS recusa de vez, e
# não só com o aviso de quarentena.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet
codesign -v "$MOUNT/ClaudeTokenCounter.app" 2>/dev/null \
    && echo "==> assinatura íntegra dentro do DMG" \
    || { echo "erro: assinatura quebrada dentro do DMG" >&2; hdiutil detach "$MOUNT" -quiet; exit 1; }
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT" 2>/dev/null || true

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
