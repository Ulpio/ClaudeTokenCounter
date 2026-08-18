# Fonte de uso ao vivo + janelas por modelo — Design

**Data:** 2026-08-18
**Status:** Aprovado para planejamento
**Referência:** [CodexBar](https://github.com/steipete/CodexBar) (`docs/claude.md`, `docs/ui.md`, `docs/refresh-loop.md`)
**Substitui:** §7.1 e §7.3 do design de 2026-08-17 (derivação de bloco e calibração de teto deixam de ser o caminho principal)

---

## 1. Objetivo

Trocar a fonte primária de uso: de `cachedUsageUtilization` em `~/.claude.json` — que só se move quando o Claude Code roda — para uma chamada ao vivo em `GET https://api.anthropic.com/api/oauth/usage`, a mesma que o próprio Claude Code faz.

Junto vem a consequência natural: o payload traz janelas por modelo, que o app hoje não mostra.

Duas entregas:

| | O quê | Por quê |
|---|---|---|
| **A** | Fonte ao vivo, com a cache como fallback | O número exibido hoje pode estar horas defasado (§2) |
| **B** | Janelas semanais por modelo | Num Max o teto por modelo estoura antes do geral, e o app é cego para ele |

---

## 2. Evidência

Sondagem contra a conta real em 2026-08-18, 17:07 UTC.

**A cache estava 13h25 defasada e errava a janela de sessão por 29 pontos:**

| Janela | cache (`~/.claude.json`) | ao vivo | erro |
|---|---|---|---|
| `five_hour` | **35%** | **6%** | 29 pontos |
| `seven_day` | 23% | 25% | 2 pontos |

Não é arredondamento: são 35% de uma janela de 5h que já tinha resetado inteira. O app mostrava um número de uma sessão morta.

O erro é assimétrico por construção. A janela de 5h gira 33 vezes mais rápido que a de 7 dias, então a mesma defasagem de relógio a destrói e mal arranha a semanal. E é a de 5h que a barra de menu exibe.

---

## 3. Achado que definiu a arquitetura

**A cache é uma cópia gravada da resposta ao vivo, mais um `fetchedAtMs`.** As mesmas 17 chaves de topo, inclusive `limits`. Verificado campo a campo na sondagem.

Consequência: não são duas fontes com dois parsers. É **um parser, duas origens**. O `CachedUsageReader` e o `LiveUsageFetcher` produzem o mesmo `UsageReport`, e nada a jusante sabe de onde veio — exceto a linha da UI que diz a procedência, que é justamente o ponto.

### 3.1 `limits[]` é o contrato, não as chaves de topo

Resposta real (recortada):

```json
{
  "five_hour":  { "utilization": 6.0,  "resets_at": "2026-08-18T19:20:00Z" },
  "seven_day":  { "utilization": 25.0, "resets_at": "2026-08-23T07:00:00Z" },
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "tangelo": null, "iguana_necktie": null, "nimbus_quill": { "utilization": 0.0 },
  "omelette_promotional": null, "cinder_cove": null, "amber_ladder": null,
  "limits": [
    { "kind": "session",       "group": "session", "percent": 6,  "severity": "normal",
      "resets_at": "2026-08-18T19:20:00Z", "scope": null, "is_active": false },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 25, "severity": "normal",
      "resets_at": "2026-08-23T07:00:00Z", "scope": null, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 0,  "severity": "normal",
      "resets_at": null, "is_active": false,
      "scope": { "model": { "id": null, "display_name": "Fable" } } }
  ]
}
```

Três razões para ler `limits[]` e não as chaves de topo:

1. **As chaves de topo são codinomes internos que giram.** `tangelo`, `iguana_necktie`, `nimbus_quill`, `omelette_promotional`, `cinder_cove`, `amber_ladder`. Nenhum é documentado; nenhum sobreviverá a um ciclo de produto. `limits[]` é auto-descritivo: `kind` + `scope` dizem o que a entrada é.

2. **Não hardcodar Opus/Sonnet.** Na conta real `seven_day_opus` e `seven_day_sonnet` são `null`; a janela por modelo que existe de fato chega como `weekly_scoped` com `scope.model.display_name = "Fable"`. Renderizar o que vier em `limits[]`, rotulado pelo `display_name`, entrega o B sem apostar em nome de modelo. É a mesma conclusão que o CodexBar registra em `docs/ui.md` ("stable, model-generic token label").

3. **`severity` e `is_active` vêm de graça.** O servidor já classifica a gravidade — melhor semáforo que threshold local — e já diz qual janela é a que aperta. Aqui é a semanal, não a de 5h.

---

## 4. Decisões tomadas

| # | Decisão | Escolha | Razão |
|---|---|---|---|
| L1 | Leitura do `accessToken` | **Opt-in explícito** nas Settings, desligado por padrão | O app passa a depender de credencial de outro app; isso é escolha do usuário, não default |
| L2 | Token expirado / 401 | **Só leitura**: cair na cache e avisar. Nunca faz refresh de OAuth, nunca escreve no keychain | Corrida de escrita no item do Claude Code pode invalidar a sessão dele. O Claude Code rotaciona sozinho a cada execução, então a degradação é curta |
| L3 | Contrato do payload | `limits[]` primário; chaves de topo como fallback legado | §3.1 |
| L4 | Janelas por modelo | Genéricas, dirigidas pelo `display_name` | §3.1 item 2 |
| L5 | Caminho derivado (JSONL + `CeilingCalibrator`) | **Permanece vivo** como terceiro nível de fallback | É o único caminho que funciona sem credencial e sem cache |
| L6 | Métrica da barra de menu | Continua % da sessão | Trocar para a janela `is_active` é o item E do backlog; fora deste escopo |

---

## 5. Restrições descobertas

**C1 — O token existe e tem o escopo necessário.** Item de keychain `Claude Code-credentials`, chave `claudeAiOauth`, campos `accessToken`, `refreshToken`, `expiresAt`, `refreshTokenExpiresAt`, `scopes`, `subscriptionType`, `rateLimitTier`. Os `scopes` incluem `user:profile`, exigido pelo endpoint — tokens só com `user:inference` recebem 401.

**C2 — O `accessToken` é de vida curta.** Na sondagem: emitido e expirando no mesmo dia, janela de horas. Qualquer desenho que assuma token estável está errado. Daí L2: conferir `expiresAt` antes de gastar rede, e tratar 401 como caminho normal, não como exceção.

**C3 — O prompt de keychain é do macOS, não nosso.** O item pertence ao Claude Code. A primeira leitura pode abrir diálogo de autorização. Negar precisa degradar para a cache, não travar.

**C4 — Os cabeçalhos são obrigatórios.** `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20`. Sem o segundo o endpoint não responde o formato esperado.

**C5 — Endpoint interno e indocumentado.** Mesma postura que o `OfficialUsageReader` já adotou para a cache: toda falha de leitura ou de parse degrada, nunca quebra.

---

## 6. Arquitetura

Novo diretório `Sources/CCUsageCore/Usage/`. Nada aqui importa SwiftUI.

```
                       ┌──────────────────┐
  keychain ──────────► │ KeychainTokenSource │──┐   (único caminho que lê accessToken)
                       └──────────────────┘  │
                                             ▼
                       ┌──────────────────────────┐
   api.anthropic.com ◄─┤    LiveUsageFetcher       │──┐
                       └──────────────────────────┘  │
                                                     ├──► UsageReportDecoder ──► UsageReport
                       ┌──────────────────────────┐  │
   ~/.claude.json ────►│    CachedUsageReader      │──┘
                       └──────────────────────────┘
                                                            │
                       ┌──────────────────────────┐         │
   JSONL + Calibrator ─┤   caminho derivado (hoje) │         │
                       └──────────────────────────┘         ▼
                                    │              ┌──────────────────┐
                                    └─────────────►│ UsageSourcePolicy │──► UsageSnapshot
                                                   └──────────────────┘
```

### 6.1 Tipos

**`UsageReport`** — valor decodificado, `Sendable`, `Equatable`.

```swift
public struct UsageReport: Sendable, Equatable {
    public struct Limit: Sendable, Equatable {
        public let kind: Kind          // .session | .weeklyAll | .weeklyScoped | .other(String)
        public let group: String
        public let fraction: Double    // percent / 100
        public let severity: Severity  // .normal | .other(String)
        public let resetsAt: Date?
        public let modelName: String?  // scope.model.display_name
        public let isActive: Bool
    }
    public let limits: [Limit]
    public let fetchedAt: Date
}
```

`Kind` e `Severity` têm case `.other(String)`. Codinome ou gravidade nova da Anthropic entra como dado desconhecido e é ignorada pela UI — não derruba o parse. Este é o mesmo princípio que já rege o `PricingTable` para modelo sem preço: o desconhecido é marcado, nunca convertido em zero.

**Só `severity: "normal"` foi observado.** A conta sondada estava em 6% e 25%, longe de qualquer alerta, então os nomes das gravidades altas são desconhecidos. `Severity` nasce com `.normal` e `.other(String)` apenas; os casos altos entram quando forem vistos de verdade. Adivinhar `"warning"` / `"critical"` agora produziria um `.other` silencioso com cara de suporte — pior que não suportar. É a mesma postura que o `PlanDetector` já toma com os tiers que nunca observou.

**`UsageReportDecoder`** — `[String: Any] → UsageReport?`. Usado pelas duas origens. Lê `limits[]`; na ausência, monta `limits` sintéticos a partir de `five_hour` / `seven_day` (Claude Code antigo).

**`TokenSource`** — protocolo. `func accessToken(at now: Date) -> String?`, devolvendo `nil` quando ausente ou expirado. Existe para os testes injetarem token falso sem tocar no keychain.

**`KeychainTokenSource`** — implementação real. **Único caminho de código do app que lê `accessToken`.** Confere `expiresAt` antes de devolver, para não gastar rede com token morto (C2).

**`LiveUsageFetcher`** — `func fetch(at now: Date) async throws -> UsageReport`. Recebe `TokenSource` e `URLSession` por injeção. Timeout de 20s. Erros tipados: `.noToken`, `.unauthorized`, `.transport(Error)`, `.malformed`.

**`CachedUsageReader`** — o `OfficialUsageReader` atual, reescrito para emitir `UsageReport` pelo decoder compartilhado.

**`UsageSourcePolicy`** — função pura, sem relógio próprio e sem I/O.

### 6.2 Seleção de fonte

```
entrada:  (liveHabilitado, resultadoLive, resultadoCache, agora)
saída:    (relatório escolhido?, SourceStatus)
```

| # | Condição | Fonte | Status para a UI |
|---|---|---|---|
| 1 | live desligado, cache presente | cache | `.cached(age:)` |
| 2 | live ligado, sucesso | live | `.live(at:)` |
| 3 | live ligado, `.noToken` ou `.unauthorized` | cache | `.credentialExpired(age:)` — "rode o Claude Code" |
| 4 | live ligado, falha de rede | cache | `.liveUnavailable(age:)` |
| 5 | nenhuma origem disponível | — | `.derivedOnly` (o `SnapshotBuilder` segue pelo caminho JSONL) |

**Primeira condição que casar vence**, de cima para baixo. O caso 5 é o fundo do poço, não uma condição paralela: qualquer linha acima que aponte para a cache cai nele quando a cache também está ausente.

Cinco casos, cinco testes, nenhum precisa de rede nem de keychain.

---

## 7. Modelo

`UsageSnapshot.Gauge` hoje distingue origem com `officialFetchedAt: Date?` e `isOfficial: Bool`. Binário demais para três origens.

| Antes | Depois |
|---|---|
| `officialFetchedAt: Date?` | `provenance: Provenance` — `.live(at: Date)` / `.cached(at: Date)` / `.derived` |
| `isOfficial: Bool` | derivado de `provenance` |
| — | `severity: Severity?` |
| — | `isActive: Bool` |

`age(at:)` passa a existir só em `.cached`. Ao vivo a idade é de segundos e não é informação — some da UI, em vez de virar um "há 4s" permanente.

`UsageSnapshot` ganha:

```swift
public struct ScopedGauge: Sendable, Equatable {
    public let modelName: String
    public let gauge: Gauge
}
public let scopedWeekly: [ScopedGauge]
```

### 7.1 De `limits[]` para o snapshot

| Entrada | Destino | Colisão |
|---|---|---|
| `kind == .session` | `snapshot.session` | primeira vence |
| `kind == .weeklyAll` | `snapshot.weekly` | primeira vence |
| `kind == .weeklyScoped` | `snapshot.scopedWeekly`, uma por entrada | preserva a ordem do payload |
| `kind == .other` | descartada | — |

"Primeira vence" e não "última" porque uma segunda entrada de mesmo `kind` seria formato novo, não correção da primeira — e formato novo deve ser ignorado, não obedecido. Sem entrada `.session`, `snapshot.session` cai para o caminho derivado: o gauge de sessão nunca é nulo, por decisão anterior do projeto.

`weeklyPace` permanece: continua sendo o que responde quando não há janela semanal nenhuma (caso 5).

---

## 8. UI

**Linha de procedência.** Substitui o rótulo binário de hoje ("Números oficiais da sua conta" / "Estimativa calibrada pelo seu histórico"):

| Status | Texto | Peso visual |
|---|---|---|
| `.live` | "ao vivo" | terciário |
| `.cached`, idade < 1h | "cache do Claude Code · há 20min" | terciário |
| `.cached`, idade ≥ 1h | "cache defasada · há 13h" | **aviso visível** |
| `.credentialExpired` | "credencial expirada · rode o Claude Code" | **aviso visível** |
| `.liveUnavailable` | "sem conexão · cache de há 20min" | aviso |
| `.derivedOnly` | "estimado do seu histórico" | terciário |

O corte em 1h é de apresentação, não de política — `UsageSourcePolicy` devolve um só `.cached(age:)` e a UI decide o peso. A razão do corte é a janela que ele protege: 1h é 20% de uma janela de 5h, e uma cache mais velha que isso já pode estar descrevendo uma sessão que resetou.

A promoção de nota de rodapé para aviso no caso de cache velha é deliberada: foi exatamente o estado que a sondagem pegou mentindo por 29 pontos (§2), e ele era invisível.

**Janelas por modelo.** Renderizadas apenas quando `isActive` ou `fraction > 0`. Sem esse filtro a conta real ganharia uma linha "Fable 0%" permanente, que é ruído — a janela existe no payload mas não diz nada.

**Semáforo.** `UsageColor` passa a preferir `severity` do servidor quando presente, caindo nos thresholds locais quando ausente ou `.other`.

---

## 9. Settings e cadência

**Toggle "Buscar números ao vivo"**, desligado por padrão (L1), com o texto honesto do que ele faz: lê o token de acesso que o Claude Code guarda no keychain e consulta a API da Anthropic; o macOS pode pedir autorização. Abaixo dele, a última busca bem-sucedida ou o erro corrente.

**Cadência mínima:** busca ao abrir o painel, a cada 5 min enquanto o toggle estiver ligado, e no refresh manual. O `ticker` de 30s existente continua só redesenhando a contagem regressiva.

A política adaptativa do CodexBar (item D do backlog: low power e estado térmico → 30min; menu aberto há pouco → 2min; ocioso → 15–30min) fica fora deste escopo, mas o timer é estruturado como uma função `próximoIntervalo() -> Duration` para ela entrar depois sem reescrita.

---

## 10. Testes

TDD. Nada de rede, nada de keychain.

| Arquivo | Cobre |
|---|---|
| `UsageReportDecoderTests` | payload real como fixture; caminho `limits[]`; fallback legado por chaves de topo; janelas `null`; `kind` e `severity` desconhecidos; JSON corrompido; `percent` ausente |
| `UsageSourcePolicyTests` | os cinco casos de §6.2 |
| `LiveUsageFetcherTests` | `URLProtocol` stub: 200, 401, timeout, corpo lixo, token ausente; presença dos dois cabeçalhos (C4) |
| `ScopedWeeklyTests` | filtro de renderização (`isActive` ou `fraction > 0`) |
| `OfficialUsageReaderTests` *(atualizado)* | mesma cobertura, agora pelo decoder compartilhado |
| `AppSettingsTests` *(atualizado)* | persistência do toggle |

A fixture usa o payload capturado na sondagem, com os percentuais preservados — são eles que dão sentido aos testes de janela por modelo. A resposta não contém credencial, e-mail nem identificador de conta: só percentuais, horários de reset e nomes de janela.

O caminho real do `KeychainTokenSource` fica sem teste, mesma postura que o `PlanDetector` já adota hoje: o keychain é fronteira de sistema, e o protocolo existe justamente para que nada acima dela dependa dele.

---

## 11. Arquivos

**Novos**

```
Sources/CCUsageCore/Usage/UsageReport.swift
Sources/CCUsageCore/Usage/UsageReportDecoder.swift
Sources/CCUsageCore/Usage/TokenSource.swift
Sources/CCUsageCore/Usage/KeychainTokenSource.swift
Sources/CCUsageCore/Usage/LiveUsageFetcher.swift
Sources/CCUsageCore/Usage/UsageSourcePolicy.swift
Tests/CCUsageCoreTests/UsageReportDecoderTests.swift
Tests/CCUsageCoreTests/UsageSourcePolicyTests.swift
Tests/CCUsageCoreTests/LiveUsageFetcherTests.swift
Tests/CCUsageCoreTests/Fixtures/oauth-usage-response.json
```

**Movido e reescrito**

```
Sources/CCUsageCore/Parsing/OfficialUsageReader.swift → Sources/CCUsageCore/Usage/CachedUsageReader.swift
```

**Tocados**

```
Sources/CCUsageCore/Models/UsageSnapshot.swift      provenance, severity, isActive, scopedWeekly
Sources/CCUsageCore/SnapshotBuilder.swift           consome UsageReport em vez de OfficialUsage
Sources/CCUsageCore/UsageStore.swift                fetch ao vivo, cadência, SourceStatus
Sources/CCUsageCore/Settings/AppSettings.swift      toggle liveUsageEnabled
Sources/CCUsageCore/Settings/PlanDetector.swift     passa a usar TokenSource; doc-comment reescrito (§12)
Sources/ClaudeTokenCounter/Settings/SettingsView.swift
Sources/ClaudeTokenCounter/Settings/SettingsFormState.swift
Sources/ClaudeTokenCounter/Panel/UsagePanel.swift   linha de procedência, janelas por modelo
Sources/ClaudeTokenCounter/Panel/UsageColor.swift   prefere severity do servidor
```

---

## 12. Dívida que este trabalho cria e paga

O doc-comment do `PlanDetector` afirma hoje:

> **Lê exclusivamente `rateLimitTier`.** O mesmo item guarda `accessToken` e `refreshToken`; nada aqui os toca, e não há caminho de código neste app que os leia. Isso é deliberado.

A partir de L1 isso é falso. A promessa é reescrita para a forma condicional e verificável: com o toggle desligado nenhum caminho lê o token; com ele ligado, apenas o `KeychainTokenSource` lê, e só o `accessToken` — o `refreshToken` continua sem nenhum leitor no app, por L2.

Na mesma passada o `PlanDetector` deixa de abrir o keychain por conta própria e passa a consumir o mesmo `TokenSource`. Dois leitores do mesmo item era duplicação tolerável enquanto um deles lia só o tier; deixa de ser quando os dois precisam do mesmo segredo.

---

## 13. Não-objetivos

Ficam fora, nomeados para não voltarem como escopo acidental:

- **Refresh de OAuth** (L2). Nem próprio, nem regravando no keychain.
- **Barra de menu configurável** (item E do backlog): tokens escolhíveis, métrica `is_active`, layout de duas linhas.
- **Política de refresh adaptativa** (item D): §9 deixa o encaixe pronto e para por aí.
- **Notificações** de quota e reset (item F).
- **`extra_usage` e `spend`.** Vêm no payload, estão desabilitados na conta real, e não têm UI a que pertencer ainda.
- **Admin API** (`sk-ant-admin...`) para gasto organizacional. É outro produto.
- **Distribuição** — Sparkle, Homebrew cask, CLI (item G).

---

## 14. Riscos

| Risco | Mitigação |
|---|---|
| O endpoint é interno e pode mudar de forma sem aviso | Todo campo é opcional; `kind`/`severity` desconhecidos viram `.other`; falha de parse degrada para a cache (C5) |
| O prompt de keychain assusta ou é negado | Toggle desligado por padrão, com o texto dizendo o que vai acontecer; negar cai na cache (C3) |
| Token de vida curta deixa o app em fallback com frequência | `expiresAt` conferido antes da rede; 401 é caminho normal com status próprio, não erro (C2, L2) |
| A cache deixar de ser escrita numa versão futura do Claude Code | O caminho derivado (JSONL + `CeilingCalibrator`) continua vivo como terceiro nível (L5) |
| Rate limit no endpoint por polling | 5 min fixos, e a busca só acontece com o toggle ligado |
