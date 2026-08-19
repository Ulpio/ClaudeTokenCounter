#!/usr/bin/env bash
#
# Corta uma release: testa, empacota universal, monta o DMG e publica no GitHub.
#
# Existe porque cortar release à mão é como se publica artefato velho: bastou
# esquecer de rodar o bundle depois de mudar o ícone, e o DMG da release fica
# sendo o da versão anterior, sem nada indicar isso.
#
# Uso: ./Scripts/release.sh [--dry-run]
#
# A versão vem do arquivo VERSION. Para subir de versão, edite aquele arquivo —
# não há segundo lugar para manter em sincronia.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
TAG="v$VERSION"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

echo "==> Release $TAG${DRY_RUN:+ (simulação)}"

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "erro: há mudanças não commitadas — a release sairia de um estado que" >&2
    echo "      ninguém consegue reproduzir depois" >&2
    exit 1
fi

if git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "erro: a tag $TAG já existe. Suba a versão no arquivo VERSION." >&2
    exit 1
fi

echo "==> Testes"
"$ROOT/Scripts/test.sh" >/dev/null

echo "==> Empacotando"
"$ROOT/Scripts/bundle.sh" >/dev/null
"$ROOT/Scripts/dmg.sh" >/dev/null

APP="$DIST/ClaudeTokenCounter.app"
DMG="$DIST/ClaudeTokenCounter-$VERSION.dmg"
ZIP="$DIST/ClaudeTokenCounter-$VERSION-universal.zip"

# A versão que o app declara precisa bater com a tag. Sem esta checagem, o
# arquivo VERSION vira só mais um lugar para esquecer de atualizar.
BUNDLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUNDLED" = "$VERSION" ] || {
    echo "erro: o app se diz $BUNDLED, mas a release é $VERSION" >&2; exit 1; }

for arch in arm64 x86_64; do
    lipo -archs "$APP/Contents/MacOS/ClaudeTokenCounter" | grep -qw "$arch" \
        || { echo "erro: o binário publicado não tem a fatia $arch" >&2; exit 1; }
done

codesign -v "$APP" || { echo "erro: assinatura inválida" >&2; exit 1; }

rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"

echo "==> Artefatos"
echo "    $(basename "$DMG") ($(du -h "$DMG" | cut -f1))"
echo "    $(basename "$ZIP") ($(du -h "$ZIP" | cut -f1))"

if $DRY_RUN; then
    echo "==> Simulação: nada foi marcado nem publicado."
    exit 0
fi

echo "==> Publicando"
git -C "$ROOT" tag -a "$TAG" -m "$TAG"
git -C "$ROOT" push origin "$TAG"
# `--generate-notes` em vez de `--notes-file -`: aquele lê da entrada padrão e
# trava um script que ninguém está observando. As notas saem dos commits e podem
# ser editadas no GitHub depois.
gh release create "$TAG" "$DMG" "$ZIP" \
    --repo Ulpio/ClaudeTokenCounter \
    --title "$TAG" \
    --generate-notes

echo "==> Done: https://github.com/Ulpio/ClaudeTokenCounter/releases/tag/$TAG"
