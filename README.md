![Claude Token Counter](docs/art/banner.png)

# Claude Token Counter

App de menu bar para macOS que mostra quanto do seu plano Claude Code já foi
consumido — e, principalmente, **de onde esse número veio**.

```
◐ 81%   ← quanto da janela de 5h já foi gasto, ao vivo
```

## Por que ele existe

O Claude Code guarda em `~/.claude.json` um cache com o seu consumo. Esse cache
**só se atualiza quando o Claude Code roda**.

Numa medição real feita durante o desenvolvimento, o cache estava **18 horas
atrasado**: dizia 35% de uso na janela de 5 horas quando o valor verdadeiro era
**81%**. Um app que lesse só o cache diria que você tem folga de sobra
justamente quando você está prestes a bater o teto.

Este app busca os números ao vivo, e quando não consegue, **diz que não
conseguiu** em vez de mostrar um valor velho com cara de fresco.

## Três fontes, e a tela sempre diz qual está em uso

| Fonte | Quando | O que a tela mostra |
|---|---|---|
| **Ao vivo** | Toggle ligado, credencial válida | `ao vivo` |
| **Cache do Claude Code** | Toggle desligado, ou busca falhou | `cache do Claude Code · há 20m`, ou **`cache defasada · há 18h`** em amarelo quando passa de 1h |
| **Derivado do histórico** | Sem cache — instalação nova | `estimado do seu histórico` |

Um número sem procedência é um número em que não dá para confiar. Cada estado
de falha tem frase própria, porque a saída é diferente: credencial expirada
pede que você rode o Claude Code; falha de rede pede que você espere.

## O que ele mostra

- **Sessão (5h) e semanal**, com horário de reset e contagem regressiva
- **Janelas semanais por modelo**, quando a sua conta tem alguma com uso
- **Valor equivalente em API** — tokens e US$ de hoje, da semana e do mês,
  com preço por modelo *e por data*; modelo sem preço conhecido nunca vira
  US$ 0,00, o total é marcado como parcial
- **Múltiplo de retorno** do plano: quanto o consumo do mês cobre a mensalidade

## Instalação

### DMG

Baixe o `.dmg` da [última release](../../releases/latest), abra, e arraste o app
para a pasta `Applications` que aparece na janela.

O app é assinado ad-hoc, não notarizado pela Apple. Na primeira abertura o
macOS vai bloqueá-lo — o DMG deixa a instalação familiar, mas não muda isso.
Duas formas de liberar:

```bash
xattr -d com.apple.quarantine /Applications/ClaudeTokenCounter.app
```

Ou, sem terminal: tente abrir, deixe o macOS bloquear, e vá em **Ajustes do
Sistema → Privacidade e Segurança**; role até o aviso e clique em **Abrir Assim
Mesmo**.

O truque antigo de clicar com o botão direito e escolher **Abrir** não funciona
mais: a Apple removeu esse atalho no macOS 15, e este app exige macOS 26.

Isso não é um contorno de segurança — é o que o macOS pede para qualquer app
fora da App Store sem conta paga de desenvolvedor. O código está todo aqui para
você conferir, e compilar você mesmo leva menos de dez segundos.

### Do código-fonte

Não precisa de Xcode — só Command Line Tools com Swift 6.4+.

```bash
git clone https://github.com/Ulpio/ClaudeTokenCounter.git
cd ClaudeTokenCounter
./Scripts/bundle.sh --install    # monta e copia para /Applications
```

Compilar localmente também evita o passo do Gatekeeper: o `.app` que você mesmo
montou não chega com a marca de quarentena.

Requer **macOS 26+**. O binário publicado é universal — roda em Apple Silicon e
nos Macs Intel que ainda alcançam o macOS 26.

## Privacidade

O app roda inteiro na sua máquina. Não há servidor, telemetria, nem analytics.

**Leitura local:** `~/.claude/projects/**/*.jsonl` (somente leitura, para tokens
e custo) e `~/.claude.json` (o cache de uso).

**Keychain:** o item `Claude Code-credentials`, que pertence ao Claude Code.
Por padrão o app lê **apenas** o campo `rateLimitTier`, para detectar seu plano.

O `accessToken` só é lido quando você liga **Ajustes → Números de uso → Buscar
ao vivo**, e mesmo então por um único ponto do código, atrás de uma checagem
do toggle. Com ele desligado, o campo não chega a ser extraído.

O `refreshToken` **não tem leitor nenhum, em lugar nenhum do app** — e a
garantia é estrutural, não uma promessa: o tipo `ClaudeCredentials` não tem
campo onde guardá-lo. O app nunca renova OAuth, porque regravar o item de
keychain do Claude Code pode invalidar a sessão dele.

**Rede:** uma única chamada, `GET https://api.anthropic.com/api/oauth/usage`,
a cada 5 minutos, e só com a busca ao vivo ligada. É a mesma chamada que o
próprio Claude Code faz.

## Desenvolvimento

```bash
./Scripts/test.sh     # suíte do core (156 testes)
./Scripts/icon.sh     # desenha dist/AppIcon.icns e a arte do instalador
./Scripts/bundle.sh   # monta dist/ClaudeTokenCounter.app
./Scripts/dmg.sh      # monta dist/ClaudeTokenCounter-<versão>.dmg
```

**`swift test` puro não funciona** neste toolchain: o Command Line Tools traz o
swift-testing mas não o conecta — o plugin de macros fica fora do plugin path e
`Testing.framework` / `lib_TestingInterop.dylib` ficam fora do rpath do bundle
de teste. `Scripts/test.sh` injeta os três caminhos e repassa os argumentos,
então `./Scripts/test.sh --filter PricingTable` funciona normalmente.

Pela mesma razão o app não usa `@State`: no SDK do macOS 26 ele é uma macro do
SwiftUI e o plugin `SwiftUIMacros` só acompanha o Xcode. O redesenho vem do
`@Observable`, cujo plugin existe no CLT.

### Arquitetura

Dois alvos. `CCUsageCore` não importa SwiftUI — toda a lógica é testável sem
instanciar janela.

A marca é um anel que se enche conforme a janela de 5h avança, e existe uma vez
só: `GaugeGeometry`, no core, constrói o path. A barra de menu o desenha com a
fração ao vivo, e `Scripts/icon.swift` — compilado junto com aquele mesmo
arquivo — o congela em 62% para o ícone do app. Não é economia de código: é o
que impede que o ícone e a barra virem dois desenhos parecidos que alguém
precisa lembrar de manter em sincronia.

A resposta ao vivo da API e o cache em `~/.claude.json` são **o mesmo payload**:
o segundo é uma cópia gravada do primeiro. Por isso existe um decoder só
(`UsageReportDecoder`) alimentado por duas origens, e uma função pura
(`UsageSourcePolicy`) escolhe entre elas. Nada a jusante sabe de onde veio o
número — exceto a linha da UI que existe para dizer.

O contrato lido é o array `limits[]`, não as chaves de topo do payload: aquelas
são codinomes internos que giram a cada ciclo de produto, e é `limits[]` que
traz as janelas por modelo com nome de exibição.

Decisões de projeto estão em `docs/superpowers/specs/` e `docs/superpowers/plans/`.

## Créditos

Inspirado no [CodexBar](https://github.com/steipete/CodexBar), de Peter
Steinberger, que mostrou que o endpoint de uso existia e valia a pena.

## Licença

MIT — veja [LICENSE](LICENSE).
