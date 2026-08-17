# ClaudeTokenCounter

App de menu bar (macOS 26+) que lê os logs locais do Claude Code e mostra
consumo de tokens, risco de teto e valor equivalente em API.

## Build

Não requer Xcode — só Command Line Tools (Swift 6.4+).

```bash
./Scripts/test.sh     # suíte do core
./Scripts/bundle.sh   # monta dist/ClaudeTokenCounter.app
open dist/ClaudeTokenCounter.app
```

`swift test` puro **não funciona** neste toolchain: o Command Line Tools traz o
swift-testing mas não o conecta — o plugin de macros fica fora do plugin path e
`Testing.framework` / `lib_TestingInterop.dylib` ficam fora do rpath do bundle.
`Scripts/test.sh` injeta os três caminhos e repassa os argumentos, então
`./Scripts/test.sh --filter PricingTable` funciona normalmente.

Pela mesma razão o app não usa `@State`: no SDK do macOS 26 ele é uma macro do
SwiftUI e o plugin `SwiftUIMacros` só acompanha o Xcode. O redesenho vem do
`@Observable`, cujo plugin existe no CLT.

## Como funciona

Lê `~/.claude/projects/**/*.jsonl` (append-only, somente leitura) com parsing
incremental por offset de byte, deduplicando por `message.id` + `requestId`.
O cache em `~/Library/Application Support/ClaudeTokenCounter/` guarda os offsets
**e** os eventos, para o app abrir com histórico completo sem reparsear.

Duas métricas, respondendo perguntas diferentes:

**Risco** — quanto do plano já foi queimado no bloco de 5h e nos últimos 7 dias.
Os blocos são *derivados* da atividade, porque a Anthropic não persiste os
horários de reset localmente. O teto é *calibrado* pelo maior consumo já
observado, contando apenas janelas inteiramente no passado — a janela corrente
não pode definir o próprio denominador. Ambos são estimativas, e a UI diz isso.

**Valor** — tokens e $ equivalente de API hoje / semana / mês. Determinístico:
tabela de preços por modelo **e data** (o preço promocional do Sonnet 5 expira
em 2026-08-31), com as cinco dimensões cobradas separadamente — input, output,
cache write 5m, cache write 1h e cache read. Modelo desconhecido nunca vira
$0: o total é marcado como parcial e ganha sufixo `+`.

Detalhes em `docs/superpowers/specs/` e `docs/superpowers/plans/`.
