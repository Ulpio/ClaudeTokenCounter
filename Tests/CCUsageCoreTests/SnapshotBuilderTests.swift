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
        override: Ceilings(blockTokens: 1_000_000))

    let block = snapshot.session
    #expect(block.resetsAt == date("2026-08-17T15:00:00Z"))
    #expect(block.fraction == 0.5)
    // Tipo explícito: `#expect` compara Optional<Double> com Int sem erro de
    // compilação e simplesmente devolve false.
    #expect(block.timeRemaining(at: now) == TimeInterval(3 * 60 * 60))
}

@Test func idleSessionKeepsTheGaugeAtZeroInsteadOfRemovingIt() {
    // Acabou de resetar é justamente quando "0% de quanto" informa mais: a
    // barra continua existindo, zerada e sem horário de reset.
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-10T10:00:00Z")],
        now: date("2026-08-17T12:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.session.resetsAt == nil)
    #expect(snapshot.session.tokens == 0)
    #expect(snapshot.session.fraction == 0)
    #expect((snapshot.session.ceiling ?? 0) > 0)   // denominador definido mesmo ocioso
    #expect(snapshot.burnRatePerMinute == nil)
}

@Test func barIsClampedButTheNumberTellsTheTruth() {
    // 5M contra teto de 1M: a barra satura em 100%, mas o texto precisa dizer
    // 500% — é justamente aí que o número informa algo.
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z", output: 5_000_000)],
        now: date("2026-08-17T12:00:00Z"), calendar: utc,
        override: Ceilings(blockTokens: 1_000_000))
    #expect(snapshot.session.fraction == 1.0)
    #expect(snapshot.session.rawFraction == 5.0)
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
    #expect(snapshot.session.resetsAt == nil)
    #expect(snapshot.today == .zero)
    #expect(snapshot.unknownModels.isEmpty)
}


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

@Test func officialNumbersSurviveAnEmptyLocalHistory() {
    // Sem isto, o `guard !events.isEmpty` no topo do build descartaria números
    // oficiais perfeitamente válidos. Instalação nova, pasta de projetos limpa,
    // ou uso do Claude Code em outra máquina: o app mostraria nada tendo dado
    // ao vivo na mão. Fica mais provável justamente agora que a fonte ao vivo
    // não depende mais de haver JSONL local.
    let now = date("2026-08-17T12:00:00Z")
    let snapshot = SnapshotBuilder.build(
        from: [], now: now, calendar: utc, override: nil,
        official: officialSource([limit(.session, 0.06, resetsAt: date("2026-08-17T15:20:00Z")),
                                  limit(.weeklyAll, 0.25, isActive: true)],
                                 fetchedAt: now, isLive: true),
        status: .live(at: now))

    #expect(snapshot.session.rawFraction == 0.06)
    #expect(snapshot.weekly?.rawFraction == 0.25)
    #expect(snapshot.sourceStatus == .live(at: now))
    // Sem eventos locais não há custo a somar — isso continua zerado, e certo.
    #expect(snapshot.today.tokens == 0)
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
