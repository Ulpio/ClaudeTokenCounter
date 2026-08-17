#!/usr/bin/env bash
#
# Roda a suíte do core.
#
# Command Line Tools traz o swift-testing mas não o conecta ao `swift test`:
# o plugin de macros não está no plugin path padrão e as bibliotecas de runtime
# não entram no rpath do bundle de teste. O toolchain do Xcode faz isso sozinho,
# então os flags abaixo só são adicionados quando os diretórios do CLT existem.
#
# Uso: ./Scripts/test.sh [args extras do swift test]
#   ./Scripts/test.sh --filter PricingTable

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="$(xcode-select -p)"

ARGS=()
PLUGINS="$DEV/usr/lib/swift/host/plugins/testing"
FRAMEWORKS="$DEV/Library/Developer/Frameworks"
INTEROP="$DEV/Library/Developer/usr/lib"

[ -d "$PLUGINS" ]    && ARGS+=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
[ -d "$FRAMEWORKS" ] && ARGS+=(-Xlinker -rpath -Xlinker "$FRAMEWORKS")
[ -d "$INTEROP" ]    && ARGS+=(-Xlinker -rpath -Xlinker "$INTEROP")

# ${ARGS[@]+...} protege contra array vazio sob `set -u` no bash 3.2 do macOS.
exec swift test --package-path "$ROOT" ${ARGS[@]+"${ARGS[@]}"} "$@"
