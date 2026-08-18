# Fonte de uso ao vivo + janelas por modelo — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar a fonte primária de uso do cache defasado de `~/.claude.json` por uma chamada ao vivo em `GET https://api.anthropic.com/api/oauth/usage`, com o cache como fallback, e passar a exibir as janelas semanais por modelo.

**Architecture:** Cache e resposta ao vivo são o mesmo payload, então há um tipo (`UsageReport`) e um decoder (`UsageReportDecoder`) alimentados por duas origens (`CachedUsageReader`, `LiveUsageFetcher`). Uma função pura (`UsageSourcePolicy`) escolhe entre elas e devolve um status que a UI exibe. O caminho derivado atual (JSONL + `CeilingCalibrator`) permanece como terceiro nível de fallback.

**Tech Stack:** Swift 6.4, SwiftPM sem Xcode (Command Line Tools), swift-testing, `@Observable`, SwiftUI `MenuBarExtra`, `URLSession`, Security.framework.

**Spec:** `docs/superpowers/specs/2026-08-18-live-usage-source-design.md`

## Global Constraints

- **macOS 26.0** é o piso da plataforma (`Package.swift`). Não subir, não descer.
- **Sem Xcode.** Só Command Line Tools. Consequência dura: **`@State` não existe** (é macro do SwiftUI, cujo plugin só vem com o Xcode). Estado de view usa `@Observable` com dono explícito, como `SettingsFormState` já faz.
- **Testes rodam por `./Scripts/test.sh`, nunca por `swift test` direto.** O script injeta o plugin path de macros e dois rpaths que o CLT não conecta sozinho. `swift test` puro falha na hora de linkar. Filtro: `./Scripts/test.sh --filter NomeDoTeste`.
- **Zero dependências externas.** O `Package.swift` não tem `dependencies:` e continua sem.
- **`CCUsageCore` não importa SwiftUI.** É o que mantém toda a lógica testável sem instanciar janela. `AppKit`/`SwiftUI` só no alvo `ClaudeTokenCounter`.
- **Comentários e strings de UI em português**, como todo o repositório. Comentários explicam *por que*, não *o que*.
- **`refreshToken` não pode ganhar nenhum leitor.** Decisão L2 da spec. O tipo `ClaudeCredentials` não tem campo para ele — a ausência do campo é a garantia.
- **Cabeçalhos obrigatórios** na chamada ao vivo: `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20`.
- **Toda falha de rede, keychain ou parse degrada.** Nunca derruba o app, nunca vira zero.

## Desvios da spec (decididos neste plano, sujeitos a rejeição)

Três, cada um com razão. Se o revisor discordar de algum, ele volta para a forma da spec.

1. **`Limit` não carrega `group: String`.** A spec §6.1 lista o campo. Ele é derivável de `kind` sem exceção (`session` → `"session"`; `weekly_all` e `weekly_scoped` → `"weekly"`) e nenhum consumidor no plano o lê. Campo carregado e nunca usado envelhece pior que campo ausente.

2. **A fixture do payload é uma string Swift inline no arquivo de teste, não `Tests/CCUsageCoreTests/Fixtures/oauth-usage-response.json`.** Recurso de teste em SwiftPM exige `resources:` no `Package.swift` e acesso por `Bundle.module` — mais superfície num toolchain que já é frágil sem Xcode. `OfficialUsageReaderTests` já estabelece o padrão inline (a constante `realShape`), e este plano o segue.

3. **O protocolo chama-se `CredentialSource` e devolve `ClaudeCredentials`, não `TokenSource` devolvendo `String?`.** A spec §6.1 nomeia `TokenSource`. Mas o `PlanDetector` precisa do `rateLimitTier` do mesmo item de keychain, e a spec §12 manda unificar os dois leitores. Um protocolo que vende só o token não serve os dois; um que vende credenciais serve, e o nome passa a descrever o que ele faz.

4. **`UsageColor` NÃO passa a preferir o `severity` do servidor.** A spec §8 pede isso, e o plano não entrega. Razão: só `severity: "normal"` foi observado. Preferir um sinal cujo vocabulário conhecemos pela metade significa que uma sessão em 95% marcada como `normal` — e não sabemos se a Anthropic a marcaria assim — apagaria o vermelho que os limiares locais dariam. O modo de falha é silenciar o aviso exatamente quando ele importa.

   O campo `severity` continua no modelo, porque é grátis e é como vamos descobrir os outros valores: quando um `.other("…")` aparecer numa conta em consumo alto, o nome fica registrado e aí o semáforo pode passar a preferi-lo. Até lá, os limiares locais de `UsageColor` mandam, inalterados.

5. **Não há "refresh manual".** A spec §9 lista busca ao abrir o painel, a cada 5 min, e no refresh manual. As duas primeiras estão na Task 8; a terceira não, porque **o app não tem refresh manual hoje** — nenhum botão, nenhum item de menu. Inventar um é UI que a spec não desenhou. `panelDidOpen()` é o caminho iniciado pelo usuário, e abrir o painel é o gesto que o usuário já faz quando quer o número atual.

6. **`SettingsFormState` não é tocado.** A spec §11 o lista entre os arquivos modificados. Ele não precisa mudar: existe para segurar rascunho de digitação, porque os valores intermediários de "214400000" (2, 21, 214…) fariam o gauge saltar a cada tecla. Um `Toggle` booleano não tem estado intermediário — liga direto em `$settings.liveUsageEnabled`.

7. **`ScopedWeeklyTests` não é arquivo próprio.** A spec §10 o lista. A cobertura existe (Task 6, `scopedWeeklyWindowsBecomeTheirOwnGauges` e `scopedWindowWithoutAModelNameIsDropped`), dentro de `SnapshotBuilderTests` — é lá que a montagem acontece, e separar teste da unidade que ele exercita só espalha.

---

## Estrutura de arquivos

**Novos** — todos em `Sources/CCUsageCore/Usage/`, um tipo por arquivo:

| Arquivo | Responsabilidade |
|---|---|
| `UsageReport.swift` | O valor decodificado. Sem I/O, sem parsing. |
| `UsageReportDecoder.swift` | `[String: Any]` → `UsageReport`. Compartilhado pelas duas origens. |
| `CredentialSource.swift` | Protocolo + `ClaudeCredentials`. Sem Security.framework. |
| `KeychainCredentialSource.swift` | A única implementação que toca o keychain. |
| `LiveUsageFetcher.swift` | A chamada HTTP. |
| `CachedUsageReader.swift` | Leitura de `~/.claude.json`. |
| `UsageSourcePolicy.swift` | Escolha de fonte. Função pura. |

**Removidos** ao final da Task 6: `Sources/CCUsageCore/Parsing/OfficialUsageReader.swift` e `Tests/CCUsageCoreTests/OfficialUsageReaderTests.swift` (cobertura migrada para `CachedUsageReaderTests`).

**Ordem e por que ela é essa:** as tasks 1–5 só *adicionam* código. O `OfficialUsageReader` continua vivo e o `SnapshotBuilder` continua o consumindo até a Task 6, que faz a troca e a remoção numa passada. Cada task compila e a suíte passa em cada commit — em nenhum momento existe uma árvore quebrada esperando a próxima task.

---

## Task 1: `UsageReport` e `UsageReportDecoder`

**Files:**
- Create: `Sources/CCUsageCore/Usage/UsageReport.swift`
- Create: `Sources/CCUsageCore/Usage/UsageReportDecoder.swift`
- Test: `Tests/CCUsageCoreTests/UsageReportDecoderTests.swift`

**Interfaces:**
- Consumes: nada (primeira task)
- Produces: `UsageReport` com `limits: [UsageReport.Limit]`, `fetchedAt: Date`, e os acessores `session: Limit?`, `weeklyAll: Limit?`, `weeklyScoped: [Limit]`. `UsageReport.Limit` com `kind: Kind`, `fraction: Double`, `severity: Severity`, `resetsAt: Date?`, `modelName: String?`, `isActive: Bool`. `UsageReportDecoder.decode(_ root: [String: Any], fetchedAt: Date) -> UsageReport?` e `UsageReportDecoder.parseTimestamp(_ raw: String) -> Date?`.

- [ ] **Step 1: Escrever o teste que falha**

Criar `Tests/CCUsageCoreTests/UsageReportDecoderTests.swift`:

> Os testes ficam dentro de `@Suite struct UsageReportDecoderTests` — métodos de um tipo, não funções
> globais. Sem isso, `parsesResetTimestampWithSixFractionalDigits` colidem com os nomes idênticos em
> `OfficialUsageReaderTests.swift`, que só é removido na Task 6, e o Swift recusa a
> redeclaração. É o mesmo padrão que a Task 4 já usa. Os helpers de arquivo ficam
> fora do struct.

```swift
import Foundation
import Testing
@testable import CCUsageCore

/// Resposta real de `GET /api/oauth/usage`, capturada de uma conta Max 5×.
/// Preservada com os percentuais originais: são eles que dão sentido aos testes
/// de janela por modelo. Não contém credencial, e-mail nem identificador.
let liveResponse = """
{
  "five_hour":  { "utilization": 6.0,  "resets_at": "2026-08-18T19:20:00.510586+00:00" },
  "seven_day":  { "utilization": 25.0, "resets_at": "2026-08-23T07:00:00.510608+00:00" },
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "tangelo": null,
  "nimbus_quill": { "utilization": 0.0, "resets_at": null },
  "limits": [
    { "kind": "session", "group": "session", "percent": 6, "severity": "normal",
      "resets_at": "2026-08-18T19:20:00.510586+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_all", "group": "weekly", "percent": 25, "severity": "normal",
      "resets_at": "2026-08-23T07:00:00.510608+00:00", "scope": null, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
      "resets_at": null, "is_active": false,
      "scope": { "model": { "id": null, "display_name": "Fable" } } }
  ]
}
"""

func dictionary(_ json: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

let fixedNow = Date(timeIntervalSince1970: 1_787_000_000)

@Suite struct UsageReportDecoderTests {
    @Test func decodesTheThreeLimitKindsFromTheLiveResponse() {
        let report = UsageReportDecoder.decode(dictionary(liveResponse), fetchedAt: fixedNow)!

        #expect(report.session?.fraction == 0.06)
        #expect(report.session?.isActive == false)
        #expect(report.weeklyAll?.fraction == 0.25)
        #expect(report.weeklyAll?.isActive == true)
        #expect(report.weeklyScoped.count == 1)
        #expect(report.weeklyScoped.first?.modelName == "Fable")
        #expect(report.fetchedAt == fixedNow)
    }

    @Test func readsLimitsAndIgnoresTheTopLevelCodenames() {
        // `tangelo`, `nimbus_quill` e companhia são codinomes internos que giram.
        // Nenhum pode virar janela: só `limits[]` define o que existe.
        let report = UsageReportDecoder.decode(dictionary(liveResponse), fetchedAt: fixedNow)!
        #expect(report.limits.count == 3)
    }

    @Test func parsesResetTimestampWithSixFractionalDigits() {
        // O payload traz microssegundos e offset "+00:00" — formatos que o parser
        // ISO padrão do Swift recusa se levados ao pé da letra.
        let expected = try! Date.ISO8601FormatStyle(includingFractionalSeconds: false)
            .parse("2026-08-18T19:20:00Z")
        let report = UsageReportDecoder.decode(dictionary(liveResponse), fetchedAt: fixedNow)!
        #expect(report.session?.resetsAt == expected)
    }

    @Test func nullResetTimeStaysNil() {
        let report = UsageReportDecoder.decode(dictionary(liveResponse), fetchedAt: fixedNow)!
        #expect(report.weeklyScoped.first?.resetsAt == nil)
    }

    @Test func unknownKindIsPreservedNotDiscarded() {
        // O que aparece aqui é o que a próxima versão precisa suportar.
        let json = """
        { "limits": [ { "kind": "monthly_pilot", "percent": 5, "severity": "normal",
                        "is_active": false } ] }
        """
        let report = UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow)!
        #expect(report.limits.first?.kind == .other("monthly_pilot"))
        #expect(report.session == nil)
        #expect(report.weeklyAll == nil)
    }

    @Test func unknownSeverityIsPreservedNotDiscarded() {
        let json = """
        { "limits": [ { "kind": "session", "percent": 91, "severity": "screaming",
                        "is_active": true } ] }
        """
        let report = UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow)!
        #expect(report.session?.severity == .other("screaming"))
    }

    @Test func firstEntryOfEachKindWins() {
        // Uma segunda entrada de mesmo kind é formato novo, não correção da
        // primeira — e formato novo deve ser ignorado, não obedecido.
        let json = """
        { "limits": [ { "kind": "session", "percent": 10, "severity": "normal", "is_active": true },
                      { "kind": "session", "percent": 90, "severity": "normal", "is_active": true } ] }
        """
        let report = UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow)!
        #expect(report.session?.fraction == 0.10)
    }

    @Test func scopedWindowsKeepPayloadOrder() {
        let json = """
        { "limits": [
            { "kind": "weekly_scoped", "percent": 1, "severity": "normal", "is_active": false,
              "scope": { "model": { "display_name": "Opus" } } },
            { "kind": "weekly_scoped", "percent": 2, "severity": "normal", "is_active": false,
              "scope": { "model": { "display_name": "Sonnet" } } } ] }
        """
        let report = UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow)!
        #expect(report.weeklyScoped.map(\.modelName) == ["Opus", "Sonnet"])
    }

    @Test func fallsBackToTopLevelKeysWhenLimitsIsAbsent() {
        // Claude Code antigo grava o cache sem `limits`. A janela ainda é legível.
        let json = """
        { "five_hour": { "utilization": 22, "resets_at": "2026-08-18T02:20:00.007553+00:00" },
          "seven_day": { "utilization": 19, "resets_at": "2026-08-23T07:00:00.007577+00:00" },
          "seven_day_opus": null }
        """
        let report = UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow)!
        #expect(report.session?.fraction == 0.22)
        #expect(report.weeklyAll?.fraction == 0.19)
        // Sem `limits`, não há janela por modelo a recuperar: as chaves de topo
        // para modelo vêm null e não são contrato.
        #expect(report.weeklyScoped.isEmpty)
    }

    @Test func nullTopLevelWindowsBecomeNothingNotZero() {
        let json = #"{ "five_hour": null, "seven_day": null }"#
        #expect(UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow) == nil)
    }

    @Test func payloadWithNoUsableWindowYieldsNoReport() {
        #expect(UsageReportDecoder.decode(dictionary(#"{ "numStartups": 3 }"#),
                                          fetchedAt: fixedNow) == nil)
    }

    @Test func entryMissingPercentIsSkippedNotZeroed() {
        let json = """
        { "limits": [ { "kind": "session", "severity": "normal", "is_active": true },
                      { "kind": "weekly_all", "percent": 30, "severity": "normal", "is_active": true } ] }
        """
        let report = UsageReportDecoder.decode(dictionary(json), fetchedAt: fixedNow)!
        #expect(report.session == nil)
        #expect(report.weeklyAll?.fraction == 0.30)
    }
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `./Scripts/test.sh --filter UsageReportDecoder`
Expected: FAIL na compilação — `cannot find 'UsageReportDecoder' in scope`.

- [ ] **Step 3: Escrever `UsageReport.swift`**

```swift
import Foundation

/// Um relatório de uso da conta, como a Anthropic o publica.
///
/// A resposta ao vivo de `/api/oauth/usage` e o bloco `cachedUsageUtilization`
/// de `~/.claude.json` são o mesmo payload — o segundo é uma cópia gravada do
/// primeiro, mais um carimbo de quando foi buscado. Por isso existe um tipo só,
/// e não um por origem.
public struct UsageReport: Sendable, Equatable {
    public struct Limit: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case session
            case weeklyAll
            case weeklyScoped
            /// Tipo que este app não conhece. Preserva o nome cru em vez de
            /// descartar: o que aparece aqui é o que a próxima versão precisa
            /// suportar.
            case other(String)

            public init(raw: String) {
                switch raw {
                case "session": self = .session
                case "weekly_all": self = .weeklyAll
                case "weekly_scoped": self = .weeklyScoped
                default: self = .other(raw)
                }
            }
        }

        /// Só `normal` foi observado numa conta real — a sondagem pegou a conta
        /// em 6% e 25%, longe de qualquer alerta. Os nomes das gravidades altas
        /// são desconhecidos, e inventá-los produziria um `.other` silencioso
        /// com cara de suporte: pior que não suportar.
        public enum Severity: Sendable, Equatable {
            case normal
            case other(String)

            public init(raw: String) {
                self = raw == "normal" ? .normal : .other(raw)
            }
        }

        public let kind: Kind
        /// 0…1. O payload grava percentual; convertido na decodificação para
        /// bater com o resto do app, que trabalha em fração.
        public let fraction: Double
        public let severity: Severity
        public let resetsAt: Date?
        /// `scope.model.display_name`. Presente nas janelas por modelo, e é o
        /// rótulo que a UI usa — o app não mantém lista de nomes de modelo.
        public let modelName: String?
        /// A janela que a Anthropic considera a que aperta agora.
        public let isActive: Bool

        public init(kind: Kind, fraction: Double, severity: Severity,
                    resetsAt: Date?, modelName: String?, isActive: Bool) {
            self.kind = kind
            self.fraction = fraction
            self.severity = severity
            self.resetsAt = resetsAt
            self.modelName = modelName
            self.isActive = isActive
        }
    }

    public let limits: [Limit]
    /// Quando este relatório foi obtido. Ao vivo é agora; vindo do cache é
    /// quando o Claude Code buscou, que pode ser horas atrás.
    public let fetchedAt: Date

    public init(limits: [Limit], fetchedAt: Date) {
        self.limits = limits
        self.fetchedAt = fetchedAt
    }

    /// Primeira entrada de cada tipo vence. Uma segunda de mesmo `kind` seria
    /// formato novo, não correção da primeira.
    public var session: Limit? { limits.first { $0.kind == .session } }
    public var weeklyAll: Limit? { limits.first { $0.kind == .weeklyAll } }
    /// Na ordem do payload.
    public var weeklyScoped: [Limit] { limits.filter { $0.kind == .weeklyScoped } }
}
```

- [ ] **Step 4: Escrever `UsageReportDecoder.swift`**

```swift
import Foundation

/// Decodifica o payload de uso da Anthropic, venha ele da rede ou do cache.
///
/// **`limits[]` é o contrato.** As chaves de topo (`five_hour`, `seven_day`,
/// `tangelo`, `nimbus_quill`, `iguana_necktie`, `amber_ladder`…) são codinomes
/// internos, não documentados, que giram a cada ciclo de produto. `limits[]` é
/// auto-descritivo: `kind` e `scope` dizem o que cada entrada é, e é ele que
/// carrega as janelas por modelo com nome de exibição.
///
/// As chaves de topo entram só como fallback para versões do Claude Code que
/// gravaram o cache antes de `limits` existir.
///
/// Endpoint interno e indocumentado: toda falha devolve `nil`, e quem chama cai
/// para a próxima fonte. Nunca lança, nunca vira zero.
public enum UsageReportDecoder {
    public static func decode(_ root: [String: Any], fetchedAt: Date) -> UsageReport? {
        if let raw = root["limits"] as? [[String: Any]] {
            let limits = raw.compactMap(limit(from:))
            if !limits.isEmpty { return UsageReport(limits: limits, fetchedAt: fetchedAt) }
        }
        let legacy = legacyLimits(from: root)
        guard !legacy.isEmpty else { return nil }
        return UsageReport(limits: legacy, fetchedAt: fetchedAt)
    }

    /// Entrada sem `kind` ou sem `percent` é descartada em vez de virar janela
    /// zerada — o mesmo princípio que rege modelo sem preço no `PricingTable`.
    private static func limit(from dict: [String: Any]) -> UsageReport.Limit? {
        guard let kindRaw = dict["kind"] as? String,
              let percent = dict["percent"] as? Double
        else { return nil }

        let model = (dict["scope"] as? [String: Any])?["model"] as? [String: Any]
        return UsageReport.Limit(
            kind: .init(raw: kindRaw),
            fraction: percent / 100,
            severity: .init(raw: dict["severity"] as? String ?? ""),
            resetsAt: (dict["resets_at"] as? String).flatMap(parseTimestamp),
            modelName: model?["display_name"] as? String,
            isActive: dict["is_active"] as? Bool ?? false)
    }

    /// Sem `limits`, recupera só as duas janelas genéricas. As chaves de topo
    /// por modelo (`seven_day_opus`, `seven_day_sonnet`) ficam de fora de
    /// propósito: vieram `null` na conta real, e apostar nesses nomes é
    /// exatamente o que ler `limits[]` evita.
    private static func legacyLimits(from root: [String: Any]) -> [UsageReport.Limit] {
        let pairs: [(String, UsageReport.Limit.Kind)] = [
            ("five_hour", .session), ("seven_day", .weeklyAll),
        ]
        return pairs.compactMap { key, kind in
            guard let dict = root[key] as? [String: Any],
                  let utilization = dict["utilization"] as? Double
            else { return nil }
            return UsageReport.Limit(
                kind: kind, fraction: utilization / 100, severity: .normal,
                resetsAt: (dict["resets_at"] as? String).flatMap(parseTimestamp),
                modelName: nil, isActive: false)
        }
    }

    /// O payload traz microssegundos e offset explícito
    /// (`2026-08-18T19:20:00.510586+00:00`). O parser ISO do Swift aceita no
    /// máximo milissegundos, então a parte fracionária é descartada — precisão
    /// sub-segundo não significa nada para um horário de reset.
    static func parseTimestamp(_ raw: String) -> Date? {
        var cleaned = raw
        if let dot = raw.firstIndex(of: "."),
           let offsetStart = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            cleaned = String(raw[..<dot]) + String(raw[offsetStart...])
        }
        let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        if let date = try? plain.parse(cleaned) { return date }
        return try? plain.parse(cleaned.replacingOccurrences(of: "+00:00", with: "Z"))
    }
}
```

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter UsageReportDecoder`
Expected: PASS, 12 testes.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS. Nada foi removido ainda, então nenhum teste existente pode ter regredido.

- [ ] **Step 7: Commit**

```bash
git add Sources/CCUsageCore/Usage/UsageReport.swift \
        Sources/CCUsageCore/Usage/UsageReportDecoder.swift \
        Tests/CCUsageCoreTests/UsageReportDecoderTests.swift
git commit -m "feat: UsageReport e decoder compartilhado das duas origens

limits[] e o contrato primario; as chaves de topo sao codinomes
internos que giram e entram so como fallback legado."
```

---

## Task 2: `CachedUsageReader`

Lê `~/.claude.json` pelo decoder compartilhado. Convive com o `OfficialUsageReader`, que só sai na Task 6.

**Files:**
- Create: `Sources/CCUsageCore/Usage/CachedUsageReader.swift`
- Test: `Tests/CCUsageCoreTests/CachedUsageReaderTests.swift`

**Interfaces:**
- Consumes: `UsageReportDecoder.decode(_:fetchedAt:)`, `UsageReport` (Task 1)
- Produces: `CachedUsageReader.defaultURL: URL` e `CachedUsageReader.read(from: URL) -> UsageReport?`

- [ ] **Step 1: Escrever o teste que falha**

Criar `Tests/CCUsageCoreTests/CachedUsageReaderTests.swift`:

> Os testes ficam dentro de `@Suite struct CachedUsageReaderTests` — métodos de um tipo, não funções
> globais. Sem isso, `missingFileYieldsNoReading`, `malformedFileYieldsNoReading` e `fileWithoutTheCacheKeyYieldsNoReading` colidem com os nomes idênticos em
> `OfficialUsageReaderTests.swift`, que só é removido na Task 6, e o Swift recusa a
> redeclaração. É o mesmo padrão que a Task 4 já usa. Os helpers de arquivo ficam
> fora do struct.

```swift
import Foundation
import Testing
@testable import CCUsageCore

/// Estrutura real de `~/.claude.json`, reduzida ao que importa. O bloco
/// `utilization` é a cópia gravada da resposta de `/api/oauth/usage`, e desde
/// versões recentes do Claude Code traz o `limits[]` junto.
private let cacheShape = """
{
  "numStartups": 13512,
  "cachedUsageUtilization": {
    "fetchedAtMs": 1787010875105,
    "accountUuid": "00000000-0000-4000-8000-000000000000",
    "utilization": {
      "five_hour": { "utilization": 22, "resets_at": "2026-08-18T02:20:00.007553+00:00" },
      "seven_day": { "utilization": 19, "resets_at": "2026-08-23T07:00:00.007577+00:00" },
      "seven_day_opus": null,
      "limits": [
        { "kind": "session", "percent": 22, "severity": "normal",
          "resets_at": "2026-08-18T02:20:00.007553+00:00", "is_active": true },
        { "kind": "weekly_all", "percent": 19, "severity": "normal",
          "resets_at": "2026-08-23T07:00:00.007577+00:00", "is_active": false }
      ]
    }
  }
}
"""

private func writeTemp(_ contents: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "cctc-cache-\(UUID().uuidString).json")
    try! contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Suite struct CachedUsageReaderTests {
    @Test func readsWindowsAndTheFetchTimestamp() {
        let url = writeTemp(cacheShape)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = CachedUsageReader.read(from: url)!
        #expect(report.session?.fraction == 0.22)
        #expect(report.weeklyAll?.fraction == 0.19)
        // A idade do cache é parte do dado: ele só se move quando o Claude Code roda.
        #expect(report.fetchedAt == Date(timeIntervalSince1970: 1787010875.105))
    }

    @Test func readsTheCachedLimitsArrayNotOnlyTheTopLevelKeys() {
        let url = writeTemp(cacheShape)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CachedUsageReader.read(from: url)?.session?.isActive == true)
    }

    @Test func cacheWithoutLimitsFallsBackToTopLevelKeys() {
        let json = """
        { "cachedUsageUtilization": { "fetchedAtMs": 1787010875105,
            "utilization": { "five_hour": { "utilization": 40, "resets_at": null } } } }
        """
        let url = writeTemp(json)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CachedUsageReader.read(from: url)?.session?.fraction == 0.40)
    }

    @Test func missingFileYieldsNoReading() {
        let absent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "cctc-absent-\(UUID().uuidString).json")
        #expect(CachedUsageReader.read(from: absent) == nil)
    }

    @Test func malformedFileYieldsNoReading() {
        // Arquivo corrompido cai na próxima fonte em vez de derrubar o app.
        let url = writeTemp("{ isto não é json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CachedUsageReader.read(from: url) == nil)
    }

    @Test func fileWithoutTheCacheKeyYieldsNoReading() {
        let url = writeTemp(#"{ "numStartups": 3 }"#)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CachedUsageReader.read(from: url) == nil)
    }

    @Test func cacheWithoutFetchTimestampYieldsNoReading() {
        // Sem carimbo não dá para dizer a idade, e a idade é o que decide se este
        // dado pode ser mostrado sem aviso.
        let json = #"{ "cachedUsageUtilization": { "utilization": { "five_hour": { "utilization": 5 } } } }"#
        let url = writeTemp(json)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CachedUsageReader.read(from: url) == nil)
    }
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `./Scripts/test.sh --filter CachedUsageReader`
Expected: FAIL — `cannot find 'CachedUsageReader' in scope`.

- [ ] **Step 3: Escrever `CachedUsageReader.swift`**

```swift
import Foundation

/// Lê `cachedUsageUtilization` de `~/.claude.json`.
///
/// É a cópia que o Claude Code grava da resposta de `/api/oauth/usage`. Serve
/// como fallback quando a busca ao vivo está desligada ou falhou — mas **só se
/// move quando o Claude Code roda**, e por isso o `fetchedAt` é obrigatório:
/// sem ele não dá para dizer a idade, e a idade é o que decide se este dado
/// pode ser exibido sem aviso.
///
/// Campo interno e indocumentado: toda falha devolve `nil` e o app segue para a
/// próxima fonte, em vez de quebrar.
public enum CachedUsageReader {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
    }

    public static func read(from url: URL = defaultURL) -> UsageReport? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any],
              let fetchedAtMs = cache["fetchedAtMs"] as? Double,
              let windows = cache["utilization"] as? [String: Any]
        else { return nil }

        return UsageReportDecoder.decode(
            windows, fetchedAt: Date(timeIntervalSince1970: fetchedAtMs / 1000))
    }
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter CachedUsageReader`
Expected: PASS, 7 testes.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS. `OfficialUsageReaderTests` ainda existe e ainda passa — as duas leituras convivem até a Task 6.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore/Usage/CachedUsageReader.swift \
        Tests/CCUsageCoreTests/CachedUsageReaderTests.swift
git commit -m "feat: CachedUsageReader emite UsageReport pelo decoder compartilhado

Convive com OfficialUsageReader ate a troca do SnapshotBuilder."
```

---
## Task 3: `CredentialSource`, `KeychainCredentialSource` e a migração do `PlanDetector`

O único ponto do app que toca o keychain. Também paga a dívida da spec §12: o `PlanDetector` deixa de abrir o item por conta própria.

**Files:**
- Create: `Sources/CCUsageCore/Usage/CredentialSource.swift`
- Create: `Sources/CCUsageCore/Usage/KeychainCredentialSource.swift`
- Modify: `Sources/CCUsageCore/Settings/PlanDetector.swift` (reescrito por inteiro)
- Test: `Tests/CCUsageCoreTests/CredentialSourceTests.swift`

**Interfaces:**
- Consumes: `Plan.init?(rateLimitTier:)`, que já existe em `PlanDetector.swift` e **permanece intocado**
- Produces:
  - `ClaudeCredentials` com `accessToken: String?`, `expiresAt: Date?`, `rateLimitTier: String?`, e `usableToken(at: Date) -> String?`
  - `protocol CredentialSource: Sendable { func credentials() -> ClaudeCredentials? }`
  - `KeychainCredentialSource(readsAccessToken: Bool, load: @Sendable () -> Data?)`, com `load` default lendo o keychain
  - `PlanDetector.detect(source: any CredentialSource) -> Plan?`

- [ ] **Step 1: Escrever o teste que falha**

Criar `Tests/CCUsageCoreTests/CredentialSourceTests.swift`:

```swift
import Foundation
import Testing
@testable import CCUsageCore

/// Formato real do item de keychain `Claude Code-credentials`. O `refreshToken`
/// está aqui de propósito: o teste prova que ele atravessa a decodificação sem
/// ganhar leitor.
private let keychainBlob = """
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat-TESTE",
    "refreshToken": "sk-ant-ort-TESTE",
    "expiresAt": 1787012535354,
    "refreshTokenExpiresAt": 1789604535354,
    "scopes": ["user:profile", "user:inference"],
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_5x"
  }
}
"""

private func source(_ json: String, readsAccessToken: Bool) -> KeychainCredentialSource {
    KeychainCredentialSource(readsAccessToken: readsAccessToken,
                             load: { Data(json.utf8) })
}

/// Um pouco antes de `expiresAt`.
private let beforeExpiry = Date(timeIntervalSince1970: 1_787_012_000)
/// Um pouco depois.
private let afterExpiry = Date(timeIntervalSince1970: 1_787_013_000)

@Test func readsTheAccessTokenWhenAuthorized() {
    let credentials = source(keychainBlob, readsAccessToken: true).credentials()!
    #expect(credentials.accessToken == "sk-ant-oat-TESTE")
    #expect(credentials.usableToken(at: beforeExpiry) == "sk-ant-oat-TESTE")
}

@Test func doesNotReadTheAccessTokenWhenNotAuthorized() {
    // Com o toggle desligado o campo nem é extraído do dicionário. É a garantia
    // que a promessa reescrita do PlanDetector faz.
    let credentials = source(keychainBlob, readsAccessToken: false).credentials()!
    #expect(credentials.accessToken == nil)
    #expect(credentials.usableToken(at: beforeExpiry) == nil)
}

@Test func theTierIsReadableWithoutAuthorizingTheToken() {
    // O plano continua detectável sem que o app precise da credencial — era
    // verdade antes desta mudança e continua sendo.
    let credentials = source(keychainBlob, readsAccessToken: false).credentials()!
    #expect(credentials.rateLimitTier == "default_claude_max_5x")
}

@Test func expiredTokenIsNotUsable() {
    // O accessToken tem vida de horas. Conferir antes evita gastar uma chamada
    // de rede que só pode voltar 401.
    let credentials = source(keychainBlob, readsAccessToken: true).credentials()!
    #expect(credentials.usableToken(at: afterExpiry) == nil)
}

@Test func credentialsHaveNoPlaceToHoldARefreshToken() {
    // O app nunca renova OAuth (decisão L2): escrever no item do Claude Code
    // pode invalidar a sessão dele. A ausência do campo é o que garante isso —
    // não há onde guardar, então não há como usar.
    let mirror = Mirror(reflecting: source(keychainBlob, readsAccessToken: true).credentials()!)
    let labels = mirror.children.compactMap(\.label)
    #expect(!labels.contains { $0.lowercased().contains("refresh") })
}

@Test func absentKeychainItemYieldsNoCredentials() {
    let empty = KeychainCredentialSource(readsAccessToken: true, load: { nil })
    #expect(empty.credentials() == nil)
}

@Test func malformedBlobYieldsNoCredentials() {
    #expect(source("{ isto não é json", readsAccessToken: true).credentials() == nil)
}

@Test func blobWithoutTheOAuthKeyYieldsNoCredentials() {
    // Claude Code 2.1.x pode gravar só estado de MCP, sem `claudeAiOauth`.
    #expect(source(#"{ "mcpOAuth": {} }"#, readsAccessToken: true).credentials() == nil)
}

@Test func planDetectionReadsTheTierThroughTheSharedSource() {
    let detected = PlanDetector.detect(source: source(keychainBlob, readsAccessToken: false))
    #expect(detected == .max5)
}

@Test func planDetectionYieldsNothingWithoutCredentials() {
    let empty = KeychainCredentialSource(readsAccessToken: false, load: { nil })
    #expect(PlanDetector.detect(source: empty) == nil)
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `./Scripts/test.sh --filter CredentialSource`
Expected: FAIL — `cannot find 'KeychainCredentialSource' in scope`.

- [ ] **Step 3: Escrever `CredentialSource.swift`**

```swift
import Foundation

/// O que o app precisa saber das credenciais que o Claude Code mantém.
///
/// **Não existe campo para `refreshToken`, e isso é o mecanismo, não um
/// esquecimento.** O app nunca renova OAuth: regravar o item de keychain do
/// Claude Code pode invalidar a sessão dele, e manter um token próprio em
/// paralelo dobra a superfície de credencial. Sem campo onde guardar, não há
/// caminho de código que possa usá-lo.
public struct ClaudeCredentials: Sendable, Equatable {
    /// `nil` quando o usuário não autorizou a leitura do token, ou quando o
    /// item não o contém. O restante dos campos continua disponível: detectar
    /// o plano nunca exigiu credencial.
    public let accessToken: String?
    public let expiresAt: Date?
    public let rateLimitTier: String?

    public init(accessToken: String?, expiresAt: Date?, rateLimitTier: String?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.rateLimitTier = rateLimitTier
    }

    /// O token, se houver um e ele ainda valer. Vida útil medida em horas, então
    /// conferir aqui evita gastar uma chamada de rede que só pode voltar 401.
    public func usableToken(at now: Date) -> String? {
        guard let accessToken else { return nil }
        if let expiresAt, expiresAt <= now { return nil }
        return accessToken
    }
}

public protocol CredentialSource: Sendable {
    func credentials() -> ClaudeCredentials?
}
```

- [ ] **Step 4: Escrever `KeychainCredentialSource.swift`**

```swift
import Foundation
import Security

/// Lê o item de keychain que o Claude Code mantém.
///
/// **É o único ponto do app que toca esse item.** O `PlanDetector` consumia o
/// keychain por conta própria; passou a consumir daqui quando os dois leitores
/// passaram a precisar do mesmo segredo.
///
/// O item pertence ao Claude Code, então a primeira leitura pode abrir o
/// diálogo de autorização do macOS. Negar faz a leitura falhar e o app degrada
/// — nunca trava.
///
/// `load` é injetável para os testes exercitarem a decodificação sem keychain.
public struct KeychainCredentialSource: CredentialSource {
    public static let service = "Claude Code-credentials"

    /// Quando `false`, o `accessToken` **não é extraído do dicionário**. Não é
    /// leitura seguida de descarte: o campo simplesmente não é acessado, que é
    /// o que a promessa do app afirma.
    private let readsAccessToken: Bool
    private let load: @Sendable () -> Data?

    public init(readsAccessToken: Bool,
                load: @escaping @Sendable () -> Data? = KeychainCredentialSource.loadFromKeychain) {
        self.readsAccessToken = readsAccessToken
        self.load = load
    }

    public func credentials() -> ClaudeCredentials? {
        guard let data = load(),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              // Claude Code 2.1.x pode gravar só estado de MCP, sem esta chave.
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }

        return ClaudeCredentials(
            accessToken: readsAccessToken ? oauth["accessToken"] as? String : nil,
            // Milissegundos desde a época, como o Claude Code grava.
            expiresAt: (oauth["expiresAt"] as? Double)
                .map { Date(timeIntervalSince1970: $0 / 1000) },
            rateLimitTier: oauth["rateLimitTier"] as? String)
    }

    public static let loadFromKeychain: @Sendable () -> Data? = {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
        else { return nil }
        return item as? Data
    }
}
```

- [ ] **Step 5: Reescrever `PlanDetector.swift`**

Substituir o arquivo inteiro. A extensão `Plan.init?(rateLimitTier:)` fica idêntica — só o enum `PlanDetector` e o doc-comment mudam.

```swift
import Foundation

extension Plan {
    /// Mapeia o `rateLimitTier` que o Claude Code grava no keychain.
    ///
    /// Só `default_claude_max_5x` foi observado de verdade; as outras variantes
    /// são inferidas pela nomenclatura. Por isso o casamento é por trecho e não
    /// por igualdade: se a Anthropic mudar o prefixo, `enterprise_claude_max_5x`
    /// continua resolvendo.
    ///
    /// Tier desconhecido devolve `nil` em vez de chutar — um plano errado vira
    /// um múltiplo de retorno errado, e é melhor cair no seletor manual.
    public init?(rateLimitTier: String) {
        let tier = rateLimitTier.lowercased()
        if tier.contains("max_20x") { self = .max20 }
        else if tier.contains("max_5x") { self = .max5 }
        else if tier.contains("pro") { self = .pro }
        else { return nil }
    }
}

/// Lê o plano do item de keychain que o Claude Code já mantém.
///
/// **Lê exclusivamente `rateLimitTier`.** O mesmo item guarda `accessToken` e
/// `refreshToken`. O `accessToken` só é lido quando o usuário liga "Buscar
/// números ao vivo" nos Ajustes, e mesmo então apenas pelo
/// `KeychainCredentialSource` — este caminho passa `readsAccessToken: false` e
/// o campo nem chega a ser extraído. O `refreshToken` não tem leitor nenhum em
/// lugar algum do app: `ClaudeCredentials` não tem campo para ele.
///
/// A promessa aqui era absoluta e virou condicional quando a busca ao vivo
/// entrou. Condicional e verificável é o que ela pode ser sem mentir.
///
/// A primeira leitura dispara o prompt de keychain do macOS, porque o item
/// pertence ao Claude Code. Negar só faz a detecção falhar — o seletor manual
/// continua valendo.
public enum PlanDetector {
    public static func detect(
        source: any CredentialSource = KeychainCredentialSource(readsAccessToken: false)
    ) -> Plan? {
        guard let tier = source.credentials()?.rateLimitTier else { return nil }
        return Plan(rateLimitTier: tier)
    }
}
```

- [ ] **Step 6: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter CredentialSource`
Expected: PASS, 10 testes.

- [ ] **Step 7: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS. `PlanDetectionTests` continua verde sem alteração — `AppSettings` chama `PlanDetector.detect()` com o default, cuja assinatura não mudou do ponto de vista de quem chama.

- [ ] **Step 8: Commit**

```bash
git add Sources/CCUsageCore/Usage/CredentialSource.swift \
        Sources/CCUsageCore/Usage/KeychainCredentialSource.swift \
        Sources/CCUsageCore/Settings/PlanDetector.swift \
        Tests/CCUsageCoreTests/CredentialSourceTests.swift
git commit -m "feat: leitor unico do keychain, com o accessToken sob autorizacao

PlanDetector deixa de abrir o item por conta propria. ClaudeCredentials
nao tem campo para refreshToken: a ausencia e o que garante que o app
nunca renova OAuth."
```

---

## Task 4: `LiveUsageFetcher`

**Files:**
- Create: `Sources/CCUsageCore/Usage/LiveUsageFetcher.swift`
- Test: `Tests/CCUsageCoreTests/LiveUsageFetcherTests.swift`

**Interfaces:**
- Consumes: `UsageReport`, `UsageReportDecoder.decode(_:fetchedAt:)` (Task 1); `CredentialSource`, `ClaudeCredentials.usableToken(at:)` (Task 3)
- Produces:
  - `enum LiveUsageError: Error, Equatable { case noToken, unauthorized, transport, malformed }`
  - `LiveUsageFetcher(source: any CredentialSource, session: URLSession)` com `func fetch(at now: Date) async throws -> UsageReport`
  - `LiveUsageFetcher.endpoint: URL` e `LiveUsageFetcher.betaHeaderValue: String`

- [ ] **Step 1: Escrever o teste que falha**

Criar `Tests/CCUsageCoreTests/LiveUsageFetcherTests.swift`. O `URLProtocol` de teste guarda estado estático, então a suíte é `.serialized` — sem isso os testes paralelos do swift-testing corrompem um ao outro.

```swift
import Foundation
import Testing
@testable import CCUsageCore

/// Intercepta as requisições sem tocar a rede.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var result: Result<(Int, Data), Error> = .success((200, Data()))
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        switch Self.result {
        case let .success((status, data)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// Fonte de credencial controlada pelo teste — nunca toca o keychain.
private struct FakeCredentials: CredentialSource {
    var value: ClaudeCredentials?
    func credentials() -> ClaudeCredentials? { value }
}

private let validCredentials = ClaudeCredentials(
    accessToken: "sk-ant-oat-TESTE",
    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
    rateLimitTier: "default_claude_max_5x")

private let now = Date(timeIntervalSince1970: 1_787_000_000)

private func fetcher(_ credentials: ClaudeCredentials?) -> LiveUsageFetcher {
    LiveUsageFetcher(source: FakeCredentials(value: credentials), session: stubbedSession())
}

@Suite(.serialized)
struct LiveUsageFetcherTests {
    @Test func decodesASuccessfulResponse() async throws {
        StubURLProtocol.result = .success((200, Data(liveResponse.utf8)))
        let report = try await fetcher(validCredentials).fetch(at: now)
        #expect(report.session?.fraction == 0.06)
        #expect(report.weeklyAll?.fraction == 0.25)
        #expect(report.weeklyScoped.first?.modelName == "Fable")
        // Ao vivo, "quando foi buscado" é agora — não o carimbo de terceiro.
        #expect(report.fetchedAt == now)
    }

    @Test func sendsBothRequiredHeaders() async throws {
        // Sem `anthropic-beta` o endpoint não responde o formato esperado.
        StubURLProtocol.result = .success((200, Data(liveResponse.utf8)))
        _ = try await fetcher(validCredentials).fetch(at: now)

        let request = StubURLProtocol.lastRequest!
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat-TESTE")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.url == LiveUsageFetcher.endpoint)
    }

    @Test func unauthorizedIsItsOwnErrorNotAGenericFailure() async {
        // 401 é caminho normal, não exceção: o token vive horas. A UI precisa
        // distinguir "credencial expirada" de "sem rede" para dizer o que fazer.
        StubURLProtocol.result = .success((401, Data()))
        await #expect(throws: LiveUsageError.unauthorized) {
            try await fetcher(validCredentials).fetch(at: now)
        }
    }

    @Test func forbiddenIsTreatedAsUnauthorized() async {
        // Token sem o escopo `user:profile` recebe 403 em vez de 401, e a saída
        // para o usuário é a mesma: reautenticar pelo Claude Code.
        StubURLProtocol.result = .success((403, Data()))
        await #expect(throws: LiveUsageError.unauthorized) {
            try await fetcher(validCredentials).fetch(at: now)
        }
    }

    @Test func networkFailureIsTransport() async {
        StubURLProtocol.result = .failure(URLError(.timedOut))
        await #expect(throws: LiveUsageError.transport) {
            try await fetcher(validCredentials).fetch(at: now)
        }
    }

    @Test func garbageBodyIsMalformed() async {
        StubURLProtocol.result = .success((200, Data("{ isto não é json".utf8)))
        await #expect(throws: LiveUsageError.malformed) {
            try await fetcher(validCredentials).fetch(at: now)
        }
    }

    @Test func serverErrorIsMalformed() async {
        StubURLProtocol.result = .success((500, Data()))
        await #expect(throws: LiveUsageError.malformed) {
            try await fetcher(validCredentials).fetch(at: now)
        }
    }

    @Test func absentCredentialsSkipTheRequestEntirely() async {
        StubURLProtocol.lastRequest = nil
        await #expect(throws: LiveUsageError.noToken) {
            try await fetcher(nil).fetch(at: now)
        }
        #expect(StubURLProtocol.lastRequest == nil)
    }

    @Test func expiredTokenSkipsTheRequestEntirely() async {
        // Gastar rede num token morto só produz um 401 previsível.
        StubURLProtocol.lastRequest = nil
        let expired = ClaudeCredentials(
            accessToken: "sk-ant-oat-TESTE",
            expiresAt: Date(timeIntervalSince1970: 1_000_000_000),
            rateLimitTier: nil)
        await #expect(throws: LiveUsageError.noToken) {
            try await fetcher(expired).fetch(at: now)
        }
        #expect(StubURLProtocol.lastRequest == nil)
    }

    @Test func unauthorizedTokenReadingSkipsTheRequestEntirely() async {
        // Toggle desligado: `accessToken` é nil e nenhuma chamada acontece.
        StubURLProtocol.lastRequest = nil
        let unread = ClaudeCredentials(accessToken: nil, expiresAt: nil,
                                       rateLimitTier: "default_claude_max_5x")
        await #expect(throws: LiveUsageError.noToken) {
            try await fetcher(unread).fetch(at: now)
        }
        #expect(StubURLProtocol.lastRequest == nil)
    }
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `./Scripts/test.sh --filter LiveUsageFetcher`
Expected: FAIL — `cannot find 'LiveUsageFetcher' in scope`.

- [ ] **Step 3: Escrever `LiveUsageFetcher.swift`**

```swift
import Foundation

/// Por que a busca falhou. Cada caso vira uma frase diferente na UI, porque a
/// saída para o usuário é diferente: reautenticar, esperar, ou nada a fazer.
public enum LiveUsageError: Error, Equatable {
    /// Sem token legível, ou o token venceu. Nenhuma chamada foi feita.
    case noToken
    /// 401 ou 403. Caminho normal, não excepcional: o token vive horas.
    case unauthorized
    /// Rede indisponível.
    case transport
    /// Resposta que não dá para interpretar — inclui erro de servidor.
    case malformed
}

/// Busca os números de uso ao vivo, na mesma chamada que o próprio Claude Code
/// faz.
///
/// Existe porque o cache de `~/.claude.json` só se move quando o Claude Code
/// roda: numa medição real ele estava 13h defasado e reportava 35% numa janela
/// de 5h cujo valor verdadeiro era 6% — a janela inteira já tinha resetado.
///
/// Endpoint interno e indocumentado (a spec §5 C5): toda falha é tipada e quem
/// chama degrada para o cache.
public struct LiveUsageFetcher: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Obrigatório: sem ele o endpoint não responde o formato esperado.
    public static let betaHeaderValue = "oauth-2025-04-20"

    private let source: any CredentialSource
    private let session: URLSession

    public init(source: any CredentialSource, session: URLSession = .shared) {
        self.source = source
        self.session = session
    }

    public func fetch(at now: Date) async throws -> UsageReport {
        // Confere a validade antes de gastar rede: um token vencido só pode
        // voltar 401, e o usuário merece a frase certa mais rápido.
        guard let token = source.credentials()?.usableToken(at: now) else {
            throw LiveUsageError.noToken
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LiveUsageError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw LiveUsageError.malformed }
        // 403 chega quando o token não tem o escopo `user:profile`. A saída para
        // o usuário é a mesma do 401: reautenticar pelo Claude Code.
        if http.statusCode == 401 || http.statusCode == 403 { throw LiveUsageError.unauthorized }

        guard http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let report = UsageReportDecoder.decode(root, fetchedAt: now)
        else { throw LiveUsageError.malformed }

        return report
    }
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter LiveUsageFetcher`
Expected: PASS, 10 testes. Nenhum toca a rede — se algum demorar mais de um segundo, o `URLProtocol` não está instalado e a chamada está saindo de verdade.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore/Usage/LiveUsageFetcher.swift \
        Tests/CCUsageCoreTests/LiveUsageFetcherTests.swift
git commit -m "feat: busca ao vivo em /api/oauth/usage

Erros tipados porque cada um vira uma frase diferente na UI: 401 pede
reautenticacao, falha de rede pede espera. Token vencido nem gasta rede."
```

---

## Task 5: `UsageSourcePolicy`

**Files:**
- Create: `Sources/CCUsageCore/Usage/UsageSourcePolicy.swift`
- Test: `Tests/CCUsageCoreTests/UsageSourcePolicyTests.swift`

**Interfaces:**
- Consumes: `UsageReport` (Task 1), `LiveUsageError` (Task 4)
- Produces:
  - `enum UsageSourceStatus: Sendable, Equatable { case live(at: Date), cached(age: TimeInterval), credentialExpired(age: TimeInterval), liveUnavailable(age: TimeInterval), derivedOnly }`
  - `struct OfficialSource: Sendable, Equatable { let report: UsageReport; let isLive: Bool }`
  - `UsageSourcePolicy.select(liveEnabled:live:cached:now:) -> (source: OfficialSource?, status: UsageSourceStatus)`

- [ ] **Step 1: Escrever o teste que falha**

Criar `Tests/CCUsageCoreTests/UsageSourcePolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import CCUsageCore

private let policyNow = Date(timeIntervalSince1970: 1_787_000_000)

private func report(fraction: Double, agedBy age: TimeInterval) -> UsageReport {
    UsageReport(
        limits: [.init(kind: .session, fraction: fraction, severity: .normal,
                       resetsAt: nil, modelName: nil, isActive: true)],
        fetchedAt: policyNow.addingTimeInterval(-age))
}

private let liveReport = report(fraction: 0.06, agedBy: 0)
private let staleCache = report(fraction: 0.35, agedBy: 13 * 3600)

@Test func liveDisabledUsesTheCache() {
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: false, live: nil, cached: staleCache, now: policyNow)
    #expect(source?.report == staleCache)
    #expect(source?.isLive == false)
    #expect(status == .cached(age: 13 * 3600))
}

@Test func liveEnabledAndSuccessfulUsesTheLiveReport() {
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: .success(liveReport), cached: staleCache, now: policyNow)
    // O caso que motivou tudo: cache dizia 35%, ao vivo diz 6%.
    #expect(source?.report == liveReport)
    #expect(source?.isLive == true)
    #expect(status == .live(at: policyNow))
}

@Test func expiredCredentialFallsBackAndSaysSo() {
    for error in [LiveUsageError.noToken, .unauthorized] {
        let (source, status) = UsageSourcePolicy.select(
            liveEnabled: true, live: .failure(error), cached: staleCache, now: policyNow)
        #expect(source?.report == staleCache)
        #expect(status == .credentialExpired(age: 13 * 3600))
    }
}

@Test func networkFailureFallsBackWithADifferentStatus() {
    // Distinto de credencial expirada porque a saída do usuário é outra:
    // esperar, não reautenticar.
    for error in [LiveUsageError.transport, .malformed] {
        let (source, status) = UsageSourcePolicy.select(
            liveEnabled: true, live: .failure(error), cached: staleCache, now: policyNow)
        #expect(source?.report == staleCache)
        #expect(status == .liveUnavailable(age: 13 * 3600))
    }
}

@Test func noSourceAtAllFallsThroughToTheDerivedPath() {
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: .failure(.transport), cached: nil, now: policyNow)
    #expect(source == nil)
    #expect(status == .derivedOnly)
}

@Test func liveDisabledWithoutCacheFallsThroughToTheDerivedPath() {
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: false, live: nil, cached: nil, now: policyNow)
    #expect(source == nil)
    #expect(status == .derivedOnly)
}

@Test func liveEnabledButNotYetFetchedShowsTheCache() {
    // Primeira abertura: o toggle está ligado mas a chamada ainda não voltou.
    // Mostrar o cache é melhor que mostrar a estimativa derivada.
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: nil, cached: staleCache, now: policyNow)
    #expect(source?.report == staleCache)
    #expect(status == .cached(age: 13 * 3600))
}

@Test func cacheFromTheFutureIsClampedToZeroAge() {
    // Relógio ajustado para trás não pode produzir idade negativa, que
    // formataria como "há -2h".
    let future = report(fraction: 0.1, agedBy: -7200)
    let (_, status) = UsageSourcePolicy.select(
        liveEnabled: false, live: nil, cached: future, now: policyNow)
    #expect(status == .cached(age: 0))
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `./Scripts/test.sh --filter UsageSourcePolicy`
Expected: FAIL — `cannot find 'UsageSourcePolicy' in scope`.

- [ ] **Step 3: Escrever `UsageSourcePolicy.swift`**

```swift
import Foundation

/// De onde veio o número que está na tela, e o que fazer se não for o ideal.
///
/// Cada caso é uma frase diferente na UI porque cada um pede uma ação diferente
/// do usuário — ou nenhuma.
public enum UsageSourceStatus: Sendable, Equatable {
    case live(at: Date)
    case cached(age: TimeInterval)
    /// Cache em uso porque o token não serve. Saída: rodar o Claude Code.
    case credentialExpired(age: TimeInterval)
    /// Cache em uso porque a chamada falhou. Saída: esperar.
    case liveUnavailable(age: TimeInterval)
    /// Nenhuma fonte oficial; o `SnapshotBuilder` segue pelo caminho derivado.
    case derivedOnly
}

/// Relatório escolhido, com a origem que a UI precisa saber.
public struct OfficialSource: Sendable, Equatable {
    public let report: UsageReport
    public let isLive: Bool

    public init(report: UsageReport, isLive: Bool) {
        self.report = report
        self.isLive = isLive
    }
}

/// Escolhe entre a busca ao vivo e o cache.
///
/// Função pura, sem relógio próprio e sem I/O: `now` entra por parâmetro. É o
/// que torna as cinco combinações testáveis sem rede e sem keychain.
public enum UsageSourcePolicy {
    /// **Primeira condição que casar vence**, de cima para baixo. O último caso
    /// é o fundo do poço: qualquer linha acima que aponte para o cache cai nele
    /// quando o cache também está ausente.
    public static func select(
        liveEnabled: Bool,
        live: Result<UsageReport, LiveUsageError>?,
        cached: UsageReport?,
        now: Date
    ) -> (source: OfficialSource?, status: UsageSourceStatus) {
        if liveEnabled, case let .success(report)? = live {
            return (OfficialSource(report: report, isLive: true), .live(at: report.fetchedAt))
        }

        guard let cached else { return (nil, .derivedOnly) }
        let source = OfficialSource(report: cached, isLive: false)
        // Relógio ajustado para trás não pode produzir idade negativa.
        let age = max(0, now.timeIntervalSince(cached.fetchedAt))

        guard liveEnabled, case let .failure(error)? = live else {
            // Live desligado, ou ligado mas ainda sem resposta na primeira
            // abertura. Nos dois casos o cache é o melhor disponível e não há
            // nada de errado a relatar.
            return (source, .cached(age: age))
        }

        switch error {
        case .noToken, .unauthorized:
            return (source, .credentialExpired(age: age))
        case .transport, .malformed:
            return (source, .liveUnavailable(age: age))
        }
    }
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter UsageSourcePolicy`
Expected: PASS, 8 testes.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore/Usage/UsageSourcePolicy.swift \
        Tests/CCUsageCoreTests/UsageSourcePolicyTests.swift
git commit -m "feat: politica pura de selecao de fonte

Cinco casos, primeira condicao que casa vence. Credencial expirada e
falha de rede sao status distintos porque a saida do usuario e outra."
```

---
## Task 6: Modelo e `SnapshotBuilder` — a troca

A task que faz a substituição. Depois dela `OfficialUsage` não existe mais.

**Files:**
- Modify: `Sources/CCUsageCore/Models/UsageSnapshot.swift` (`Gauge` reescrito, `ScopedGauge` e `sourceStatus` novos)
- Modify: `Sources/CCUsageCore/SnapshotBuilder.swift:9-63` (assinatura e montagem dos medidores)
- Delete: `Sources/CCUsageCore/Parsing/OfficialUsageReader.swift`
- Delete: `Tests/CCUsageCoreTests/OfficialUsageReaderTests.swift` (cobertura já migrada na Task 2)
- Modify: `Tests/CCUsageCoreTests/SnapshotBuilderTests.swift:96-165`

**Interfaces:**
- Consumes: `UsageReport`, `UsageReport.Limit` (Task 1); `OfficialSource`, `UsageSourceStatus` (Task 5)
- Produces:
  - `UsageSnapshot.Provenance` — `.live(at: Date)` / `.cached(at: Date)` / `.derived`
  - `UsageSnapshot.Gauge.official(_ limit: UsageReport.Limit, from source: OfficialSource) -> Gauge`
  - `UsageSnapshot.Gauge.derived(tokens: UInt64, ceiling: UInt64, resetsAt: Date?) -> Gauge` (inalterada)
  - `UsageSnapshot.ScopedGauge` com `modelName: String` e `gauge: Gauge`
  - `UsageSnapshot.scopedWeekly: [ScopedGauge]` e `UsageSnapshot.sourceStatus: UsageSourceStatus`
  - `SnapshotBuilder.build(from:now:calendar:override:official:status:)`

- [ ] **Step 1: Reescrever a seção de leitura oficial dos testes**

Em `Tests/CCUsageCoreTests/SnapshotBuilderTests.swift`, substituir tudo a partir do comentário `// MARK: - Leitura oficial` (linha 94) até o fim do arquivo por:

```swift
// MARK: - Leitura oficial

private func limit(_ kind: UsageReport.Limit.Kind, _ fraction: Double,
                   resetsAt: Date? = nil, modelName: String? = nil,
                   isActive: Bool = false) -> UsageReport.Limit {
    UsageReport.Limit(kind: kind, fraction: fraction, severity: .normal,
                      resetsAt: resetsAt, modelName: modelName, isActive: isActive)
}

private func officialSource(_ limits: [UsageReport.Limit], fetchedAt: Date,
                            isLive: Bool = false) -> OfficialSource {
    OfficialSource(report: UsageReport(limits: limits, fetchedAt: fetchedAt), isLive: isLive)
}

@Test func officialReadingWinsOverTheDerivedBlock() {
    // A derivação não recupera a fase real da janela: o floor de hora perde até
    // 59 minutos por bloco e o erro acumula. Quando há oficial, ele manda.
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z", output: 500_000)],
        now: now, calendar: utc,
        override: Ceilings(blockTokens: 1_000_000),
        official: officialSource([limit(.session, 0.22, resetsAt: date("2026-08-17T15:20:00Z")),
                                  limit(.weeklyAll, 0.19)], fetchedAt: now),
        status: .cached(age: 0))

    #expect(snapshot.session.isOfficial)
    #expect(snapshot.session.rawFraction == 0.22)
    #expect(snapshot.session.resetsAt == date("2026-08-17T15:20:00Z"))
    // O derivado diria 50% e resetaria às 15:00 — descartado.
    #expect(snapshot.session.tokens == nil)
}

@Test func fallsBackToTheDerivedBlockWithoutOfficialData() {
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z", output: 500_000)],
        now: date("2026-08-17T12:00:00Z"), calendar: utc,
        override: Ceilings(blockTokens: 1_000_000), official: nil, status: .derivedOnly)

    #expect(snapshot.session.isOfficial == false)
    #expect(snapshot.session.provenance == .derived)
    #expect(snapshot.session.rawFraction == 0.5)
    #expect(snapshot.weekly == nil)   // semanal não é derivável
    #expect(snapshot.scopedWeekly.isEmpty)
}

@Test func weeklyExistsOnlyWithOfficialData() {
    let now = date("2026-08-17T12:00:00Z")
    let withOfficial = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.session, 0.22), limit(.weeklyAll, 0.19)],
                                 fetchedAt: now),
        status: .cached(age: 0))
    #expect(withOfficial.weekly?.rawFraction == 0.19)

    // Janela ausente no payload (vem null com frequência) não vira zero.
    let partial = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.session, 0.22)], fetchedAt: now),
        status: .cached(age: 0))
    #expect(partial.weekly == nil)
    #expect(partial.session.isOfficial)
}

@Test func cachedGaugeReportsItsAge() {
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.session, 0.22)],
                                 fetchedAt: date("2026-08-17T11:45:00Z")),
        status: .cached(age: 15 * 60))
    // Tipo explícito: `#expect` compara Optional<Double> com Int sem erro de
    // compilação e simplesmente devolve false.
    #expect(snapshot.session.age(at: now) == TimeInterval(15 * 60))
}

@Test func liveGaugeHasNoAgeToReport() {
    // Ao vivo a idade é de segundos e não é informação. Mostrá-la produziria um
    // "há 4s" permanente, que só ocupa espaço.
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.session, 0.06)], fetchedAt: now, isLive: true),
        status: .live(at: now))
    #expect(snapshot.session.provenance == .live(at: now))
    #expect(snapshot.session.age(at: now) == nil)
}

@Test func scopedWeeklyWindowsBecomeTheirOwnGauges() {
    // O B da spec: a janela por modelo é genérica, rotulada pelo nome que o
    // payload manda — o app não mantém lista de modelos.
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([
            limit(.session, 0.06),
            limit(.weeklyScoped, 0.44, modelName: "Opus", isActive: true),
            limit(.weeklyScoped, 0.12, modelName: "Fable"),
        ], fetchedAt: now, isLive: true),
        status: .live(at: now))

    #expect(snapshot.scopedWeekly.map(\.modelName) == ["Opus", "Fable"])
    #expect(snapshot.scopedWeekly.first?.gauge.rawFraction == 0.44)
    #expect(snapshot.scopedWeekly.first?.gauge.isActive == true)
}

@Test func scopedWindowWithoutAModelNameIsDropped() {
    // Sem nome não há rótulo, e uma barra anônima não diz de que é o teto.
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.weeklyScoped, 0.44)], fetchedAt: now),
        status: .cached(age: 0))
    #expect(snapshot.scopedWeekly.isEmpty)
}

@Test func theStatusTravelsWithTheSnapshot() {
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z")], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.session, 0.35)],
                                 fetchedAt: date("2026-08-16T23:00:00Z")),
        status: .credentialExpired(age: 13 * 3600))
    #expect(snapshot.sourceStatus == .credentialExpired(age: 13 * 3600))
}
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `./Scripts/test.sh --filter SnapshotBuilder`
Expected: FAIL na compilação — `cannot find 'OfficialSource'`, `extra argument 'status'`.

- [ ] **Step 3: Reescrever a `Gauge` em `UsageSnapshot.swift`**

Substituir a declaração de `Gauge` (linhas 5-45 do arquivo atual) por:

```swift
    /// De onde este medidor veio. Três estados, não dois: o cache do Claude
    /// Code é oficial *e* pode estar horas defasado, e essas são perguntas
    /// diferentes.
    public enum Provenance: Sendable, Equatable {
        case live(at: Date)
        case cached(at: Date)
        case derived
    }

    /// Um medidor de janela.
    public struct Gauge: Sendable, Equatable {
        /// Razão real, sem saturação. Passa de 1 quando o consumo supera o
        /// denominador — e é aí que o número mais informa.
        public let rawFraction: Double
        public let resetsAt: Date?
        public let provenance: Provenance
        /// Gravidade como o servidor a classifica. `nil` no caminho derivado,
        /// que não tem servidor a consultar.
        public let severity: UsageReport.Limit.Severity?
        /// A janela que a Anthropic considera a que aperta agora.
        public let isActive: Bool
        /// Tokens e teto existem apenas no caminho derivado; o oficial devolve
        /// percentual pronto e não expõe os absolutos.
        public let tokens: UInt64?
        public let ceiling: UInt64?

        public var isOfficial: Bool { provenance != .derived }

        /// Saturada em 1, para a barra de progresso — que não pode encher além
        /// do fim.
        public var fraction: Double { min(1.0, rawFraction) }

        public func timeRemaining(at now: Date) -> TimeInterval? {
            guard let resetsAt else { return nil }
            return max(0, resetsAt.timeIntervalSince(now))
        }

        /// Há quanto tempo o dado foi buscado — **só faz sentido no cache**, que
        /// só se move quando o Claude Code roda. Ao vivo a idade é de segundos e
        /// mostrá-la produziria um "há 4s" permanente; derivado não tem busca.
        public func age(at now: Date) -> TimeInterval? {
            guard case let .cached(at) = provenance else { return nil }
            return max(0, now.timeIntervalSince(at))
        }

        public static func official(_ limit: UsageReport.Limit,
                                    from source: OfficialSource) -> Gauge {
            Gauge(rawFraction: limit.fraction,
                  resetsAt: limit.resetsAt,
                  provenance: source.isLive
                      ? .live(at: source.report.fetchedAt)
                      : .cached(at: source.report.fetchedAt),
                  severity: limit.severity,
                  isActive: limit.isActive,
                  tokens: nil, ceiling: nil)
        }

        public static func derived(tokens: UInt64, ceiling: UInt64, resetsAt: Date?) -> Gauge {
            Gauge(rawFraction: ceiling > 0 ? Double(tokens) / Double(ceiling) : 0,
                  resetsAt: resetsAt, provenance: .derived, severity: nil, isActive: false,
                  tokens: tokens, ceiling: ceiling)
        }
    }

    /// Uma janela semanal presa a um modelo. O rótulo vem do payload — o app
    /// não mantém lista de nomes de modelo, porque essa lista envelhece.
    public struct ScopedGauge: Sendable, Equatable {
        public let modelName: String
        public let gauge: Gauge

        public init(modelName: String, gauge: Gauge) {
            self.modelName = modelName
            self.gauge = gauge
        }
    }
```

- [ ] **Step 4: Adicionar os campos novos ao `UsageSnapshot`**

Em `UsageSnapshot`, depois de `public let weekly: Gauge?`, adicionar:

```swift
    /// Janelas semanais por modelo, na ordem do payload. Vazio quando não há
    /// nenhuma — que é o caso mais comum.
    public let scopedWeekly: [ScopedGauge]
```

E depois de `public let generatedAt: Date`, adicionar:

```swift
    /// De onde vieram os números, incluindo os estados de falha. A UI diz isso
    /// em vez de mostrar um número sem procedência.
    public let sourceStatus: UsageSourceStatus
```

Atualizar o `init` para receber e atribuir os dois (`scopedWeekly` logo após `weekly`, `sourceStatus` ao final), e o `empty(at:)` para passar `scopedWeekly: []` e `sourceStatus: .derivedOnly`.

- [ ] **Step 5: Trocar a montagem no `SnapshotBuilder.swift`**

Substituir a assinatura e o bloco dos medidores:

```swift
    public static func build(
        from events: [UsageEvent],
        now: Date,
        calendar: Calendar = .current,
        override: Ceilings?,
        official: OfficialSource? = nil,
        status: UsageSourceStatus = .derivedOnly
    ) -> UsageSnapshot {
```

E, no lugar do bloco que hoje monta `sessionGauge` e `weeklyGauge`:

```swift
        // O número oficial vence sempre que existe: ele traz a fase real da
        // janela, que a derivação não recupera — o floor de hora perde até 59
        // minutos por bloco e o erro acumula ao longo da cadeia.
        //
        // Sem oficial, o medidor derivado vem zerado em vez de ausente quando
        // não há bloco ativo: acabou de resetar é justamente quando "0% de
        // quanto" informa mais.
        let sessionGauge: UsageSnapshot.Gauge
        if let official, let session = official.report.session {
            sessionGauge = .official(session, from: official)
        } else {
            sessionGauge = .derived(tokens: active?.tokens ?? 0,
                                    ceiling: ceilings.blockTokens,
                                    resetsAt: active?.end)
        }

        // A janela semanal da Anthropic tem reset próprio e não é derivável do
        // histórico local; sem oficial, a UI cai no múltiplo do ritmo típico.
        let weeklyGauge = official.flatMap { source in
            source.report.weeklyAll.map { UsageSnapshot.Gauge.official($0, from: source) }
        }

        // Janela sem nome de modelo é descartada: uma barra anônima não diz de
        // que é o teto que ela mede.
        let scoped = official.map { source in
            source.report.weeklyScoped.compactMap { limit in
                limit.modelName.map {
                    UsageSnapshot.ScopedGauge(modelName: $0,
                                              gauge: .official(limit, from: source))
                }
            }
        } ?? []
```

E, no `return UsageSnapshot(...)`, passar `scopedWeekly: scoped` logo depois de `weekly:` e `sourceStatus: status` ao final.

- [ ] **Step 6: Apagar o leitor antigo**

```bash
git rm Sources/CCUsageCore/Parsing/OfficialUsageReader.swift \
       Tests/CCUsageCoreTests/OfficialUsageReaderTests.swift
```

O `UsageStore.swift` ainda referencia `OfficialUsageReader` e vai parar de compilar. Corrigir de forma mínima aqui — a fiação completa é a Task 8. Em `UsageStore.swift`, trocar o default do parâmetro `officialUsageURL` de `OfficialUsageReader.defaultURL` para `CachedUsageReader.defaultURL`, e o corpo de `rebuild()` por:

```swift
    private func rebuild() {
        // Relido a cada reconstrução: o arquivo é pequeno e o cache oficial se
        // move sozinho enquanto o Claude Code roda.
        let cached = CachedUsageReader.read(from: officialUsageURL)
        let (official, status) = UsageSourcePolicy.select(
            liveEnabled: false, live: nil, cached: cached, now: Date())
        snapshot = SnapshotBuilder.build(
            from: events, now: Date(), calendar: .current,
            override: ceilingOverride, official: official, status: status)
    }
```

- [ ] **Step 7: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter SnapshotBuilder`
Expected: PASS, 9 testes na seção oficial.

- [ ] **Step 8: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS. Se `UsageStoreTests` falhar, é porque construía snapshot pela API antiga — ajustar as chamadas para a nova assinatura, sem mudar o que cada teste afirma.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: snapshot passa a falar UsageReport, com procedencia de tres estados

Gauge troca isOfficial booleano por provenance live/cached/derived: o
cache e oficial E pode estar horas defasado, e isso sao duas perguntas.
age() passa a existir so no cache. OfficialUsageReader sai."
```

---

## Task 7: O toggle nos Ajustes

**Files:**
- Modify: `Sources/CCUsageCore/Settings/AppSettings.swift:52-99`
- Test: `Tests/CCUsageCoreTests/AppSettingsTests.swift` (acrescentar ao final)

**Interfaces:**
- Consumes: nada de tasks anteriores
- Produces: `AppSettings.liveUsageEnabled: Bool`, persistido, default `false`

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar ao final de `Tests/CCUsageCoreTests/AppSettingsTests.swift`:

```swift
@MainActor
@Test func liveUsageIsOffUntilTheUserSaysOtherwise() {
    // O app passa a depender de credencial de outro app. Isso é escolha do
    // usuário, não default.
    let settings = AppSettings(defaults: freshDefaults(), detectPlan: { nil })
    #expect(settings.liveUsageEnabled == false)
}

@MainActor
@Test func liveUsageChoiceSurvivesRestart() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults, detectPlan: { nil })
    first.liveUsageEnabled = true

    let restarted = AppSettings(defaults: defaults, detectPlan: { nil })
    #expect(restarted.liveUsageEnabled)
}

@MainActor
@Test func settingsSavedBeforeTheToggleExistedStayOff() {
    // Payload gravado por uma versão anterior não tem o campo. Ausência não
    // pode virar "ligado" — seria autorizar a leitura do token sem perguntar.
    let defaults = freshDefaults()
    let legacy = #"{"plan":"max5"}"#
    defaults.set(Data(legacy.utf8), forKey: AppSettings.storageKey)

    let settings = AppSettings(defaults: defaults, detectPlan: { nil })
    #expect(settings.plan == .max5)
    #expect(settings.liveUsageEnabled == false)
}
```

> `AppSettingsTests.swift` já declara `private func freshDefaults()` na linha 5. Use essa — não redeclarar. (A cópia em `PlanDetectionTests.swift` é `private` e **não** é visível daqui.)

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `./Scripts/test.sh --filter liveUsage`
Expected: FAIL — `value of type 'AppSettings' has no member 'liveUsageEnabled'`.

- [ ] **Step 3: Implementar**

Em `AppSettings`, depois de `manualBlockCeiling`, adicionar:

```swift
    /// Liga a busca ao vivo em `/api/oauth/usage`.
    ///
    /// Desligado por padrão, e por decisão explícita: ligado, o app lê o
    /// `accessToken` que o Claude Code guarda no keychain. Depender da
    /// credencial de outro app é escolha do usuário, e ausência de escolha não
    /// pode ser lida como consentimento.
    public var liveUsageEnabled: Bool {
        didSet { save() }
    }
```

No `Payload`:

```swift
    private struct Payload: Codable {
        var plan: Plan
        var manualBlockCeiling: UInt64?
        /// Ausente em payload gravado antes deste campo existir. `nil` resolve
        /// para `false` no init — nunca para ligado.
        var liveUsageEnabled: Bool?
    }
```

No `init`, depois de `self.manualBlockCeiling = stored?.manualBlockCeiling`:

```swift
        self.liveUsageEnabled = stored?.liveUsageEnabled ?? false
```

No `save()`:

```swift
        let payload = Payload(plan: plan, manualBlockCeiling: manualBlockCeiling,
                              liveUsageEnabled: liveUsageEnabled)
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter AppSettings`
Expected: PASS.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore/Settings/AppSettings.swift \
        Tests/CCUsageCoreTests/AppSettingsTests.swift
git commit -m "feat: toggle de busca ao vivo, desligado por padrao

Payload antigo sem o campo resolve para desligado: ausencia de escolha
nao e consentimento para ler a credencial."
```

---
## Task 8: Fiação no `UsageStore`

**Files:**
- Modify: `Sources/CCUsageCore/UsageStore.swift` (init, `liveUsageEnabled`, `refreshLive()`, `panelDidOpen()`, ticker, `rebuild()`)
- Test: `Tests/CCUsageCoreTests/UsageStoreTests.swift` (acrescentar ao final)

**Interfaces:**
- Consumes: `CachedUsageReader.read(from:)` (Task 2), `KeychainCredentialSource` (Task 3), `LiveUsageFetcher`, `LiveUsageError` (Task 4), `UsageSourcePolicy.select(liveEnabled:live:cached:now:)` (Task 5), `SnapshotBuilder.build(...:official:status:)` (Task 6)
- Produces: `UsageStore.LiveFetch` (typealias), `UsageStore.liveUsageEnabled: Bool`, `UsageStore.refreshLive() async`, `UsageStore.panelDidOpen()`

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar ao final de `Tests/CCUsageCoreTests/UsageStoreTests.swift`:

```swift
// MARK: - Fonte ao vivo

/// Cache gravado em disco com a idade que o teste quiser.
private func writeCache(_ fraction: Double, agedBy age: TimeInterval, at url: URL) throws {
    let percent = Int(fraction * 100)
    let fetchedAtMs = (Date().addingTimeInterval(-age).timeIntervalSince1970 * 1000)
        .rounded()
    let json = """
    { "cachedUsageUtilization": { "fetchedAtMs": \(Int(fetchedAtMs)),
        "utilization": { "limits": [ { "kind": "session", "percent": \(percent),
          "severity": "normal", "is_active": true } ] } } }
    """
    try json.write(to: url, atomically: true, encoding: .utf8)
}

private func liveReportSaying(_ fraction: Double) -> UsageReport {
    UsageReport(limits: [.init(kind: .session, fraction: fraction, severity: .normal,
                               resetsAt: nil, modelName: nil, isActive: true)],
                fetchedAt: Date())
}

@MainActor
@Test func liveReadingReplacesTheStaleCache() async throws {
    // O caso que motivou a mudança: cache de 13h dizendo 35% enquanto o valor
    // real é 6%.
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheFile = root.appending(path: "claude.json")
    try writeCache(0.35, agedBy: 13 * 3600, at: cacheFile)

    let store = UsageStore(scanner: ProjectScanner(root: root),
                           cacheURL: root.appending(path: "cache.json"),
                           cachedUsageURL: cacheFile,
                           liveUsageEnabled: true,
                           fetchLive: { _ in liveReportSaying(0.06) })
    await store.refresh()
    await store.refreshLive()

    #expect(store.snapshot.session.rawFraction == 0.06)
    if case .live = store.snapshot.sourceStatus {} else {
        Issue.record("esperava status ao vivo, veio \(store.snapshot.sourceStatus)")
    }
}

@MainActor
@Test func expiredCredentialFallsBackToTheCacheAndSaysSo() async throws {
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheFile = root.appending(path: "claude.json")
    try writeCache(0.35, agedBy: 13 * 3600, at: cacheFile)

    let store = UsageStore(scanner: ProjectScanner(root: root),
                           cacheURL: root.appending(path: "cache.json"),
                           cachedUsageURL: cacheFile,
                           liveUsageEnabled: true,
                           fetchLive: { _ in throw LiveUsageError.unauthorized })
    await store.refresh()
    await store.refreshLive()

    #expect(store.snapshot.session.rawFraction == 0.35)
    if case .credentialExpired = store.snapshot.sourceStatus {} else {
        Issue.record("esperava credencial expirada, veio \(store.snapshot.sourceStatus)")
    }
}

@MainActor
@Test func theFetcherIsNeverCalledWhileTheToggleIsOff() async throws {
    // A garantia que sustenta a promessa reescrita do PlanDetector: desligado,
    // nada chama a rede e nada lê o token.
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheFile = root.appending(path: "claude.json")
    try writeCache(0.35, agedBy: 60, at: cacheFile)

    final class Counter: @unchecked Sendable { var calls = 0 }
    let counter = Counter()

    let store = UsageStore(scanner: ProjectScanner(root: root),
                           cacheURL: root.appending(path: "cache.json"),
                           cachedUsageURL: cacheFile,
                           liveUsageEnabled: false,
                           fetchLive: { _ in
                               counter.calls += 1
                               return liveReportSaying(0.06)
                           })
    await store.refresh()
    await store.refreshLive()
    store.panelDidOpen()

    #expect(counter.calls == 0)
    #expect(store.snapshot.session.rawFraction == 0.35)
}
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `./Scripts/test.sh --filter UsageStore`
Expected: FAIL — `extra argument 'cachedUsageURL'`, `no member 'refreshLive'`.

- [ ] **Step 3: Implementar no `UsageStore.swift`**

Trocar as propriedades e o init:

```swift
    /// Como buscar os números ao vivo. Injetável para os testes exercitarem
    /// sucesso, 401 e falha de rede sem tocar keychain nem rede.
    public typealias LiveFetch = @Sendable (Date) async throws -> UsageReport

    /// Liga a busca ao vivo. Ligar dispara uma busca imediata; desligar
    /// descarta o último resultado, para a UI voltar ao cache na hora em vez de
    /// continuar mostrando um número que o usuário acabou de desautorizar.
    public var liveUsageEnabled: Bool {
        didSet {
            guard liveUsageEnabled != oldValue else { return }
            lastLive = nil
            rebuild()
            if liveUsageEnabled { Task { await refreshLive() } }
        }
    }

    private let cachedUsageURL: URL
    private let fetchLive: LiveFetch
    private var lastLive: Result<UsageReport, LiveUsageError>?
    private var lastLiveAttempt: Date?
    private var liveTicker: Task<Void, Never>?

    /// O `KeychainCredentialSource` que lê o token é construído **aqui e só
    /// aqui**, dentro de um caminho que nunca roda com o toggle desligado.
    public static let defaultLiveFetch: LiveFetch = { now in
        try await LiveUsageFetcher(
            source: KeychainCredentialSource(readsAccessToken: true)).fetch(at: now)
    }

    public init(
        scanner: ProjectScanner = ProjectScanner(),
        cacheURL: URL = ParseCache.defaultURL,
        cachedUsageURL: URL = CachedUsageReader.defaultURL,
        lookback: TimeInterval = 90 * 24 * 60 * 60,
        liveUsageEnabled: Bool = false,
        fetchLive: @escaping LiveFetch = UsageStore.defaultLiveFetch
    ) {
        self.scanner = scanner
        self.cacheURL = cacheURL
        self.cachedUsageURL = cachedUsageURL
        self.lookback = lookback
        self.liveUsageEnabled = liveUsageEnabled
        self.fetchLive = fetchLive
        self.snapshot = .empty(at: Date())
    }
```

> Remover a propriedade `officialUsageURL` e seu parâmetro — `cachedUsageURL` a substitui.

Acrescentar os métodos novos:

```swift
    /// Busca os números ao vivo. Guarda o resultado — inclusive o erro — porque
    /// a política precisa distinguir "ainda não busquei" de "busquei e falhou".
    public func refreshLive() async {
        guard liveUsageEnabled else { return }
        let now = Date()
        lastLiveAttempt = now
        do {
            lastLive = .success(try await fetchLive(now))
        } catch let error as LiveUsageError {
            lastLive = .failure(error)
        } catch {
            lastLive = .failure(.transport)
        }
        rebuild()
    }

    /// O painel abriu. Vale uma busca fora de hora: custa uma requisição e paga
    /// com um número que não está cinco minutos velho.
    ///
    /// Represado em 30s porque abrir e fechar o menu é gesto barato, e uma
    /// rajada de requisições por isso não é.
    public func panelDidOpen() {
        if let lastLiveAttempt, Date().timeIntervalSince(lastLiveAttempt) < 30 { return }
        Task { await refreshLive() }
    }
```

Em `start()`, depois do `ticker`, acrescentar:

```swift
        // Cadência fixa por ora. A política adaptativa (bateria, pressão
        // térmica, ociosidade) encaixa aqui trocando a constante por uma
        // função, sem mexer no resto.
        liveTicker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLive()
                try? await Task.sleep(for: .seconds(300))
            }
        }
```

Em `stop()`:

```swift
        liveTicker?.cancel()
        liveTicker = nil
```

E `rebuild()` por inteiro:

```swift
    private func rebuild() {
        let now = Date()
        // Relido a cada reconstrução: o arquivo é pequeno e o cache se move
        // sozinho enquanto o Claude Code roda.
        let cached = CachedUsageReader.read(from: cachedUsageURL)
        let (official, status) = UsageSourcePolicy.select(
            liveEnabled: liveUsageEnabled, live: lastLive, cached: cached, now: now)
        snapshot = SnapshotBuilder.build(
            from: events, now: now, calendar: .current,
            override: ceilingOverride, official: official, status: status)
    }
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `./Scripts/test.sh --filter UsageStore`
Expected: PASS.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore/UsageStore.swift Tests/CCUsageCoreTests/UsageStoreTests.swift
git commit -m "feat: store busca ao vivo com cadencia de 5min e cache como fallback

O KeychainCredentialSource que le o token e construido num unico ponto,
dentro de um caminho que nunca roda com o toggle desligado."
```

---

## Task 9: UI — procedência, janelas por modelo e o toggle

Sem teste unitário: o repositório não testa views. A verificação é compilar, empacotar e olhar.

**Files:**
- Modify: `Sources/ClaudeTokenCounter/Panel/UsagePanel.swift:24-71`
- Modify: `Sources/ClaudeTokenCounter/Settings/SettingsView.swift` (seção nova)
- Modify: `Sources/ClaudeTokenCounter/App.swift` (ponte do toggle e `panelDidOpen`)

**Interfaces:**
- Consumes: `UsageSnapshot.sourceStatus`, `UsageSnapshot.scopedWeekly`, `UsageSnapshot.Gauge.provenance` (Task 6); `AppSettings.liveUsageEnabled` (Task 7); `UsageStore.liveUsageEnabled`, `UsageStore.panelDidOpen()` (Task 8)
- Produces: nada consumido por tasks posteriores

- [ ] **Step 1: Trocar o rótulo binário pela linha de procedência**

Em `UsagePanel.swift`, substituir o bloco `if snapshot.session.isOfficial { … } else { … }` (final de `sessionSection`) por `provenanceRow`, e acrescentar:

```swift
    /// De onde vieram os números. Substitui o rótulo binário anterior, que só
    /// sabia dizer "oficial" ou "estimado" — e chamava de oficial um cache que
    /// podia estar treze horas atrasado.
    private var provenanceRow: some View {
        let (text, icon, isWarning) = provenance
        return Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(isWarning ? UsageColor.warning : .tertiary)
    }

    private var provenance: (String, String, Bool) {
        switch snapshot.sourceStatus {
        case .live:
            return ("ao vivo", "bolt.horizontal.circle", false)
        case let .cached(age):
            // Uma hora é 20% de uma janela de 5h. Cache mais velho que isso já
            // pode estar descrevendo uma sessão que resetou — foi exatamente o
            // estado que mostrava 35% quando o valor real era 6%.
            return age < 3600
                ? ("cache do Claude Code · há \(Format.duration(age))", "clock", false)
                : ("cache defasada · há \(Format.duration(age))", "exclamationmark.triangle", true)
        case let .credentialExpired(age):
            return ("credencial expirada · rode o Claude Code (cache de há \(Format.duration(age)))",
                    "exclamationmark.triangle", true)
        case let .liveUnavailable(age):
            return ("sem conexão · cache de há \(Format.duration(age))", "wifi.slash", true)
        case .derivedOnly:
            return ("estimado do seu histórico", "info.circle", false)
        }
    }
```

- [ ] **Step 2: Tirar a idade do `resetDetail`**

A linha de procedência agora é dona da idade. Mantê-la nos dois lugares repete a mesma informação com formatações diferentes. Em `resetDetail`, remover o bloco:

```swift
        // A idade importa: o cache oficial só se move quando o Claude Code roda.
        if let age = gauge.age(at: snapshot.generatedAt), age > 120 {
            text += " · lido há \(Format.duration(age))"
        }
```

- [ ] **Step 3: Adicionar as janelas por modelo**

Em `sessionSection`, logo depois do bloco `if let weekly = snapshot.weekly { … } else { … }`:

```swift
            // Só as que dizem algo. Uma linha "Fable 0%" permanente é ruído: a
            // janela existe no payload mas não informa nada.
            ForEach(snapshot.scopedWeekly.filter { $0.gauge.isActive || $0.gauge.rawFraction > 0 },
                    id: \.modelName) { scoped in
                gauge(title: scoped.modelName,
                      gauge: scoped.gauge,
                      detail: resetDetail(scoped.gauge))
            }
```

- [ ] **Step 4: Adicionar a seção nos Ajustes**

Em `SettingsView.swift`, entre a seção "Plano" e "Teto do bloco de 5h":

```swift
            Section("Números de uso") {
                Toggle("Buscar ao vivo", isOn: $settings.liveUsageEnabled)
                Text(settings.liveUsageEnabled
                     ? "O app lê o token de acesso que o Claude Code guarda no keychain "
                       + "e consulta a API da Anthropic a cada 5 minutos. O macOS pode "
                       + "pedir autorização na primeira leitura."
                     : "Desligado, o app usa o número que o Claude Code deixou em cache — "
                       + "que só se atualiza quando ele roda, e pode estar horas atrasado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 5: Ligar as pontas no `App.swift`**

No `init()`, depois de `Self.store.ceilingOverride = …`:

```swift
        Self.store.liveUsageEnabled = Self.settings.liveUsageEnabled
```

No `MenuBarExtra`, avisar o store quando o painel aparece:

```swift
        MenuBarExtra {
            UsagePanel(snapshot: Self.store.snapshot, plan: Self.settings.plan)
                .onAppear { Self.store.panelDidOpen() }
        } label: {
```

E, na cena `Settings`, uma segunda ponte ao lado da que já existe para o teto:

```swift
                .onChange(of: Self.settings.liveUsageEnabled) { _, enabled in
                    Self.store.liveUsageEnabled = enabled
                }
```

- [ ] **Step 6: Compilar**

Run: `swift build --package-path . -Xswiftc -target -Xswiftc arm64-apple-macos26.0`
Expected: build sem erro. Se `.tertiary` reclamar em `foregroundStyle`, trocar por `HierarchicalShapeStyle.tertiary`.

- [ ] **Step 7: Rodar a suíte inteira**

Run: `./Scripts/test.sh`
Expected: PASS.

- [ ] **Step 8: Empacotar e olhar**

```bash
./Scripts/bundle.sh
open dist/ClaudeTokenCounter.app
```

Conferir na ordem:
1. Painel abre com o rótulo de procedência dizendo "cache do Claude Code · há Xm" ou "cache defasada".
2. Ajustes → Números de uso → ligar "Buscar ao vivo". O macOS pode pedir autorização de keychain; permitir.
3. Voltar ao painel: o rótulo vira "ao vivo" e o percentual da sessão muda se o cache estava velho.
4. Desligar o toggle: o rótulo volta ao cache na hora, sem precisar reabrir.

- [ ] **Step 9: Commit**

```bash
git add Sources/ClaudeTokenCounter/
git commit -m "feat: linha de procedencia, janelas por modelo e toggle nos ajustes

Cache com mais de 1h vira aviso visivel em vez de nota de rodape: era
justamente o estado que mostrava 35% quando o valor real era 6%."
```

---

## Verificação final

- [ ] `./Scripts/test.sh` — suíte inteira verde
- [ ] `grep -rn "OfficialUsage" Sources/ Tests/` — sem resultado; o tipo antigo saiu por completo
- [ ] `grep -rn "refreshToken" Sources/` — sem resultado; nenhum leitor, em lugar nenhum
- [ ] `grep -rn "accessToken" Sources/` — resultado **único**, em `KeychainCredentialSource.swift`
- [ ] `grep -rn "import SwiftUI\|import AppKit" Sources/CCUsageCore/` — sem resultado; o core continua sem UI
- [ ] `./Scripts/bundle.sh && open dist/ClaudeTokenCounter.app` — o roteiro visual da Task 9 Step 8
- [ ] Com o toggle ligado, confirmar contra a verdade: `python3 -c "import json,subprocess;..."` não é necessário — basta comparar o percentual do painel com o que o `/usage` do Claude Code mostra. Devem bater.

## O que este plano deixa para depois

Nomeado para não voltar como escopo acidental: política de refresh adaptativa (bateria, pressão térmica, ociosidade), barra de menu configurável e métrica `is_active`, notificações de quota e reset, `extra_usage` e `spend`, Admin API, e distribuição (Sparkle, Homebrew, CLI). A spec §13 é a lista completa.
