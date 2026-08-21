#!/usr/bin/env bash
#
# Avisa quando o app instalado não corresponde mais ao código do repositório.
#
# Existe porque o atrito real não é rodar o bundle.sh — é lembrar de rodar. Sem
# aviso, dá para passar uma semana usando um binário de duas semanas atrás e
# concluir que uma correção não funcionou, quando ela nunca foi instalada.
#
# Avisa e para. Não instala sozinho de propósito: trocar o binário embaixo de
# uma sessão em andamento deixa o processo velho rodando enquanto o disco já tem
# outro app, e a próxima dúvida vira "qual dos dois está me respondendo".
#
# Uso: ./Scripts/update.sh [--schedule|--unschedule|--quiet]
#   --schedule    instala um agente launchd que roda esta checagem uma vez por dia
#   --unschedule  remove o agente
#   --quiet       só notifica; não escreve nada no terminal (usado pelo launchd)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeTokenCounter"
INSTALLED="/Applications/$APP_NAME.app"
LABEL="com.synqo.claudetokencounter.updatecheck"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

QUIET=false
case "${1:-}" in
    --schedule)
        mkdir -p "$(dirname "$AGENT")"
        # StartInterval em vez de StartCalendar: a checagem não precisa de hora
        # certa, e um intervalo roda também em máquina que estava dormindo na
        # hora marcada, o que num laptop é a maioria dos dias.
        cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$ROOT/Scripts/update.sh</string>
        <string>--quiet</string>
    </array>
    <key>StartInterval</key><integer>86400</integer>
    <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$AGENT"
        echo "==> Agendado: checagem diária ($AGENT)"
        exit 0
        ;;
    --unschedule)
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
        rm -f "$AGENT"
        echo "==> Agendamento removido"
        exit 0
        ;;
    --quiet) QUIET=true ;;
    "") ;;
    *) echo "erro: argumento desconhecido: $1" >&2; exit 1 ;;
esac

say() { $QUIET || echo "$@"; }

if [ ! -d "$INSTALLED" ]; then
    say "Nenhum $APP_NAME em /Applications. Instale com: ./Scripts/bundle.sh --install"
    exit 0
fi

# CFBundleVersion é "<versão>+<commit>". Só o commit interessa aqui: a versão de
# marketing não se move entre releases, então compará-la não detectaria nada.
INSTALLED_FULL="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
                  "$INSTALLED/Contents/Info.plist" 2>/dev/null || echo "")"
INSTALLED_BUILD="${INSTALLED_FULL#*+}"

HEAD_BUILD="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
    HEAD_BUILD="$HEAD_BUILD-dirty"
fi

# App anterior ao campo de build: o valor não tem "+", então INSTALLED_BUILD saiu
# igual à string inteira. Vale avisar, porque ele é necessariamente antigo.
if [ "$INSTALLED_FULL" = "$INSTALLED_BUILD" ]; then
    INSTALLED_BUILD="(desconhecido)"
fi

if [ "$INSTALLED_BUILD" = "$HEAD_BUILD" ]; then
    say "Em dia: $APP_NAME instalado é $HEAD_BUILD"
    exit 0
fi

say "Desatualizado: instalado $INSTALLED_BUILD, repositório $HEAD_BUILD"
say "Para atualizar: ./Scripts/bundle.sh --install"

# osascript porque não exige dependência nenhuma. O macOS atribui a notificação
# ao processo que a dispara, então o ícone não é o do app — o texto compensa
# dizendo o nome logo no título.
osascript -e "display notification \"Instalado $INSTALLED_BUILD, repositório $HEAD_BUILD\" with title \"$APP_NAME desatualizado\" subtitle \"Rode Scripts/bundle.sh --install\"" 2>/dev/null || true
