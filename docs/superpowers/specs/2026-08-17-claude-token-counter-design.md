# ClaudeTokenCounter — Design

**Data:** 2026-08-17
**Status:** Aprovado para planejamento
**Plataforma:** macOS 27 (Tahoe+), Apple Silicon

---

## 1. Objetivo

App nativo de menu bar que mostra, em tempo real, o consumo do Claude Code na máquina local: quanto do plano já foi queimado na janela atual, quando ela reseta, e qual o valor equivalente em API dos tokens consumidos hoje / na semana / no mês.

Duas perguntas distintas, duas seções na UI:

| Seção | Pergunta que responde | Métrica |
|---|---|---|
| **Risco** | "Vou bater o teto no meio de uma task?" | % do bloco de 5h, % da janela de 7 dias, tempo até o reset |
| **Valor** | "Quanto meu Max está me devolvendo?" | Tokens e $ equivalente em API — hoje, semana, mês |

### Não-objetivos (v1)

Notificações, gráficos históricos, breakdown por projeto e shell no notch ficam fora. A arquitetura os acomoda sem reescrita (§4, §9), mas nenhum entra na v1.

---

## 2. Decisões tomadas

| # | Decisão | Escolha |
|---|---|---|
| D1 | Form factor | `MenuBarExtra` na v1; notch como segunda shell sobre o mesmo core |
| D2 | Semântica de "custo" | Ambos — $ equivalente de API **e** % do plano |
| D3 | Escopo v1 | Só o core |
| D4 | Toolchain | SwiftPM + Command Line Tools; **sem Xcode** (verificado por compilação) |

---

## 3. Restrições descobertas na exploração

Levantadas contra a máquina real antes do design; cada uma moldou uma decisão.

**R1 — Os dados de uso existem e são completos.** Cada linha `type: "assistant"` em `~/.claude/projects/**/*.jsonl` carrega `message.usage` com `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, o split `cache_creation.ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens`, `cache_read_input_tokens`, `message.model`, `message.usage.speed`, `timestamp` (ISO-8601 UTC), `requestId`, `message.id`, `sessionId`, `cwd` e `isSidechain`.

**R2 — Os horários de reset NÃO existem localmente.** Busca por `rateLimits`, `resetsAt`, `unifiedRateLimit` e caches de limites em `~/.claude/` não retornou nada persistido. A janela de 5h precisa ser **derivada** (§7.1). É estimativa, e a UI diz isso.

**R3 — O plano é Max.** `subscriptionType: max` no keychain. Não há cobrança por token: o "custo" é valor equivalente de API, e o "% do plano" tem denominador desconhecido (§7.3).

**R4 — Volume é pequeno, o texto é grande.** ~36.000 eventos de uso em 252 MB / 309 arquivos. Em memória isso é ~1 MB; o custo real é varrer o texto (§6.2).

**R5 — Sem Xcode, com Liquid Glass.** Só Command Line Tools (Swift 6.4), mas em macOS 27. Verificado por compilação: `MenuBarExtra`, `.menuBarExtraStyle(.window)` e `.glassEffect(_:in:)` resolvem com `swiftc -parse-as-library -target arm64-apple-macos26.0`.

**R6 — Sem barreira de permissão.** `~/.claude` não é diretório protegido por TCC. Sem entitlements, sem prompt.

---

## 4. Arquitetura

Dois alvos no mesmo package. `CCUsageCore` não importa SwiftUI — toda a lógica é testável via CLI, sem rodar a UI.

```
┌─ ClaudeTokenCounter (executable, UI) ───────────────┐
│  MenuBarShell ✅          NotchShell (futuro)       │
└──────────────┬───────────────────┬──────────────────┘
               └─────────┬─────────┘
┌────────────────────────▼────────────────────────────┐
│  CCUsageCore (library, zero UI)                     │
│                                                     │
│  UsageStore  ──emits──▶  UsageSnapshot              │
│      ▲                                              │
│      ├── Aggregator  (blocos 5h · períodos · teto)  │
│      ├── PricingTable (modelo × dimensão × data)    │
│      ├── JSONLParser + ParseCache                   │
│      ├── ProjectScanner                             │
│      └── FSWatcher                                  │
└─────────────────────────────────────────────────────┘
```

**A regra que torna o notch barato depois:** `UsageStore` expõe um `UsageSnapshot` com valores já calculados e formatados. Nenhuma shell sabe o que é um JSONL, um bloco de 5h ou um preço. Trocar `MenuBarExtra` por um `NSPanel` posicionado no notch não toca em nada abaixo da linha do store.

### Layout de arquivos

```
Package.swift
Sources/
  CCUsageCore/
    Models/            UsageEvent.swift  UsageSnapshot.swift  ModelID.swift
    Parsing/           ProjectScanner.swift  JSONLParser.swift  ParseCache.swift
    Aggregation/       BlockBuilder.swift  PeriodAggregator.swift  CeilingCalibrator.swift
    Pricing/           PricingTable.swift  ModelAlias.swift
    Watch/             FSWatcher.swift
    UsageStore.swift
  ClaudeTokenCounter/
    App.swift  MenuBarLabel.swift
    Panel/             UsagePanel.swift  RiskSection.swift  ValueSection.swift
    Settings/          SettingsView.swift
Tests/CCUsageCoreTests/
Scripts/bundle.sh
```

---

## 5. Modelo de dados

```swift
struct UsageEvent {
    let timestamp: Date
    let model: ModelID           // enum com caso .unknown(String)
    let isFast: Bool             // message.usage.speed == "fast"
    let input: UInt32
    let output: UInt32
    let cacheWrite5m: UInt32
    let cacheWrite1h: UInt32
    let cacheRead: UInt32
    let dedupeKey: String         // "\(messageID):\(requestID)"
}
```

~32 bytes por evento. 36k eventos ≈ 1,2 MB — cabe todo em memória, sem banco.

`cache_creation_input_tokens` (total) é ignorado em favor do split `ephemeral_5m` + `ephemeral_1h`, porque eles têm preços diferentes. Se o split estiver ausente (versões antigas do Claude Code), o total cai em `cacheWrite5m` — o TTL padrão.

---

## 6. Ingestão

### 6.1 Descoberta

`ProjectScanner` varre `~/.claude/projects/**/*.jsonl`. Arquivos com `mtime` anterior ao início da janela de interesse são descartados.

**Isso é correto, não apenas otimização:** o JSONL é append-only, então nenhum arquivo pode conter um evento mais recente que seu próprio `mtime`. Descartar por `mtime` nunca perde dado. (Vale notar que na máquina atual os 309 arquivos estão todos dentro de 40 dias, então o ganho aqui é ~0 — o filtro existe pela correção e por máquinas com histórico mais antigo.)

### 6.2 Parsing

`JSONLParser` lê linha a linha e só passa pelo `JSONDecoder` as linhas que contêm a substring `"usage"`. A maioria absoluta das linhas é user/tool/system e nunca chega ao decoder. Esse pré-filtro em bytes é a diferença entre segundos e dezenas de segundos no primeiro launch.

Dois filtros que mudam o número final:

- **Dedup por `message.id` + `requestId`.** Resume e fork de sessão reescrevem a mesma mensagem assistant em arquivos diferentes. Sem dedup, tokens são contados em duplicidade.
- **Descarte de `model: "<synthetic>"`.** Placeholders de erro de API, sem consumo real (64 ocorrências no histórico atual).

`isSidechain: true` (subagentes) **é contado** — consome tokens de verdade.

### 6.3 Cache incremental

`ParseCache` persiste em `~/Library/Application Support/ClaudeTokenCounter/cache.json`:

```
[path: { size, mtimeNs, byteOffset, eventCount }]
```

Na releitura, `seek(byteOffset)` e parse só do delta. Se `size < byteOffset`, o arquivo foi truncado ou reescrito → reparse total dele. Se o cache não abrir ou não decodificar, descarta e reparseia tudo.

### 6.4 Watching

`FSWatcher` usa `DispatchSource.makeFileSystemObjectSource` no diretório `projects/`, com debounce de 2 s. O Claude Code escreve continuamente durante uma sessão; sem debounce o app reparsearia a cada token.

---

## 7. Agregação

### 7.1 Bloco de 5 horas

Algoritmo (eventos ordenados por `timestamp`):

1. Abre bloco novo quando: não há bloco anterior, **ou** `evento > inícioDoBloco + 5h`, **ou** `evento > últimoEventoDoBloco + 5h` (gap).
2. `inícioDoBloco` = timestamp do primeiro evento arredondado para baixo à hora cheia.
3. `resetAt` = `inícioDoBloco + 5h`.
4. Bloco **ativo** = aquele cujo intervalo contém `now`.

Se não há bloco ativo (usuário parado há mais de 5h), a UI mostra "nenhuma sessão ativa" — não um bloco a 0%, que sugeriria falsamente que o relógio está correndo.

**Honestidade obrigatória:** por R2, isso é derivação, não o número oficial do `/usage`. A UI marca o bloco como estimativa. O app não apresenta um número derivado com a mesma autoridade de um número oficial.

### 7.2 Períodos

`Calendar.current` no timezone local:

- **Hoje** — dia de calendário local.
- **Semana** — semana de calendário (segunda a domingo), para a seção Valor.
- **Mês** — mês de calendário.
- **Últimos 7 dias** — janela rolling, usada **só** no gauge de risco semanal e rotulada como "últimos 7 dias".

As duas definições de semana coexistem porque respondem a perguntas diferentes; a diferença é resolvida por rótulo explícito, nunca por sobrecarga do mesmo termo.

### 7.3 Teto do plano (denominador dos %)

A Anthropic não publica os limites do Max. `CeilingCalibrator` deriva:

```
teto5h      = max(total de qualquer bloco de 5h COMPLETO nos últimos 90 dias)
tetoSemanal = max(total de qualquer janela de 7 dias INTEIRAMENTE PASSADA nos últimos 90 dias)
```

**A janela corrente nunca calibra o próprio teto.** Descoberto na verificação contra dados reais: incluí-la deixava o gauge semanal cravado em 100%, porque com uso em alta a janela atual é sempre o maior valor já visto — a métrica definia o próprio denominador e não informava nada. Excluí-la é o mesmo princípio que já valia para o bloco de 5h ("só blocos completos"), e o teto ainda sobe sozinho: a semana de hoje entra na calibração assim que vira passado.

Quando o consumo supera o teto, a **barra** satura em 100% mas o **número** mostra a razão real (ex.: "140%") — é justamente aí que ele informa algo, e saturar o texto esconderia que o usuário está em território inédito.

Com override manual nas settings.

Os ~36k eventos de histórico dão base suficiente para calibrar já no primeiro launch. O % aparece na UI com marca de estimativa.

---

## 8. Pricing

### 8.1 Tabela base (USD por milhão de tokens)

Fonte: skill `claude-api` (cache 2026-06-24), verificada em 2026-08-17.

| Modelo | Input | Output |
|---|---:|---:|
| `claude-opus-5` | 5,00 | 25,00 |
| `claude-opus-5` **fast mode** | 10,00 | 50,00 |
| `claude-opus-4-8` / `4-7` / `4-6` / `4-5` | 5,00 | 25,00 |
| `claude-sonnet-5` | 3,00 | 15,00 |
| `claude-sonnet-4-6` / `4-5` | 3,00 | 15,00 |
| `claude-haiku-4-5` | 1,00 | 5,00 |
| `claude-fable-5` | 10,00 | 50,00 |

### 8.2 Dimensões de cache — derivadas do input

Multiplicadores fixos, iguais para todo modelo:

| Dimensão | Multiplicador |
|---|---:|
| cache write 5m | 1,25 × input |
| cache write 1h | 2,00 × input |
| cache read | 0,10 × input |

Resolvidas (USD/MTok):

| Modelo | write 5m | write 1h | read |
|---|---:|---:|---:|
| Opus (5/4.x) | 6,25 | 10,00 | 0,50 |
| Opus 5 fast | 12,50 | 20,00 | 1,00 |
| Sonnet (5/4.x) | 3,75 | 6,00 | 0,30 |
| Haiku 4.5 | 1,25 | 2,00 | 0,10 |
| Fable 5 | 12,50 | 20,00 | 1,00 |

### 8.3 Preço com validade — Sonnet 5

**Sonnet 5 está em preço introdutório de $2,00 / $10,00 até 2026-08-31**, voltando a $3,00 / $15,00 em 2026-09-01. A tabela é portanto indexada por **(modelo, data do evento)**, não só por modelo:

```swift
struct PriceWindow {
    let effectiveFrom: Date
    let effectiveUntil: Date?     // nil = vigente
    let input: Decimal
    let output: Decimal
}
```

Um evento de 20 de agosto é precificado a $2/$10; um de 5 de setembro, a $3/$15. Sem isso, o total do mês de setembro fica errado — e um app de custo que mente é pior que um que não responde.

### 8.4 Resolução de alias

O histórico contém IDs canônicos (`claude-opus-5`) e aliases crus (`"sonnet"`, `"opus"`, `"haiku"` — 203 ocorrências). `ModelAlias` mapeia alias → modelo canônico vigente na data do evento.

### 8.5 Modelo desconhecido

Um modelo que não resolve **não vira $0 silencioso**. Os tokens são contados normalmente; o custo daquele evento é `nil`; a agregação marca o período como `costIsPartial = true`; a UI mostra o valor com um indicador de incompleto e o nome do modelo não reconhecido.

Zero silencioso subestimaria o custo — exatamente o erro que um app de custo não pode cometer.

---

## 9. UI

`MenuBarExtra` com `.menuBarExtraStyle(.window)`, deployment target macOS 26.

**Na barra:** ícone + % do bloco de 5h. Cor evolui `secondary → orange → red` conforme o percentual sobe. Sem bloco ativo, só o ícone em `secondary`.

**No painel:** `GlassEffectContainer` envolvendo as duas seções aprovadas — **Risco** em cima (bloco 5h com barra e reset, janela de 7 dias, projeção de burn rate), **Valor** embaixo (hoje / semana / mês em tokens e $, com o multiplicador sobre o preço do plano). Cada superfície usa `.glassEffect(.regular, in: .rect(cornerRadius:))`.

**Settings:** plano (Pro / Max 5x / Max 20x, para o denominador do multiplicador de valor), override manual dos tetos, e toggle do launch-at-login.

---

## 10. Build e distribuição

Sem Xcode. `Scripts/bundle.sh`:

1. `swift build -c release --arch arm64`
2. Monta `ClaudeTokenCounter.app/Contents/{MacOS,Resources}`
3. Escreve `Info.plist` com `LSUIElement = true` (sem ícone no Dock), `CFBundleIdentifier`, `LSMinimumSystemVersion = 26.0`
4. `codesign -s - --force --deep` (ad-hoc, roda localmente sem notarização)

---

## 11. Tratamento de erros

| Situação | Comportamento |
|---|---|
| Linha JSON malformada | Pula, incrementa `skippedLines`, segue. Nunca derruba o parse. |
| `~/.claude/projects` ausente | Empty state explícito: "Nenhum dado do Claude Code encontrado" |
| Arquivo removido durante o parse | Ignora, remove do cache |
| Cache corrompido | Descarta, reparse completo |
| Modelo desconhecido | §8.5 — tokens contam, custo fica parcial e sinalizado |
| Sem bloco ativo | "Nenhuma sessão ativa" (≠ bloco a 0%) |

---

## 12. Testes

TDD com `swift-testing`, tudo contra `CCUsageCore` — sem instanciar UI.

**Parsing:** fixture com linhas válidas, malformadas, `<synthetic>` e duplicadas → só os eventos esperados sobrevivem; dedup por `(messageID, requestID)` remove a duplicata; `isSidechain` é contado; split de cache ausente cai em `cacheWrite5m`.

**Incremental:** append em fixture → só o delta é parseado; truncate → reparse total; cache corrompido → reparse total.

**Blocos:** sequência conhecida → fronteiras esperadas; gap > 5h abre bloco novo; início arredonda à hora cheia; sem evento recente → nenhum bloco ativo.

**Pricing:** contagens conhecidas × modelo conhecido → custo esperado nas 5 dimensões; alias resolve; modelo desconhecido → `nil` e período marcado parcial; **evento Sonnet 5 em 2026-08-20 usa $2/$10 e em 2026-09-05 usa $3/$15**; `speed: "fast"` em Opus 5 dobra o preço.

**Períodos:** virada de mês; virada de semana; horário de verão; semana de calendário ≠ rolling 7 dias.

**Calibração:** histórico sintético → teto = maior bloco completo; consumo acima do teto eleva o teto.

---

## 13. Riscos conhecidos

| Risco | Mitigação |
|---|---|
| Blocos de 5h derivados divergem do `/usage` oficial | Rotulado como estimativa na UI; nunca apresentado como número oficial |
| Teto do plano é calibrado, não publicado | Override manual nas settings; auto-eleva quando ultrapassado |
| Schema do JSONL pode mudar entre versões do Claude Code | Decoder tolerante (campos opcionais); linha inválida é pulada, não fatal |
| Preço promocional do Sonnet 5 expira em 2026-08-31 | Tabela indexada por data (§8.3); a janela já está codificada |
| Novos modelos aparecem sem entrada na tabela | §8.5 — custo parcial e sinalizado, nunca $0 silencioso |
