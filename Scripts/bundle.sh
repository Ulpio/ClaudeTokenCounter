#!/usr/bin/env bash
#
# Monta dist/ClaudeTokenCounter.app a partir do binário do SwiftPM.
# Não usa Xcode: o bundle é montado à mão.
#
# Uso: ./Scripts/bundle.sh [--install] [--adhoc]
#   --install  copia para /Applications
#   --adhoc    ignora qualquer identidade e assina ad-hoc

set -euo pipefail

INSTALL=false
ADHOC=false
while [ $# -gt 0 ]; do
    case "$1" in
        --install) INSTALL=true ;;
        --adhoc)   ADHOC=true ;;
        *) echo "erro: argumento desconhecido: $1" >&2; exit 1 ;;
    esac
    shift
done

APP_NAME="ClaudeTokenCounter"
BUNDLE_ID="com.synqo.claudetokencounter"
# Fonte única da versão. Com ela fixa aqui, uma tag v1.0.1 podia publicar um app
# que se diz 1.0.0 — e o único lugar onde isso apareceria seria em "Sobre" na
# máquina de quem instalou.
VERSION="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../VERSION")"

# CFBundleVersion carrega o commit; CFBundleShortVersionString fica com a versão
# de marketing. É a divisão que a Apple já define para os dois campos, e sem ela
# nenhum script consegue responder se o app instalado corresponde ao código:
# dois builds de commits diferentes se declaram "1.2.0" igual.
#
# O sufixo -dirty importa: com working tree suja o commit não descreve o binário,
# e declarar o hash limpo seria mentir sobre o que está rodando.
BUILD_ID="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." status --porcelain 2>/dev/null)" ]; then
    BUILD_ID="$BUILD_ID-dirty"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Universal em vez de nativo: o macOS 26 ainda roda em alguns Macs Intel, e um
# binário só arm64 não abre neles — sem mensagem que explique o porquê. Custa
# uns 45s a mais de build. As duas fatias saem com minos 26.0; o aviso de
# "x86_64 deprecated" que o toolchain emite é sobre o alvo dele, não sobre o
# binário gerado.
ARCHS=(--arch arm64 --arch x86_64)

echo "==> Building release binary (universal)"
swift build -c release --package-path "$ROOT" "${ARCHS[@]}"
BIN="$(swift build -c release --package-path "$ROOT" "${ARCHS[@]}" --show-bin-path)/$APP_NAME"

echo "==> Checking strings"
"$ROOT/Scripts/check-strings.sh" >/dev/null

echo "==> Generating icon"
"$ROOT/Scripts/icon.sh" >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Os .lproj vão para dentro do bundle montado à mão. Ficam fora de Sources/ de
# propósito: o SwiftPM reclama de arquivo solto num target que ele não sabe
# tratar, e aqui não há target que os declare — quem monta o bundle é este
# script.
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Claude Token Counter</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <!-- Inglês como base: quem estiver num idioma sem tradução recebe inglês,
         não português. O fallback tem que ser o que mais gente consegue ler. -->
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION+$BUILD_ID</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <!-- Agent app: vive só na menu bar, sem ícone no Dock. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Se uma das fatias sumir, o app deixa de abrir em metade dos Macs e nada aqui
# reclamaria — a checagem existe para transformar isso em erro de build.
for arch in arm64 x86_64; do
    lipo -archs "$APP/Contents/MacOS/$APP_NAME" | grep -qw "$arch" \
        || { echo "erro: binário sem a fatia $arch" >&2; exit 1; }
done

# A identidade estável existe por causa do Keychain, não do Gatekeeper. O
# requisito designado de um app ad-hoc é o hash do binário, então cada rebuild
# é um app diferente para o macOS e todo "Sempre Permitir" morre junto.
# Assinado com identidade, o requisito passa a ser o bundle ID mais o
# certificado, e sobrevive à recompilação.
#
# Releases saem ad-hoc de propósito, via --adhoc: a identidade não convence o
# Gatekeeper em máquina alheia — o spctl rejeita os dois igual — e embutiria o
# e-mail do desenvolvedor em todo binário publicado, junto no requisito
# designado. Custo de privacidade sem ganho de instalação.
#
# Sem identidade no chaveiro cai em ad-hoc, senão exigir certificado quebraria
# a promessa de buildar só com o Command Line Tools.
SIGN_ID="-"
SIGN_LABEL="ad-hoc"
if ! $ADHOC; then
    IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
                     | awk '/^ *[0-9]+\) [0-9A-F]+ /{print; exit}')"
    if [ -n "$IDENTITY_LINE" ]; then
        SIGN_ID="$(printf '%s' "$IDENTITY_LINE" | awk '{print $2}')"
        SIGN_LABEL="$(printf '%s' "$IDENTITY_LINE" | sed 's/.*"\(.*\)"/\1/')"
    fi
fi

echo "==> Signing ($SIGN_LABEL)"
codesign --force --deep --sign "$SIGN_ID" "$APP"

echo "==> Done: $APP"

# `--install` copia para /Applications. O launch at login precisa disso: o
# SMAppService registra um caminho, e um app que vive em dist/ tem o binário
# trocado a cada rebuild — o login item passaria a apontar para lixo.
if $INSTALL; then
    TARGET="/Applications/$APP_NAME.app"
    echo "==> Installing to $TARGET"
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    codesign --force --deep --sign "$SIGN_ID" "$TARGET"
    echo "==> Installed: $TARGET"
fi
