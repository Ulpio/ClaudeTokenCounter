# ClaudeTokenCounter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App nativo de menu bar em macOS que lê os logs locais do Claude Code e mostra risco de teto (bloco de 5h, janela de 7 dias) e valor equivalente em API (hoje/semana/mês).

**Architecture:** Duas camadas num único SwiftPM package. `CCUsageCore` é uma library sem nenhum `import SwiftUI` — parser, pricing, agregação e o snapshot final, tudo testável por CLI. `ClaudeTokenCounter` é um executable que só desenha um `UsageSnapshot` pronto num `MenuBarExtra`. A shell nunca vê JSONL, bloco ou preço.

**Tech Stack:** Swift 6.4 (Command Line Tools, **sem Xcode**), SwiftPM, swift-testing, SwiftUI `MenuBarExtra` + Liquid Glass (`.glassEffect`), `DispatchSource` para file watching.

**Spec:** `docs/superpowers/specs/2026-08-17-claude-token-counter-design.md`

## Global Constraints

- **Deployment target: macOS 26.0.** `Package.swift` declara `.macOS("26.0")`. `.glassEffect` e `.menuBarExtraStyle(.window)` exigem isso.
- **Swift tools 6.0, modo de linguagem Swift 6** — concorrência estrita. Todo tipo compartilhado é `Sendable`; tipos Foundation não-Sendable (`JSONDecoder`) usam `nonisolated(unsafe)` com comentário justificando.
- **`CCUsageCore` NUNCA importa SwiftUI/AppKit.** Se um teste precisa de UI para rodar, a lógica está na camada errada.
- **Sem Xcode.** Build é `swift build`; o `.app` é montado por `Scripts/bundle.sh`. Nada de `xcodebuild`.
- **Testes rodam por `./Scripts/test.sh`, não por `swift test` puro.** Descoberto na Task 1: o toolchain só-CLT traz o swift-testing mas não o conecta — o plugin de macros fica fora do plugin path e `Testing.framework` / `lib_TestingInterop.dylib` ficam fora do rpath do bundle. O script injeta os três caminhos quando detecta o layout do CLT. Onde as tasks abaixo dizem `swift test ...`, leia `./Scripts/test.sh ...` (os argumentos são repassados, então `--filter` funciona igual).
- **Dinheiro é `Decimal`, nunca `Double`.** Literais decimais via `Decimal(sign:exponent:significand:)` ou inteiros — nunca literal de ponto flutuante (passa por `Double` e perde precisão).
- **Custo desconhecido nunca vira zero.** Modelo não reconhecido marca `Money.isPartial = true` e preserva a soma parcial.
- **Preço é função de (modelo, data).** Sonnet 5 custa $2/$10 até 2026-08-31 e $3/$15 a partir de 2026-09-01.
- **Fonte de dados:** `~/.claude/projects/**/*.jsonl`, append-only, somente leitura. O app nunca escreve nesse diretório.
- **Commits:** sem linha `Co-Authored-By`.

---

### Task 1: Fundação — Package, ModelID, Money, UsageEvent

**Files:**
- Create: `Package.swift`
- Create: `Sources/CCUsageCore/Models/ModelID.swift`
- Create: `Sources/CCUsageCore/Models/Money.swift`
- Create: `Sources/CCUsageCore/Models/UsageEvent.swift`
- Create: `Sources/ClaudeTokenCounter/App.swift` (stub, só para o package compilar)
- Test: `Tests/CCUsageCoreTests/ModelIDTests.swift`
- Test: `Tests/CCUsageCoreTests/MoneyTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `ModelID` (enum com `init(raw: String)`), `Money` (struct com `usd: Decimal`, `isPartial: Bool`, `+`, `add(cost: Decimal?)`, `.zero`), `UsageEvent` (struct com `timestamp/model/isFast/input/output/cacheWrite5m/cacheWrite1h/cacheRead/dedupeKey` e `totalTokens: UInt64`).

- [ ] **Step 1: Criar `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeTokenCounter",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CCUsageCore"),
        .executableTarget(name: "ClaudeTokenCounter", dependencies: ["CCUsageCore"]),
        .testTarget(name: "CCUsageCoreTests", dependencies: ["CCUsageCore"]),
    ]
)
```

- [ ] **Step 2: Criar o stub do executable em `Sources/ClaudeTokenCounter/App.swift`**

Precisa existir para `swift build` não falhar com target vazio. Vira o app de verdade na Task 10.

```swift
import SwiftUI

@main
struct ClaudeTokenCounterApp: App {
    var body: some Scene {
        MenuBarExtra("ClaudeTokenCounter", systemImage: "bolt.horizontal") {
            Text("em construção")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: Escrever os testes que falham em `Tests/CCUsageCoreTests/ModelIDTests.swift`**

```swift
import Testing
@testable import CCUsageCore

@Test func resolvesCanonicalIDs() {
    #expect(ModelID(raw: "claude-opus-5") == .opus5)
    #expect(ModelID(raw: "claude-opus-4-8") == .opus4x)
    #expect(ModelID(raw: "claude-sonnet-5") == .sonnet5)
    #expect(ModelID(raw: "claude-sonnet-4-5-20250929") == .sonnet4x)
    #expect(ModelID(raw: "claude-haiku-4-5-20251001") == .haiku45)
    #expect(ModelID(raw: "claude-fable-5") == .fable5)
}

@Test func resolvesBareAliases() {
    #expect(ModelID(raw: "opus") == .opus5)
    #expect(ModelID(raw: "sonnet") == .sonnet5)
    #expect(ModelID(raw: "haiku") == .haiku45)
}

@Test func unknownModelKeepsItsRawName() {
    #expect(ModelID(raw: "claude-opus-9") == .unknown("claude-opus-9"))
    #expect(ModelID(raw: "<synthetic>") == .unknown("<synthetic>"))
}
```

- [ ] **Step 4: Escrever os testes que falham em `Tests/CCUsageCoreTests/MoneyTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

@Test func addingKnownCostsSums() {
    var m = Money.zero
    m.add(cost: Decimal(string: "1.50"))
    m.add(cost: Decimal(string: "2.25"))
    #expect(m.usd == Decimal(string: "3.75"))
    #expect(m.isPartial == false)
}

@Test func addingNilCostFlagsPartialButKeepsTheSum() {
    var m = Money.zero
    m.add(cost: Decimal(string: "10.00"))
    m.add(cost: nil)
    #expect(m.usd == Decimal(string: "10.00"))
    #expect(m.isPartial == true)
}

@Test func partialityPropagatesThroughAddition() {
    let a = Money(usd: 1, isPartial: false)
    let b = Money(usd: 2, isPartial: true)
    #expect((a + b).usd == 3)
    #expect((a + b).isPartial == true)
}
```

- [ ] **Step 5: Rodar os testes e confirmar que falham por compilação**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ModelID' in scope`, `cannot find 'Money' in scope`.

- [ ] **Step 6: Implementar `Sources/CCUsageCore/Models/ModelID.swift`**

```swift
/// Um modelo do Claude, agrupado por faixa de preço.
///
/// Os casos `4x` colapsam gerações que compartilham exatamente a mesma tabela
/// de preços — separá-las não mudaria nenhum número.
public enum ModelID: Hashable, Sendable {
    case opus5
    case opus4x      // Opus 4.5 / 4.6 / 4.7 / 4.8 — todos $5/$25
    case sonnet5
    case sonnet4x    // Sonnet 4.5 / 4.6 — ambos $3/$15
    case haiku45
    case fable5      // inclui Mythos 5 / Mythos Preview
    case unknown(String)

    /// Resolve o valor cru de `message.model` no JSONL.
    ///
    /// Aliases nus (`"opus"`, `"sonnet"`, `"haiku"`) aparecem quando um subagente
    /// é configurado por tier em vez de por ID. Resolvem para a geração corrente
    /// da família, que é o que o Claude Code entende por eles.
    public init(raw: String) {
        if raw == "claude-fable-5" || raw == "claude-mythos-5" || raw == "claude-mythos-preview" {
            self = .fable5
        } else if raw == "claude-opus-5" || raw == "opus" {
            self = .opus5
        } else if raw.hasPrefix("claude-opus-4") {
            self = .opus4x
        } else if raw == "claude-sonnet-5" || raw == "sonnet" {
            self = .sonnet5
        } else if raw.hasPrefix("claude-sonnet-4") {
            self = .sonnet4x
        } else if raw.hasPrefix("claude-haiku-4-5") || raw == "haiku" {
            self = .haiku45
        } else {
            self = .unknown(raw)
        }
    }

    /// Nome cru quando o modelo não foi reconhecido — para a UI poder dizer qual é.
    public var unknownName: String? {
        if case .unknown(let name) = self { return name }
        return nil
    }
}
```

- [ ] **Step 7: Implementar `Sources/CCUsageCore/Models/Money.swift`**

```swift
import Foundation

/// Valor em USD que sabe quando está incompleto.
///
/// `isPartial` existe para que um modelo sem preço conhecido nunca seja contado
/// como zero: a soma dos eventos precificáveis é preservada e o total é marcado
/// como piso, não como valor exato.
public struct Money: Sendable, Equatable {
    public var usd: Decimal
    public var isPartial: Bool

    public static let zero = Money(usd: 0, isPartial: false)

    public init(usd: Decimal, isPartial: Bool) {
        self.usd = usd
        self.isPartial = isPartial
    }

    /// Soma um custo; `nil` significa "esse evento não tem preço conhecido".
    public mutating func add(cost: Decimal?) {
        if let cost { usd += cost } else { isPartial = true }
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(usd: lhs.usd + rhs.usd, isPartial: lhs.isPartial || rhs.isPartial)
    }
}
```

- [ ] **Step 8: Implementar `Sources/CCUsageCore/Models/UsageEvent.swift`**

```swift
import Foundation

/// Uma mensagem assistant com uso de token, extraída de uma linha do JSONL.
public struct UsageEvent: Sendable, Equatable {
    public let timestamp: Date
    public let model: ModelID
    /// `message.usage.speed == "fast"` — fast mode custa o dobro no Opus 5.
    public let isFast: Bool
    public let input: UInt32
    public let output: UInt32
    public let cacheWrite5m: UInt32
    public let cacheWrite1h: UInt32
    public let cacheRead: UInt32
    /// `"\(message.id):\(requestId)"` — resume e fork reescrevem a mesma
    /// mensagem em arquivos diferentes; sem isso os tokens contam em dobro.
    public let dedupeKey: String

    public init(
        timestamp: Date, model: ModelID, isFast: Bool,
        input: UInt32, output: UInt32,
        cacheWrite5m: UInt32, cacheWrite1h: UInt32, cacheRead: UInt32,
        dedupeKey: String
    ) {
        self.timestamp = timestamp
        self.model = model
        self.isFast = isFast
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.dedupeKey = dedupeKey
    }

    public var totalTokens: UInt64 {
        UInt64(input) + UInt64(output)
            + UInt64(cacheWrite5m) + UInt64(cacheWrite1h) + UInt64(cacheRead)
    }
}
```

- [ ] **Step 9: Rodar os testes e confirmar que passam**

Run: `swift test 2>&1 | tail -20`
Expected: PASS — 6 testes.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "feat: fundação do core — ModelID, Money, UsageEvent"
```

---

### Task 2: PricingTable

**Files:**
- Create: `Sources/CCUsageCore/Pricing/PricingTable.swift`
- Test: `Tests/CCUsageCoreTests/PricingTableTests.swift`

**Interfaces:**
- Consumes: `ModelID`, `UsageEvent` (Task 1).
- Produces: `Rates` (struct com `input`, `output` e as derivadas `cacheWrite5m`, `cacheWrite1h`, `cacheRead`, todas `Decimal` por MTok), `PricingTable.rates(for:at:isFast:) -> Rates?`, `PricingTable.cost(of: UsageEvent) -> Decimal?`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/PricingTableTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func date(_ s: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(s)
}

private func event(
    model: ModelID, at: Date, isFast: Bool = false,
    input: UInt32 = 0, output: UInt32 = 0,
    w5m: UInt32 = 0, w1h: UInt32 = 0, read: UInt32 = 0
) -> UsageEvent {
    UsageEvent(timestamp: at, model: model, isFast: isFast,
               input: input, output: output,
               cacheWrite5m: w5m, cacheWrite1h: w1h, cacheRead: read,
               dedupeKey: "k")
}

@Test func cacheDimensionsDeriveFromInput() {
    let r = PricingTable.rates(for: .opus5, at: date("2026-08-17T12:00:00Z"), isFast: false)!
    #expect(r.input == 5)
    #expect(r.output == 25)
    #expect(r.cacheWrite5m == Decimal(string: "6.25"))
    #expect(r.cacheWrite1h == 10)
    #expect(r.cacheRead == Decimal(string: "0.5"))
}

@Test func sonnet5UsesIntroPricingBeforeSeptember() {
    let r = PricingTable.rates(for: .sonnet5, at: date("2026-08-20T00:00:00Z"), isFast: false)!
    #expect(r.input == 2)
    #expect(r.output == 10)
}

@Test func sonnet5RevertsToStandardPricingInSeptember() {
    let r = PricingTable.rates(for: .sonnet5, at: date("2026-09-05T00:00:00Z"), isFast: false)!
    #expect(r.input == 3)
    #expect(r.output == 15)
}

@Test func fastModeDoublesOpus5() {
    let d = date("2026-08-17T12:00:00Z")
    let standard = PricingTable.rates(for: .opus5, at: d, isFast: false)!
    let fast = PricingTable.rates(for: .opus5, at: d, isFast: true)!
    #expect(fast.input == standard.input * 2)
    #expect(fast.output == standard.output * 2)
}

@Test func unknownModelHasNoPrice() {
    #expect(PricingTable.rates(for: .unknown("claude-opus-9"),
                               at: date("2026-08-17T12:00:00Z"), isFast: false) == nil)
    #expect(PricingTable.cost(of: event(model: .unknown("x"),
                                        at: date("2026-08-17T12:00:00Z"), input: 1000)) == nil)
}

@Test func costSumsAllFiveDimensions() {
    // Opus 5 standard: 1M input=$5, 1M output=$25, 1M w5m=$6.25, 1M w1h=$10, 1M read=$0.50
    let e = event(model: .opus5, at: date("2026-08-17T12:00:00Z"),
                  input: 1_000_000, output: 1_000_000,
                  w5m: 1_000_000, w1h: 1_000_000, read: 1_000_000)
    #expect(PricingTable.cost(of: e) == Decimal(string: "46.75"))
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter PricingTable 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PricingTable' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Pricing/PricingTable.swift`**

```swift
import Foundation

/// Preços em USD por milhão de tokens.
public struct Rates: Sendable, Equatable {
    public let input: Decimal
    public let output: Decimal

    public init(input: Decimal, output: Decimal) {
        self.input = input
        self.output = output
    }

    // Multiplicadores fixos sobre o preço de input, iguais para todo modelo.
    // Construídos por significando/expoente porque literais de ponto flutuante
    // passam por Double e introduziriam imprecisão no Decimal.
    private static let write5mMultiplier = Decimal(sign: .plus, exponent: -2, significand: 125) // 1.25
    private static let write1hMultiplier = Decimal(2)
    private static let readMultiplier = Decimal(sign: .plus, exponent: -1, significand: 1)      // 0.1

    public var cacheWrite5m: Decimal { input * Self.write5mMultiplier }
    public var cacheWrite1h: Decimal { input * Self.write1hMultiplier }
    public var cacheRead: Decimal { input * Self.readMultiplier }
}

public enum PricingTable {
    /// Sonnet 5 tem preço introdutório de $2/$10 até 2026-08-31 inclusive;
    /// a partir deste instante volta a $3/$15.
    static let sonnet5IntroEnd: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }()

    /// `nil` quando o modelo não é reconhecido — o chamador deve marcar o total
    /// como parcial, nunca tratar como zero.
    public static func rates(for model: ModelID, at date: Date, isFast: Bool) -> Rates? {
        switch model {
        case .opus5:
            return isFast ? Rates(input: 10, output: 50) : Rates(input: 5, output: 25)
        case .opus4x:
            return Rates(input: 5, output: 25)
        case .sonnet5:
            return date < sonnet5IntroEnd
                ? Rates(input: 2, output: 10)
                : Rates(input: 3, output: 15)
        case .sonnet4x:
            return Rates(input: 3, output: 15)
        case .haiku45:
            return Rates(input: 1, output: 5)
        case .fable5:
            return Rates(input: 10, output: 50)
        case .unknown:
            return nil
        }
    }

    private static let perMillion = Decimal(1_000_000)

    public static func cost(of event: UsageEvent) -> Decimal? {
        guard let r = rates(for: event.model, at: event.timestamp, isFast: event.isFast) else {
            return nil
        }
        let total = Decimal(event.input) * r.input
            + Decimal(event.output) * r.output
            + Decimal(event.cacheWrite5m) * r.cacheWrite5m
            + Decimal(event.cacheWrite1h) * r.cacheWrite1h
            + Decimal(event.cacheRead) * r.cacheRead
        return total / perMillion
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `swift test --filter PricingTable 2>&1 | tail -20`
Expected: PASS — 6 testes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCUsageCore/Pricing Tests/CCUsageCoreTests/PricingTableTests.swift
git commit -m "feat: tabela de preços indexada por modelo e data"
```

---

### Task 3: JSONLParser

**Files:**
- Create: `Sources/CCUsageCore/Parsing/JSONLParser.swift`
- Test: `Tests/CCUsageCoreTests/JSONLParserTests.swift`

**Interfaces:**
- Consumes: `ModelID`, `UsageEvent` (Task 1).
- Produces: `JSONLParser.mayContainUsage(_ line: Data) -> Bool`, `JSONLParser.event(from line: Data) -> UsageEvent?`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/JSONLParserTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func line(_ json: String) -> Data { Data(json.utf8) }

private let assistantLine = """
{"type":"assistant","timestamp":"2026-07-13T10:08:12.767Z","requestId":"req_1",\
"message":{"id":"msg_1","model":"claude-opus-5","usage":{"input_tokens":2,\
"output_tokens":792,"cache_creation_input_tokens":26186,"cache_read_input_tokens":19059,\
"speed":"standard","cache_creation":{"ephemeral_1h_input_tokens":26186,\
"ephemeral_5m_input_tokens":0}}}}
"""

@Test func prefilterRejectsLinesWithoutUsage() {
    #expect(JSONLParser.mayContainUsage(line(#"{"type":"user","message":{}}"#)) == false)
    #expect(JSONLParser.mayContainUsage(line(assistantLine)) == true)
}

@Test func parsesAllFiveTokenDimensions() {
    let e = JSONLParser.event(from: line(assistantLine))!
    #expect(e.model == .opus5)
    #expect(e.input == 2)
    #expect(e.output == 792)
    #expect(e.cacheWrite1h == 26186)
    #expect(e.cacheWrite5m == 0)
    #expect(e.cacheRead == 19059)
    #expect(e.isFast == false)
    #expect(e.dedupeKey == "msg_1:req_1")
}

@Test func detectsFastMode() {
    let fast = assistantLine.replacingOccurrences(of: #""speed":"standard""#,
                                                  with: #""speed":"fast""#)
    #expect(JSONLParser.event(from: line(fast))!.isFast == true)
}

@Test func fallsBackToFiveMinuteTTLWhenSplitIsAbsent() {
    let noSplit = """
    {"type":"assistant","timestamp":"2026-07-13T10:08:12.767Z","requestId":"req_2",\
    "message":{"id":"msg_2","model":"claude-opus-5","usage":{"input_tokens":1,\
    "output_tokens":1,"cache_creation_input_tokens":500}}}
    """
    let e = JSONLParser.event(from: line(noSplit))!
    #expect(e.cacheWrite5m == 500)
    #expect(e.cacheWrite1h == 0)
}

@Test func skipsSyntheticModel() {
    let synthetic = assistantLine.replacingOccurrences(of: #""claude-opus-5""#,
                                                       with: #""<synthetic>""#)
    #expect(JSONLParser.event(from: line(synthetic)) == nil)
}

@Test func skipsNonAssistantAndMalformedLines() {
    let user = #"{"type":"user","timestamp":"2026-07-13T10:08:12.767Z","message":{"usage":{}}}"#
    #expect(JSONLParser.event(from: line(user)) == nil)
    #expect(JSONLParser.event(from: line(#"{"type":"assistant","usage" broken"#)) == nil)
    #expect(JSONLParser.event(from: line("")) == nil)
}

@Test func parsesTimestampWithoutFractionalSeconds() {
    let plain = assistantLine.replacingOccurrences(of: "10:08:12.767Z", with: "10:08:12Z")
    #expect(JSONLParser.event(from: line(plain)) != nil)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter JSONLParser 2>&1 | tail -20`
Expected: FAIL — `cannot find 'JSONLParser' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Parsing/JSONLParser.swift`**

```swift
import Foundation

public enum JSONLParser {
    // MARK: - Pré-filtro

    private static let usageMarker = Data(#""usage""#.utf8)

    /// Portão barato em bytes: só linhas contendo `"usage"` podem gerar evento.
    /// A esmagadora maioria das linhas é user/tool/system e nunca chega ao
    /// `JSONDecoder` — é o que torna a varredura de 252 MB viável.
    public static func mayContainUsage(_ line: Data) -> Bool {
        line.range(of: usageMarker) != nil
    }

    // MARK: - Decode

    // JSONDecoder não é Sendable, mas decodificar com uma instância que nunca é
    // mutada é seguro para uso concorrente.
    nonisolated(unsafe) private static let decoder = JSONDecoder()

    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func parseTimestamp(_ raw: String) -> Date? {
        if let d = try? isoWithFraction.parse(raw) { return d }
        return try? isoPlain.parse(raw)
    }

    private struct RawLine: Decodable {
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: RawMessage?
    }

    private struct RawMessage: Decodable {
        let id: String?
        let model: String?
        let usage: RawUsage?
    }

    private struct RawUsage: Decodable {
        let inputTokens: UInt32?
        let outputTokens: UInt32?
        let cacheCreationInputTokens: UInt32?
        let cacheReadInputTokens: UInt32?
        let speed: String?
        let cacheCreation: RawCacheCreation?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case speed
            case cacheCreation = "cache_creation"
        }
    }

    private struct RawCacheCreation: Decodable {
        let ephemeral1h: UInt32?
        let ephemeral5m: UInt32?

        enum CodingKeys: String, CodingKey {
            case ephemeral1h = "ephemeral_1h_input_tokens"
            case ephemeral5m = "ephemeral_5m_input_tokens"
        }
    }

    /// `nil` para qualquer linha que não seja uma mensagem assistant com uso real.
    /// Linha malformada é descartada silenciosamente — um log corrompido não
    /// pode derrubar a varredura inteira.
    public static func event(from line: Data) -> UsageEvent? {
        guard mayContainUsage(line),
              let raw = try? decoder.decode(RawLine.self, from: line),
              raw.type == "assistant",
              let message = raw.message,
              let usage = message.usage,
              let modelRaw = message.model,
              modelRaw != "<synthetic>",
              let messageID = message.id,
              let requestID = raw.requestId,
              let timestampRaw = raw.timestamp,
              let timestamp = parseTimestamp(timestampRaw)
        else { return nil }

        // Versões antigas do Claude Code não gravam o split por TTL; nesse caso
        // o total cai no bucket de 5m, que é o TTL padrão.
        let write5m: UInt32
        let write1h: UInt32
        if let split = usage.cacheCreation {
            write5m = split.ephemeral5m ?? 0
            write1h = split.ephemeral1h ?? 0
        } else {
            write5m = usage.cacheCreationInputTokens ?? 0
            write1h = 0
        }

        return UsageEvent(
            timestamp: timestamp,
            model: ModelID(raw: modelRaw),
            isFast: usage.speed == "fast",
            input: usage.inputTokens ?? 0,
            output: usage.outputTokens ?? 0,
            cacheWrite5m: write5m,
            cacheWrite1h: write1h,
            cacheRead: usage.cacheReadInputTokens ?? 0,
            dedupeKey: "\(messageID):\(requestID)"
        )
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `swift test --filter JSONLParser 2>&1 | tail -20`
Expected: PASS — 7 testes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCUsageCore/Parsing Tests/CCUsageCoreTests/JSONLParserTests.swift
git commit -m "feat: parser de JSONL com pré-filtro em bytes"
```

---

### Task 4: ProjectScanner + ParseCache (leitura incremental)

**Files:**
- Create: `Sources/CCUsageCore/Parsing/ParseCache.swift`
- Create: `Sources/CCUsageCore/Parsing/ProjectScanner.swift`
- Test: `Tests/CCUsageCoreTests/ProjectScannerTests.swift`

**Interfaces:**
- Consumes: `JSONLParser`, `UsageEvent` (Tasks 1, 3).
- Produces: `FileState` (`size`, `mtime`, `byteOffset`), `ParseCache` (`files: [String: FileState]`, `load(from:)`, `save(to:)`), `ProjectScanner(root:)` com `files(modifiedSince:) throws -> [URL]` e `ingest(since:cache:) throws -> (events: [UsageEvent], cache: ParseCache)`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/ProjectScannerTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func makeLine(id: String, request: String, output: UInt32) -> String {
    """
    {"type":"assistant","timestamp":"2026-08-17T10:00:00.000Z","requestId":"\(request)",\
    "message":{"id":"\(id)","model":"claude-opus-5","usage":{"input_tokens":1,\
    "output_tokens":\(output),"cache_read_input_tokens":0}}}
    """
}

private func makeTempRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "cctc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appending(path: "projA"),
                                            withIntermediateDirectories: true)
    return root
}

@Test func ingestsEventsFromNestedJSONLFiles() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "projA/session.jsonl")
    try (makeLine(id: "m1", request: "r1", output: 10) + "\n").write(to: file, atomically: true, encoding: .utf8)

    let scanner = ProjectScanner(root: root)
    let result = try scanner.ingest(since: .distantPast, cache: ParseCache())
    #expect(result.events.count == 1)
    #expect(result.events[0].output == 10)
}

@Test func dedupesIdenticalMessageAcrossFiles() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let same = makeLine(id: "m1", request: "r1", output: 10) + "\n"
    try same.write(to: root.appending(path: "projA/a.jsonl"), atomically: true, encoding: .utf8)
    try same.write(to: root.appending(path: "projA/b.jsonl"), atomically: true, encoding: .utf8)

    let result = try ProjectScanner(root: root).ingest(since: .distantPast, cache: ParseCache())
    #expect(result.events.count == 1)
}

@Test func secondIngestReadsOnlyTheAppendedDelta() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "projA/session.jsonl")
    try (makeLine(id: "m1", request: "r1", output: 10) + "\n")
        .write(to: file, atomically: true, encoding: .utf8)

    let scanner = ProjectScanner(root: root)
    let first = try scanner.ingest(since: .distantPast, cache: ParseCache())
    #expect(first.events.count == 1)

    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((makeLine(id: "m2", request: "r2", output: 20) + "\n").utf8))
    try handle.close()

    let second = try scanner.ingest(since: .distantPast, cache: first.cache)
    #expect(second.events.count == 1)
    #expect(second.events[0].output == 20)
}

@Test func truncatedFileTriggersFullReparse() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "projA/session.jsonl")
    let twoLines = makeLine(id: "m1", request: "r1", output: 10) + "\n"
        + makeLine(id: "m2", request: "r2", output: 20) + "\n"
    try twoLines.write(to: file, atomically: true, encoding: .utf8)

    let scanner = ProjectScanner(root: root)
    let first = try scanner.ingest(since: .distantPast, cache: ParseCache())
    #expect(first.events.count == 2)

    try (makeLine(id: "m3", request: "r3", output: 30) + "\n")
        .write(to: file, atomically: true, encoding: .utf8)

    let second = try scanner.ingest(since: .distantPast, cache: first.cache)
    #expect(second.events.count == 1)
    #expect(second.events[0].output == 30)
}

@Test func missingRootYieldsNoEvents() throws {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "cctc-absent-\(UUID().uuidString)")
    let result = try ProjectScanner(root: missing).ingest(since: .distantPast, cache: ParseCache())
    #expect(result.events.isEmpty)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter ProjectScanner 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ProjectScanner' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Parsing/ParseCache.swift`**

```swift
import Foundation

public struct FileState: Codable, Sendable, Equatable {
    public var size: UInt64
    public var mtime: Date
    /// Offset em bytes até onde o arquivo já foi parseado.
    public var byteOffset: UInt64

    public init(size: UInt64, mtime: Date, byteOffset: UInt64) {
        self.size = size
        self.mtime = mtime
        self.byteOffset = byteOffset
    }
}

/// Estado de leitura por arquivo, para que só o delta seja reparseado.
public struct ParseCache: Codable, Sendable, Equatable {
    public var files: [String: FileState]

    public init(files: [String: FileState] = [:]) {
        self.files = files
    }

    public static func load(from url: URL) -> ParseCache {
        // Cache corrompido ou ausente não é erro: descarta e reparseia tudo.
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ParseCache.self, from: data)
        else { return ParseCache() }
        return cache
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// `~/Library/Application Support/ClaudeTokenCounter/cache.json`
    public static var defaultURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ClaudeTokenCounter/cache.json")
    }
}
```

- [ ] **Step 4: Implementar `Sources/CCUsageCore/Parsing/ProjectScanner.swift`**

```swift
import Foundation

public struct ProjectScanner: Sendable {
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
                                .appending(path: ".claude/projects")) {
        self.root = root
    }

    /// Arquivos `.jsonl` cujo `mtime` é igual ou posterior a `since`.
    ///
    /// Descartar por mtime é **correto**, não só otimização: o log é append-only,
    /// então nenhum arquivo pode conter um evento mais novo que seu próprio mtime.
    public func files(modifiedSince since: Date) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let mtime = values?.contentModificationDate, mtime >= since else { continue }
            result.append(url)
        }
        return result
    }

    /// Lê apenas o que ainda não foi lido e devolve os eventos novos, já
    /// deduplicados, junto com o cache atualizado.
    public func ingest(
        since: Date,
        cache: ParseCache
    ) throws -> (events: [UsageEvent], cache: ParseCache) {
        var cache = cache
        var events: [UsageEvent] = []
        var seen = Set<String>()

        for url in try files(modifiedSince: since) {
            let key = url.path
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values?.fileSize.map(UInt64.init),
                  let mtime = values?.contentModificationDate
            else { continue }

            var offset = cache.files[key]?.byteOffset ?? 0
            // Arquivo encolheu → foi truncado ou reescrito; reparseia do zero.
            if size < offset { offset = 0 }
            guard size > offset else {
                cache.files[key] = FileState(size: size, mtime: mtime, byteOffset: offset)
                continue
            }

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd() else { continue }

            var consumed = offset
            for lineRange in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
                                 .dropLast() {
                consumed += UInt64(lineRange.count) + 1  // +1 pelo \n consumido
                guard let event = JSONLParser.event(from: Data(lineRange)) else { continue }
                guard seen.insert(event.dedupeKey).inserted else { continue }
                events.append(event)
            }

            // `consumed` para na última quebra de linha: uma linha parcial no
            // fim do arquivo (o Claude Code ainda escrevendo) é relida inteira
            // na próxima passada em vez de ser parseada pela metade.
            cache.files[key] = FileState(size: size, mtime: mtime, byteOffset: consumed)
        }

        return (events, cache)
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `swift test --filter ProjectScanner 2>&1 | tail -20`
Expected: PASS — 5 testes.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore/Parsing Tests/CCUsageCoreTests/ProjectScannerTests.swift
git commit -m "feat: varredura incremental com dedup e reparse em truncate"
```

---

### Task 5: BlockBuilder (janela de 5 horas)

**Files:**
- Create: `Sources/CCUsageCore/Aggregation/BlockBuilder.swift`
- Test: `Tests/CCUsageCoreTests/BlockBuilderTests.swift`

**Interfaces:**
- Consumes: `UsageEvent`, `Money`, `PricingTable` (Tasks 1, 2).
- Produces: `UsageBlock` (`start`, `end`, `lastEvent`, `tokens: UInt64`, `money: Money`, `isActive(at:)`, `isComplete(at:)`), `BlockBuilder.duration`, `BlockBuilder.blocks(from:calendar:) -> [UsageBlock]`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/BlockBuilderTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func date(_ s: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(s)
}

private func event(_ iso: String, output: UInt32 = 100) -> UsageEvent {
    UsageEvent(timestamp: date(iso), model: .opus5, isFast: false,
               input: 0, output: output, cacheWrite5m: 0, cacheWrite1h: 0,
               cacheRead: 0, dedupeKey: iso)
}

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

@Test func blockStartsFlooredToTheHour() {
    let blocks = BlockBuilder.blocks(from: [event("2026-08-17T10:37:00Z")], calendar: utc)
    #expect(blocks.count == 1)
    #expect(blocks[0].start == date("2026-08-17T10:00:00Z"))
    #expect(blocks[0].end == date("2026-08-17T15:00:00Z"))
}

@Test func eventsWithinFiveHoursShareABlock() {
    let blocks = BlockBuilder.blocks(
        from: [event("2026-08-17T10:10:00Z"), event("2026-08-17T14:00:00Z")], calendar: utc)
    #expect(blocks.count == 1)
    #expect(blocks[0].tokens == 200)
}

@Test func crossingTheWindowOpensANewBlock() {
    // 10:00 + 5h = 15:00; um evento às 15:30 cai fora do primeiro bloco.
    let blocks = BlockBuilder.blocks(
        from: [event("2026-08-17T10:10:00Z"), event("2026-08-17T15:30:00Z")], calendar: utc)
    #expect(blocks.count == 2)
    #expect(blocks[1].start == date("2026-08-17T15:00:00Z"))
}

@Test func gapLongerThanFiveHoursOpensANewBlock() {
    let blocks = BlockBuilder.blocks(
        from: [event("2026-08-17T10:00:00Z"), event("2026-08-18T09:00:00Z")], calendar: utc)
    #expect(blocks.count == 2)
}

@Test func eventsAreSortedBeforeBlocking() {
    let blocks = BlockBuilder.blocks(
        from: [event("2026-08-17T14:00:00Z"), event("2026-08-17T10:10:00Z")], calendar: utc)
    #expect(blocks.count == 1)
    #expect(blocks[0].start == date("2026-08-17T10:00:00Z"))
}

@Test func activeAndCompleteAreDistinct() {
    let blocks = BlockBuilder.blocks(from: [event("2026-08-17T10:10:00Z")], calendar: utc)
    let b = blocks[0]
    #expect(b.isActive(at: date("2026-08-17T12:00:00Z")) == true)
    #expect(b.isComplete(at: date("2026-08-17T12:00:00Z")) == false)
    #expect(b.isActive(at: date("2026-08-17T16:00:00Z")) == false)
    #expect(b.isComplete(at: date("2026-08-17T16:00:00Z")) == true)
}

@Test func unknownModelMakesTheBlockMoneyPartial() {
    let unknown = UsageEvent(timestamp: date("2026-08-17T10:10:00Z"),
                             model: .unknown("claude-opus-9"), isFast: false,
                             input: 1000, output: 0, cacheWrite5m: 0, cacheWrite1h: 0,
                             cacheRead: 0, dedupeKey: "u")
    let blocks = BlockBuilder.blocks(from: [event("2026-08-17T10:10:00Z"), unknown], calendar: utc)
    #expect(blocks[0].money.isPartial == true)
    #expect(blocks[0].money.usd > 0)   // a parte precificável foi preservada
    #expect(blocks[0].tokens == 1100)  // tokens contam mesmo sem preço
}

@Test func noEventsYieldsNoBlocks() {
    #expect(BlockBuilder.blocks(from: [], calendar: utc).isEmpty)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter BlockBuilder 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BlockBuilder' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Aggregation/BlockBuilder.swift`**

```swift
import Foundation

/// Uma janela de 5 horas derivada da atividade.
///
/// A Anthropic não persiste os horários oficiais de reset em lugar nenhum local,
/// então isto é **estimativa** — a UI precisa apresentá-la como tal.
public struct UsageBlock: Sendable, Equatable {
    public let start: Date       // arredondado para baixo à hora cheia
    public let end: Date         // start + 5h
    public let lastEvent: Date
    public let tokens: UInt64
    public let money: Money

    public func isActive(at now: Date) -> Bool { now >= start && now < end }
    public func isComplete(at now: Date) -> Bool { now >= end }
}

public enum BlockBuilder {
    public static let duration: TimeInterval = 5 * 60 * 60

    /// Abre um bloco novo quando não há bloco corrente, quando o evento passa de
    /// `início + 5h`, ou quando há um gap de mais de 5h desde o último evento.
    public static func blocks(from events: [UsageEvent], calendar: Calendar = .current) -> [UsageBlock] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var blocks: [UsageBlock] = []

        var start: Date?
        var last: Date?
        var tokens: UInt64 = 0
        var money = Money.zero

        func closeCurrent() {
            guard let start, let last else { return }
            blocks.append(UsageBlock(start: start,
                                     end: start.addingTimeInterval(duration),
                                     lastEvent: last,
                                     tokens: tokens,
                                     money: money))
        }

        for event in sorted {
            let needsNewBlock: Bool
            if let start, let last {
                needsNewBlock = event.timestamp >= start.addingTimeInterval(duration)
                    || event.timestamp >= last.addingTimeInterval(duration)
            } else {
                needsNewBlock = true
            }

            if needsNewBlock {
                closeCurrent()
                start = calendar.dateInterval(of: .hour, for: event.timestamp)?.start
                    ?? event.timestamp
                tokens = 0
                money = .zero
            }

            tokens += event.totalTokens
            money.add(cost: PricingTable.cost(of: event))
            last = event.timestamp
        }

        closeCurrent()
        return blocks
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `swift test --filter BlockBuilder 2>&1 | tail -20`
Expected: PASS — 8 testes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCUsageCore/Aggregation Tests/CCUsageCoreTests/BlockBuilderTests.swift
git commit -m "feat: derivação dos blocos de 5h a partir da atividade"
```

---

### Task 6: PeriodAggregator

**Files:**
- Create: `Sources/CCUsageCore/Aggregation/PeriodAggregator.swift`
- Test: `Tests/CCUsageCoreTests/PeriodAggregatorTests.swift`

**Interfaces:**
- Consumes: `UsageEvent`, `Money`, `PricingTable` (Tasks 1, 2).
- Produces: `Totals` (`tokens: UInt64`, `money: Money`, `.zero`), `PeriodAggregator(calendar:)` com `todayInterval(now:)`, `weekInterval(now:)`, `monthInterval(now:)`, `rolling7Days(now:)` e `totals(from:in:) -> Totals`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/PeriodAggregatorTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func date(_ s: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(s)
}

private func event(_ iso: String, output: UInt32 = 100) -> UsageEvent {
    UsageEvent(timestamp: date(iso), model: .opus5, isFast: false,
               input: 0, output: output, cacheWrite5m: 0, cacheWrite1h: 0,
               cacheRead: 0, dedupeKey: iso)
}

private var utcAggregator: PeriodAggregator {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return PeriodAggregator(calendar: c)
}

@Test func todayIsTheLocalCalendarDay() {
    let agg = utcAggregator
    let interval = agg.todayInterval(now: date("2026-08-17T23:30:00Z"))
    #expect(interval.start == date("2026-08-17T00:00:00Z"))
    #expect(interval.end == date("2026-08-18T00:00:00Z"))
}

@Test func calendarWeekStartsOnMonday() {
    // 2026-08-17 é uma segunda-feira.
    let interval = utcAggregator.weekInterval(now: date("2026-08-20T12:00:00Z"))
    #expect(interval.start == date("2026-08-17T00:00:00Z"))
    #expect(interval.end == date("2026-08-24T00:00:00Z"))
}

@Test func monthCoversTheWholeCalendarMonth() {
    let interval = utcAggregator.monthInterval(now: date("2026-08-17T12:00:00Z"))
    #expect(interval.start == date("2026-08-01T00:00:00Z"))
    #expect(interval.end == date("2026-09-01T00:00:00Z"))
}

@Test func rollingSevenDaysDiffersFromCalendarWeek() {
    let agg = utcAggregator
    let now = date("2026-08-20T12:00:00Z")
    let rolling = agg.rolling7Days(now: now)
    #expect(rolling.start == date("2026-08-13T12:00:00Z"))
    #expect(rolling.end == now)
    #expect(rolling.start != agg.weekInterval(now: now).start)
}

@Test func totalsCountOnlyEventsInsideTheInterval() {
    let agg = utcAggregator
    let events = [
        event("2026-08-16T23:59:00Z", output: 1),   // ontem
        event("2026-08-17T00:00:00Z", output: 10),  // borda inicial: dentro
        event("2026-08-17T12:00:00Z", output: 20),
        event("2026-08-18T00:00:00Z", output: 40),  // borda final: fora
    ]
    let totals = agg.totals(from: events, in: agg.todayInterval(now: date("2026-08-17T12:00:00Z")))
    #expect(totals.tokens == 30)
}

@Test func totalsGoPartialOnUnknownModel() {
    let agg = utcAggregator
    let unknown = UsageEvent(timestamp: date("2026-08-17T12:00:00Z"),
                             model: .unknown("x"), isFast: false,
                             input: 100, output: 0, cacheWrite5m: 0, cacheWrite1h: 0,
                             cacheRead: 0, dedupeKey: "u")
    let totals = agg.totals(from: [event("2026-08-17T11:00:00Z"), unknown],
                            in: agg.todayInterval(now: date("2026-08-17T12:00:00Z")))
    #expect(totals.money.isPartial == true)
    #expect(totals.tokens == 200)
}

@Test func monthBoundaryDoesNotLeakIntoNextMonth() {
    let agg = utcAggregator
    let events = [event("2026-08-31T23:00:00Z", output: 5), event("2026-09-01T01:00:00Z", output: 7)]
    let august = agg.totals(from: events, in: agg.monthInterval(now: date("2026-08-15T00:00:00Z")))
    #expect(august.tokens == 5)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter PeriodAggregator 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PeriodAggregator' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Aggregation/PeriodAggregator.swift`**

```swift
import Foundation

public struct Totals: Sendable, Equatable {
    public var tokens: UInt64
    public var money: Money

    public static let zero = Totals(tokens: 0, money: .zero)
}

/// Recorta eventos em períodos de calendário e na janela rolling de 7 dias.
///
/// "Semana" tem duas definições deliberadamente distintas: a de calendário
/// (segunda a domingo) alimenta a seção de **valor**, e a rolling de 7 dias
/// alimenta o gauge de **risco**. Cada uma responde a uma pergunta diferente,
/// e a UI rotula ambas explicitamente.
public struct PeriodAggregator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        var cal = calendar
        cal.firstWeekday = 2  // segunda-feira
        self.calendar = cal
    }

    public func todayInterval(now: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: now)!
    }

    public func weekInterval(now: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: now)!
    }

    public func monthInterval(now: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: now)!
    }

    public func rolling7Days(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-7 * 24 * 60 * 60), end: now)
    }

    /// Intervalo semiaberto `[start, end)` — a borda final pertence ao próximo período.
    public func totals(from events: [UsageEvent], in interval: DateInterval) -> Totals {
        var totals = Totals.zero
        for event in events where event.timestamp >= interval.start && event.timestamp < interval.end {
            totals.tokens += event.totalTokens
            totals.money.add(cost: PricingTable.cost(of: event))
        }
        return totals
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `swift test --filter PeriodAggregator 2>&1 | tail -20`
Expected: PASS — 7 testes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCUsageCore/Aggregation Tests/CCUsageCoreTests/PeriodAggregatorTests.swift
git commit -m "feat: agregação por período de calendário e janela rolling"
```

---

### Task 7: CeilingCalibrator

**Files:**
- Create: `Sources/CCUsageCore/Aggregation/CeilingCalibrator.swift`
- Test: `Tests/CCUsageCoreTests/CeilingCalibratorTests.swift`

**Interfaces:**
- Consumes: `UsageEvent`, `UsageBlock` (Tasks 1, 5).
- Produces: `Ceilings` (`blockTokens: UInt64`, `weeklyTokens: UInt64`), `CeilingCalibrator.blockCeiling(blocks:now:lookback:)`, `CeilingCalibrator.weeklyCeiling(events:now:lookback:)`, `CeilingCalibrator.calibrate(blocks:events:now:override:) -> Ceilings`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/CeilingCalibratorTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func date(_ s: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(s)
}

private func block(_ startISO: String, tokens: UInt64) -> UsageBlock {
    let start = date(startISO)
    return UsageBlock(start: start, end: start.addingTimeInterval(BlockBuilder.duration),
                      lastEvent: start, tokens: tokens, money: .zero)
}

private func event(_ iso: String, output: UInt32) -> UsageEvent {
    UsageEvent(timestamp: date(iso), model: .opus5, isFast: false,
               input: 0, output: output, cacheWrite5m: 0, cacheWrite1h: 0,
               cacheRead: 0, dedupeKey: iso)
}

@Test func blockCeilingIsTheLargestCompletedBlock() {
    let now = date("2026-08-17T20:00:00Z")
    let blocks = [
        block("2026-08-15T00:00:00Z", tokens: 500_000),
        block("2026-08-16T00:00:00Z", tokens: 900_000),
        block("2026-08-17T18:00:00Z", tokens: 100_000),  // ainda em curso
    ]
    #expect(CeilingCalibrator.blockCeiling(blocks: blocks, now: now) == 900_000)
}

@Test func blockCeilingIgnoresBlocksOlderThanLookback() {
    let now = date("2026-08-17T20:00:00Z")
    let blocks = [
        block("2026-01-01T00:00:00Z", tokens: 9_000_000),  // fora dos 90 dias
        block("2026-08-16T00:00:00Z", tokens: 400_000),
    ]
    #expect(CeilingCalibrator.blockCeiling(blocks: blocks, now: now) == 400_000)
}

@Test func weeklyCeilingFindsTheHeaviestSevenDayWindow() {
    // Três dias consecutivos de 100 cada cabem numa janela de 7 dias = 300.
    let events = [
        event("2026-08-01T00:00:00Z", output: 100),
        event("2026-08-02T00:00:00Z", output: 100),
        event("2026-08-03T00:00:00Z", output: 100),
        event("2026-08-20T00:00:00Z", output: 50),   // isolado
    ]
    #expect(CeilingCalibrator.weeklyCeiling(events: events,
                                            now: date("2026-08-25T00:00:00Z")) == 300)
}

@Test func manualOverrideWins() {
    let now = date("2026-08-17T20:00:00Z")
    let ceilings = CeilingCalibrator.calibrate(
        blocks: [block("2026-08-16T00:00:00Z", tokens: 900_000)],
        events: [],
        now: now,
        override: Ceilings(blockTokens: 2_000_000, weeklyTokens: 20_000_000))
    #expect(ceilings.blockTokens == 2_000_000)
    #expect(ceilings.weeklyTokens == 20_000_000)
}

@Test func ceilingIsNeverZeroSoPercentagesStayDefined() {
    let ceilings = CeilingCalibrator.calibrate(
        blocks: [], events: [], now: date("2026-08-17T20:00:00Z"), override: nil)
    #expect(ceilings.blockTokens > 0)
    #expect(ceilings.weeklyTokens > 0)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter CeilingCalibrator 2>&1 | tail -20`
Expected: FAIL — `cannot find 'CeilingCalibrator' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Aggregation/CeilingCalibrator.swift`**

```swift
import Foundation

public struct Ceilings: Sendable, Equatable, Codable {
    public var blockTokens: UInt64
    public var weeklyTokens: UInt64

    public init(blockTokens: UInt64, weeklyTokens: UInt64) {
        self.blockTokens = blockTokens
        self.weeklyTokens = weeklyTokens
    }
}

/// Deriva o denominador dos percentuais de risco.
///
/// A Anthropic não publica os limites do Max, então o teto é o **maior consumo
/// já observado** — se o usuário chegou até ali sem travar, o limite real é ao
/// menos isso. Sempre uma estimativa, e a UI diz isso.
public enum CeilingCalibrator {
    public static let defaultLookback: TimeInterval = 90 * 24 * 60 * 60

    /// Pisos para o primeiro launch, quando ainda não há histórico suficiente.
    /// Existem só para o percentual não dividir por zero.
    static let floorBlockTokens: UInt64 = 1_000_000
    static let floorWeeklyTokens: UInt64 = 10_000_000

    public static func blockCeiling(
        blocks: [UsageBlock], now: Date, lookback: TimeInterval = defaultLookback
    ) -> UInt64 {
        let cutoff = now.addingTimeInterval(-lookback)
        return blocks
            .filter { $0.isComplete(at: now) && $0.start >= cutoff }
            .map(\.tokens)
            .max() ?? 0
    }

    /// Maior soma em qualquer janela deslizante de 7 dias, por dois ponteiros
    /// sobre os eventos ordenados.
    public static func weeklyCeiling(
        events: [UsageEvent], now: Date, lookback: TimeInterval = defaultLookback
    ) -> UInt64 {
        let cutoff = now.addingTimeInterval(-lookback)
        let window: TimeInterval = 7 * 24 * 60 * 60
        let sorted = events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        var best: UInt64 = 0
        var running: UInt64 = 0
        var tail = 0
        for head in sorted.indices {
            running += sorted[head].totalTokens
            while sorted[head].timestamp.timeIntervalSince(sorted[tail].timestamp) > window {
                running -= sorted[tail].totalTokens
                tail += 1
            }
            best = max(best, running)
        }
        return best
    }

    /// Override manual vence. Sem override, calibra pelo histórico e nunca
    /// devolve zero.
    public static func calibrate(
        blocks: [UsageBlock], events: [UsageEvent], now: Date, override: Ceilings?
    ) -> Ceilings {
        if let override { return override }
        return Ceilings(
            blockTokens: max(blockCeiling(blocks: blocks, now: now), floorBlockTokens),
            weeklyTokens: max(weeklyCeiling(events: events, now: now), floorWeeklyTokens)
        )
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `swift test --filter CeilingCalibrator 2>&1 | tail -20`
Expected: PASS — 5 testes.

- [ ] **Step 5: Commit**

```bash
git add Sources/CCUsageCore/Aggregation Tests/CCUsageCoreTests/CeilingCalibratorTests.swift
git commit -m "feat: calibração do teto do plano a partir do histórico"
```

---

### Task 8: SnapshotBuilder

**Files:**
- Create: `Sources/CCUsageCore/Models/UsageSnapshot.swift`
- Create: `Sources/CCUsageCore/SnapshotBuilder.swift`
- Test: `Tests/CCUsageCoreTests/SnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: todos os tipos das Tasks 1–7.
- Produces: `UsageSnapshot` (com `Gauge` aninhado: `tokens`, `ceiling`, `resetsAt`, `fraction`, `timeRemaining(at:)`), `SnapshotBuilder.build(events:now:calendar:override:) -> UsageSnapshot`.

- [ ] **Step 1: Escrever os testes que falham em `Tests/CCUsageCoreTests/SnapshotBuilderTests.swift`**

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func date(_ s: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(s)
}

private func event(_ iso: String, output: UInt32 = 100, model: ModelID = .opus5) -> UsageEvent {
    UsageEvent(timestamp: date(iso), model: model, isFast: false,
               input: 0, output: output, cacheWrite5m: 0, cacheWrite1h: 0,
               cacheRead: 0, dedupeKey: iso)
}

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

@Test func activeBlockCarriesResetTimeAndFraction() {
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z", output: 500_000)],
        now: now, calendar: utc,
        override: Ceilings(blockTokens: 1_000_000, weeklyTokens: 10_000_000))

    let block = snapshot.activeBlock!
    #expect(block.resetsAt == date("2026-08-17T15:00:00Z"))
    #expect(block.fraction == 0.5)
    #expect(block.timeRemaining(at: now) == 3 * 60 * 60)
}

@Test func noRecentActivityMeansNoActiveBlock() {
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-10T10:00:00Z")],
        now: date("2026-08-17T12:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.activeBlock == nil)
}

@Test func fractionIsClampedAtOne() {
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z", output: 5_000_000)],
        now: date("2026-08-17T12:00:00Z"), calendar: utc,
        override: Ceilings(blockTokens: 1_000_000, weeklyTokens: 10_000_000))
    #expect(snapshot.activeBlock!.fraction == 1.0)
}

@Test func periodTotalsArePopulated() {
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:00:00Z", output: 100),
               event("2026-08-03T10:00:00Z", output: 200)],
        now: date("2026-08-17T12:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.today.tokens == 100)
    #expect(snapshot.month.tokens == 300)
}

@Test func unknownModelsAreSurfacedByName() {
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:00:00Z", model: .unknown("claude-opus-9"))],
        now: date("2026-08-17T12:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.unknownModels == ["claude-opus-9"])
    #expect(snapshot.today.money.isPartial == true)
}

@Test func burnRateComesFromTheActiveBlock() {
    // 600.000 tokens ao longo de 60 minutos decorridos do bloco → 10.000/min.
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:00:00Z", output: 600_000)],
        now: date("2026-08-17T11:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.burnRatePerMinute == 10_000)
}

@Test func emptyHistoryProducesAnEmptySnapshot() {
    let snapshot = SnapshotBuilder.build(
        from: [], now: date("2026-08-17T12:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.activeBlock == nil)
    #expect(snapshot.today == .zero)
    #expect(snapshot.unknownModels.isEmpty)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `swift test --filter SnapshotBuilder 2>&1 | tail -20`
Expected: FAIL — `cannot find 'SnapshotBuilder' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Models/UsageSnapshot.swift`**

```swift
import Foundation

/// Tudo que a UI precisa desenhar, já calculado. Nenhuma shell conhece JSONL,
/// bloco ou preço — só recebe isto.
public struct UsageSnapshot: Sendable, Equatable {
    public struct Gauge: Sendable, Equatable {
        public let tokens: UInt64
        public let ceiling: UInt64
        public let resetsAt: Date?

        /// 0…1, saturado em 1 — o teto é estimado e pode ser ultrapassado.
        public var fraction: Double {
            guard ceiling > 0 else { return 0 }
            return min(1.0, Double(tokens) / Double(ceiling))
        }

        public func timeRemaining(at now: Date) -> TimeInterval? {
            guard let resetsAt else { return nil }
            return max(0, resetsAt.timeIntervalSince(now))
        }
    }

    public let activeBlock: Gauge?
    public let rollingWeek: Gauge
    public let today: Totals
    public let week: Totals
    public let month: Totals
    /// Tokens por minuto no bloco ativo; `nil` sem bloco ativo.
    public let burnRatePerMinute: Double?
    /// Nomes crus de modelos sem preço conhecido — a UI mostra quais são.
    public let unknownModels: Set<String>
    public let generatedAt: Date

    public static func empty(at now: Date) -> UsageSnapshot {
        UsageSnapshot(activeBlock: nil,
                      rollingWeek: Gauge(tokens: 0, ceiling: 1, resetsAt: nil),
                      today: .zero, week: .zero, month: .zero,
                      burnRatePerMinute: nil, unknownModels: [], generatedAt: now)
    }
}
```

- [ ] **Step 4: Implementar `Sources/CCUsageCore/SnapshotBuilder.swift`**

```swift
import Foundation

public enum SnapshotBuilder {
    /// Função pura: mesmos eventos + mesmo `now` = mesmo snapshot.
    /// É o que torna toda a lógica de apresentação testável sem UI.
    public static func build(
        from events: [UsageEvent],
        now: Date,
        calendar: Calendar = .current,
        override: Ceilings?
    ) -> UsageSnapshot {
        guard !events.isEmpty else { return .empty(at: now) }

        let blocks = BlockBuilder.blocks(from: events, calendar: calendar)
        let ceilings = CeilingCalibrator.calibrate(
            blocks: blocks, events: events, now: now, override: override)

        let aggregator = PeriodAggregator(calendar: calendar)
        let today = aggregator.totals(from: events, in: aggregator.todayInterval(now: now))
        let week = aggregator.totals(from: events, in: aggregator.weekInterval(now: now))
        let month = aggregator.totals(from: events, in: aggregator.monthInterval(now: now))
        let rolling = aggregator.totals(from: events, in: aggregator.rolling7Days(now: now))

        let active = blocks.last { $0.isActive(at: now) }

        let blockGauge = active.map {
            UsageSnapshot.Gauge(tokens: $0.tokens, ceiling: ceilings.blockTokens, resetsAt: $0.end)
        }

        let burnRate: Double? = active.flatMap { block in
            let elapsedMinutes = now.timeIntervalSince(block.start) / 60
            guard elapsedMinutes > 0 else { return nil }
            return Double(block.tokens) / elapsedMinutes
        }

        var unknown = Set<String>()
        for event in events {
            if let name = event.model.unknownName { unknown.insert(name) }
        }

        return UsageSnapshot(
            activeBlock: blockGauge,
            rollingWeek: UsageSnapshot.Gauge(
                tokens: rolling.tokens, ceiling: ceilings.weeklyTokens, resetsAt: nil),
            today: today, week: week, month: month,
            burnRatePerMinute: burnRate,
            unknownModels: unknown,
            generatedAt: now)
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `swift test --filter SnapshotBuilder 2>&1 | tail -20`
Expected: PASS — 7 testes.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `swift test 2>&1 | tail -10`
Expected: PASS — todos os testes das Tasks 1–8.

- [ ] **Step 7: Commit**

```bash
git add Sources/CCUsageCore Tests/CCUsageCoreTests/SnapshotBuilderTests.swift
git commit -m "feat: SnapshotBuilder — a fronteira entre core e apresentação"
```

---

### Task 9: UsageStore + FSWatcher (runtime)

**Files:**
- Create: `Sources/CCUsageCore/Watch/FSWatcher.swift`
- Create: `Sources/CCUsageCore/UsageStore.swift`
- Test: `Tests/CCUsageCoreTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `ProjectScanner`, `ParseCache`, `SnapshotBuilder`, `Ceilings` (Tasks 4, 7, 8).
- Produces: `FSWatcher(url:debounce:onChange:)` com `start()`/`stop()`, `UsageStore` (`@MainActor @Observable`) com `snapshot: UsageSnapshot`, `ceilingOverride: Ceilings?`, `refresh() async`, `start()`, `stop()`.

- [ ] **Step 1: Escrever o teste que falha em `Tests/CCUsageCoreTests/UsageStoreTests.swift`**

O store é I/O e `@MainActor`; o que se testa é que ele integra scanner + builder de ponta a ponta contra arquivos reais.

```swift
import Foundation
import Testing
@testable import CCUsageCore

private func makeRootWithOneEvent() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "cctc-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appending(path: "p"),
                                            withIntermediateDirectories: true)
    let now = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(Date())
    let line = """
    {"type":"assistant","timestamp":"\(now)","requestId":"r1",\
    "message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":0,\
    "output_tokens":1234,"cache_read_input_tokens":0}}}

    """
    try line.write(to: root.appending(path: "p/s.jsonl"), atomically: true, encoding: .utf8)
    return root
}

@MainActor
@Test func refreshLoadsEventsFromDiskIntoTheSnapshot() async throws {
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheURL = root.appending(path: "cache.json")

    let store = UsageStore(scanner: ProjectScanner(root: root), cacheURL: cacheURL)
    await store.refresh()

    #expect(store.snapshot.today.tokens == 1234)
    #expect(store.snapshot.activeBlock != nil)
}

@MainActor
@Test func refreshIsIdempotentAcrossRuns() async throws {
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheURL = root.appending(path: "cache.json")

    let store = UsageStore(scanner: ProjectScanner(root: root), cacheURL: cacheURL)
    await store.refresh()
    await store.refresh()   // segunda passada não pode duplicar

    #expect(store.snapshot.today.tokens == 1234)
}
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `swift test --filter UsageStore 2>&1 | tail -20`
Expected: FAIL — `cannot find 'UsageStore' in scope`.

- [ ] **Step 3: Implementar `Sources/CCUsageCore/Watch/FSWatcher.swift`**

```swift
import Foundation

/// Observa um diretório e chama `onChange` com debounce.
///
/// O Claude Code escreve continuamente durante uma sessão; sem o debounce o app
/// reparsearia a cada token emitido.
public final class FSWatcher: @unchecked Sendable {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.claudetokencounter.fswatcher")

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?

    public init(url: URL, debounce: TimeInterval = 2.0, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        stop()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib], queue: queue)
        source.setEventHandler { [weak self] in self?.scheduleCallback() }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func scheduleCallback() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit { stop() }
}
```

- [ ] **Step 4: Implementar `Sources/CCUsageCore/UsageStore.swift`**

```swift
import Foundation
import Observation

/// Fachada observável: mantém os eventos em memória, reage a mudanças no disco
/// e publica um `UsageSnapshot`. É o único tipo que a UI conhece.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot
    public private(set) var isLoading = false

    /// Teto manual das settings; `nil` usa a calibração automática.
    public var ceilingOverride: Ceilings? {
        didSet { rebuild() }
    }

    private let scanner: ProjectScanner
    private let cacheURL: URL
    private let lookback: TimeInterval

    private var events: [UsageEvent] = []
    private var seenKeys = Set<String>()
    private var cache = ParseCache()
    private var watcher: FSWatcher?
    private var ticker: Task<Void, Never>?

    public init(
        scanner: ProjectScanner = ProjectScanner(),
        cacheURL: URL = ParseCache.defaultURL,
        lookback: TimeInterval = 90 * 24 * 60 * 60
    ) {
        self.scanner = scanner
        self.cacheURL = cacheURL
        self.lookback = lookback
        self.snapshot = .empty(at: Date())
    }

    /// Lê o delta do disco, funde com o que já está em memória e reconstrói o snapshot.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let scanner = self.scanner
        let cache = self.cache
        let since = Date().addingTimeInterval(-lookback)

        let result: (events: [UsageEvent], cache: ParseCache)
        do {
            result = try await Task.detached(priority: .utility) {
                try scanner.ingest(since: since, cache: cache)
            }.value
        } catch {
            // Disco indisponível ou permissão negada: mantém o último snapshot bom.
            return
        }

        self.cache = result.cache
        for event in result.events where seenKeys.insert(event.dedupeKey).inserted {
            events.append(event)
        }
        try? self.cache.save(to: cacheURL)
        rebuild()
    }

    public func start() {
        cache = ParseCache.load(from: cacheURL)
        Task { await refresh() }

        watcher = FSWatcher(url: scanner.root) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        watcher?.start()

        // O bloco de 5h continua correndo mesmo sem escrita nova no disco:
        // o tempo até o reset precisa avançar sozinho.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run { self?.rebuild() }
            }
        }
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        ticker?.cancel()
        ticker = nil
    }

    private func rebuild() {
        snapshot = SnapshotBuilder.build(
            from: events, now: Date(), calendar: .current, override: ceilingOverride)
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `swift test --filter UsageStore 2>&1 | tail -20`
Expected: PASS — 2 testes.

- [ ] **Step 6: Commit**

```bash
git add Sources/CCUsageCore Tests/CCUsageCoreTests/UsageStoreTests.swift
git commit -m "feat: UsageStore observável com watching e debounce"
```

---

### Task 10: Shell de menu bar

**Files:**
- Modify: `Sources/ClaudeTokenCounter/App.swift` (substitui o stub da Task 1)
- Create: `Sources/ClaudeTokenCounter/MenuBarLabel.swift`
- Create: `Sources/ClaudeTokenCounter/Panel/UsagePanel.swift`
- Create: `Sources/ClaudeTokenCounter/Panel/Formatters.swift`

**Interfaces:**
- Consumes: `UsageStore`, `UsageSnapshot`, `Totals`, `Money` (Tasks 1, 6, 8, 9).
- Produces: nada consumido por tasks posteriores.

- [ ] **Step 1: Criar `Sources/ClaudeTokenCounter/Panel/Formatters.swift`**

```swift
import Foundation
import CCUsageCore

enum Format {
    /// 2_400_000 → "2.4M"
    static func tokens(_ value: UInt64) -> String {
        let v = Double(value)
        switch v {
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 1_000...:     return String(format: "%.1fk", v / 1_000)
        default:           return "\(value)"
        }
    }

    /// Money parcial ganha "+" para indicar que é piso, não valor exato.
    static func money(_ money: Money) -> String {
        let number = NSDecimalNumber(decimal: money.usd)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        let base = formatter.string(from: number) ?? "$0.00"
        return money.isPartial ? base + "+" : base
    }

    /// 4320 → "1h 12m"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int(fraction * 100))%"
    }
}
```

- [ ] **Step 2: Criar `Sources/ClaudeTokenCounter/MenuBarLabel.swift`**

```swift
import SwiftUI
import CCUsageCore

/// O que fica sempre visível: ícone + % do bloco de 5h.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    private var tint: Color {
        guard let fraction = snapshot.activeBlock?.fraction else { return .secondary }
        switch fraction {
        case ..<0.6: return .secondary
        case ..<0.85: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.horizontal")
            if let block = snapshot.activeBlock {
                Text(Format.percent(block.fraction))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(tint)
    }
}
```

- [ ] **Step 3: Criar `Sources/ClaudeTokenCounter/Panel/UsagePanel.swift`**

```swift
import SwiftUI
import CCUsageCore

struct UsagePanel: View {
    let snapshot: UsageSnapshot

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 16) {
                riskSection
                Divider()
                valueSection
                if !snapshot.unknownModels.isEmpty { unknownModelsNotice }
                footer
            }
            .padding(16)
            .frame(width: 320)
        }
    }

    // MARK: Risco

    @ViewBuilder
    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RISCO")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if let block = snapshot.activeBlock {
                gauge(title: "Sessão atual",
                      detail: block.resetsAt.map {
                          "reseta \(Format.clockTime($0))"
                              + (block.timeRemaining(at: snapshot.generatedAt)
                                  .map { " · em \(Format.duration($0))" } ?? "")
                      } ?? "",
                      fraction: block.fraction)
            } else {
                Text("Nenhuma sessão ativa")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            gauge(title: "Últimos 7 dias", detail: "", fraction: snapshot.rollingWeek.fraction)

            if let rate = snapshot.burnRatePerMinute {
                Text("\(Format.tokens(UInt64(rate)))/min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label("Percentuais são estimativa calibrada pelo seu histórico",
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func gauge(title: String, detail: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(Format.percent(fraction)).font(.callout.monospacedDigit())
            }
            ProgressView(value: fraction)
                .tint(fraction >= 0.85 ? .red : (fraction >= 0.6 ? .orange : .accentColor))
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Valor

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VALOR — SE FOSSE API")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 0) {
                column("HOJE", snapshot.today)
                column("SEMANA", snapshot.week)
                column("MÊS", snapshot.month)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func column(_ title: String, _ totals: Totals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(Format.tokens(totals.tokens)).font(.callout.monospacedDigit())
            Text(Format.money(totals.money))
                .font(.callout.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unknownModelsNotice: some View {
        Label("Modelo sem preço conhecido: \(snapshot.unknownModels.sorted().joined(separator: ", "))",
              systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 4: Substituir `Sources/ClaudeTokenCounter/App.swift`**

```swift
import SwiftUI
import CCUsageCore

@main
struct ClaudeTokenCounterApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(snapshot: store.snapshot)
        } label: {
            MenuBarLabel(snapshot: store.snapshot)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhaseStarted, initial: true) { _, _ in
            store.start()
        }
    }

    // MenuBarExtra não tem ciclo de vida de janela; este gatilho constante
    // apenas garante que `store.start()` rode uma vez na inicialização.
    private var scenePhaseStarted: Bool { true }
}
```

- [ ] **Step 5: Compilar**

Run: `swift build 2>&1 | tail -20`
Expected: build sem erros. Se `.onChange(of:initial:)` reclamar no contexto de `Scene`, mover a inicialização para o `init()` da struct `App` (`_store = State(initialValue: { let s = UsageStore(); s.start(); return s }())`).

- [ ] **Step 6: Rodar a suíte inteira para garantir que a UI não quebrou o core**

Run: `swift test 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeTokenCounter
git commit -m "feat: shell de menu bar com painel Liquid Glass"
```

---

### Task 11: Bundle `.app` e verificação de ponta a ponta

**Files:**
- Create: `Scripts/bundle.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: o executable da Task 10.
- Produces: `dist/ClaudeTokenCounter.app` executável.

- [ ] **Step 1: Criar `Scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClaudeTokenCounter"
BUNDLE_ID="com.synqo.claudetokencounter"
VERSION="1.0.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT"
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Claude Token Counter</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <!-- Agent app: vive só na menu bar, sem ícone no Dock. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
```

- [ ] **Step 2: Tornar executável e rodar**

Run: `chmod +x Scripts/bundle.sh && ./Scripts/bundle.sh`
Expected: termina com `==> Done: .../dist/ClaudeTokenCounter.app`.

- [ ] **Step 3: Verificar o bundle**

Run: `codesign -dv dist/ClaudeTokenCounter.app 2>&1 | head -3 && plutil -lint dist/ClaudeTokenCounter.app/Contents/Info.plist`
Expected: assinatura ad-hoc presente e `Info.plist: OK`.

- [ ] **Step 4: Smoke test contra os dados reais**

Run: `open dist/ClaudeTokenCounter.app`
Expected: ícone aparece na menu bar com um percentual; clicar abre o painel Liquid Glass com números reais em Risco e Valor. Nenhum ícone no Dock.

Se o painel mostrar `$0.00` ou tokens zerados com histórico existente, o problema é ingestão — rodar `swift test --filter ProjectScanner` e verificar `~/.claude/projects`.

- [ ] **Step 5: Criar `README.md`**

```markdown
# ClaudeTokenCounter

App de menu bar (macOS 26+) que lê os logs locais do Claude Code e mostra
consumo de tokens, risco de teto e valor equivalente em API.

## Build

Não requer Xcode — só Command Line Tools (Swift 6.4+).

```bash
swift test          # suíte do core
./Scripts/bundle.sh # monta dist/ClaudeTokenCounter.app
open dist/ClaudeTokenCounter.app
```

## Como funciona

Lê `~/.claude/projects/**/*.jsonl` (append-only, somente leitura) com parsing
incremental por offset de byte. Deduplica por `message.id` + `requestId`.

Duas métricas, respondendo perguntas diferentes:

- **Risco** — % do bloco de 5h e da janela de 7 dias. Os blocos são **derivados**
  da atividade, porque a Anthropic não persiste os horários de reset localmente.
  O teto do plano é **calibrado** pelo maior consumo já observado. Ambos são
  estimativas e a UI diz isso.
- **Valor** — tokens e $ equivalente de API hoje/semana/mês. Determinístico:
  tabela de preços por modelo e data. Modelo desconhecido nunca vira $0 —
  o total é marcado como parcial (sufixo `+`).

Detalhes em `docs/superpowers/specs/`.
```

- [ ] **Step 6: Commit**

```bash
git add Scripts/bundle.sh README.md
git commit -m "build: script de bundle .app sem Xcode + README"
```

---

## Self-Review

**Cobertura do spec:**

| Seção do spec | Task |
|---|---|
| §4 Arquitetura em camadas | 1 (Package), 8 (fronteira SnapshotBuilder) |
| §5 Modelo de dados | 1 |
| §6.1 Descoberta + filtro mtime | 4 |
| §6.2 Parsing, pré-filtro, dedup, `<synthetic>` | 3, 4 |
| §6.3 Cache incremental, truncate | 4 |
| §6.4 Watching com debounce | 9 |
| §7.1 Blocos de 5h | 5 |
| §7.2 Períodos + rolling 7d | 6 |
| §7.3 Calibração do teto | 7 |
| §8.1–8.2 Tabela base + dimensões de cache | 2 |
| §8.3 Preço com validade (Sonnet 5) | 2 |
| §8.4 Resolução de alias | 1 |
| §8.5 Modelo desconhecido → parcial | 1 (Money), 2 (nil), 8 (unknownModels), 10 (aviso) |
| §9 UI menu bar + painel | 10 |
| §10 Build sem Xcode | 11 |
| §11 Erros | 3 (linha malformada), 4 (root ausente, truncate), 9 (falha de I/O), 5+8 (sem bloco ativo) |
| §12 Testes | 1–9 |

Sem lacunas.

**Placeholders:** nenhum TBD/TODO; todo passo de código traz o código.

**Consistência de tipos:** `Money.add(cost:)` (Task 1) é chamado com `PricingTable.cost(of:)` (Task 2) nas Tasks 5, 6. `UsageBlock.money` (Task 5) e `Totals.money` (Task 6) são ambos `Money`. `Ceilings` (Task 7) é consumido por `SnapshotBuilder.build(override:)` (Task 8) e por `UsageStore.ceilingOverride` (Task 9). `BlockBuilder.duration` (Task 5) é usado no teste da Task 7. `ModelID.unknownName` (Task 1) é usado na Task 8. `UsageSnapshot.Gauge.fraction`/`timeRemaining` (Task 8) são usados na Task 10.
