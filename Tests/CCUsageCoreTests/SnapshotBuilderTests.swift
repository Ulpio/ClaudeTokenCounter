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
    // Tipo explícito: `#expect` compara Optional<Double> com Int sem erro de
    // compilação e simplesmente devolve false.
    #expect(block.timeRemaining(at: now) == TimeInterval(3 * 60 * 60))
}

@Test func noRecentActivityMeansNoActiveBlock() {
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-10T10:00:00Z")],
        now: date("2026-08-17T12:00:00Z"), calendar: utc, override: nil)
    #expect(snapshot.activeBlock == nil)
}

@Test func barIsClampedButTheNumberTellsTheTruth() {
    // 5M contra teto de 1M: a barra satura em 100%, mas o texto precisa dizer
    // 500% — é justamente aí que o número informa algo.
    let snapshot = SnapshotBuilder.build(
        from: [event("2026-08-17T10:30:00Z", output: 5_000_000)],
        now: date("2026-08-17T12:00:00Z"), calendar: utc,
        override: Ceilings(blockTokens: 1_000_000, weeklyTokens: 10_000_000))
    #expect(snapshot.activeBlock!.fraction == 1.0)
    #expect(snapshot.activeBlock!.rawFraction == 5.0)
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
