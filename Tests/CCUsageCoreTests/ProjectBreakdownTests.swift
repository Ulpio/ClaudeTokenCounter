import Foundation
import Testing
@testable import CCUsageCore

private let now = Date(timeIntervalSince1970: 1_787_000_000)

private func event(_ project: String, at offset: TimeInterval, id: String) -> UsageEvent {
    UsageEvent(timestamp: now.addingTimeInterval(offset), model: .opus5, isFast: false,
               input: 0, output: 100, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0,
               dedupeKey: id, project: project)
}

@Test func theSnapshotCarriesTheBreakdownPerPeriod() {
    let snapshot = SnapshotBuilder.build(
        from: [event("-Users-me-a", at: -60, id: "1"),
               event("-Users-me-b", at: -120, id: "2")],
        now: now, override: nil)

    #expect(snapshot.projects.today["-Users-me-a"]?.tokens == 100)
    #expect(snapshot.projects.today["-Users-me-b"]?.tokens == 100)
}

@Test func theBreakdownAgreesWithTheOverallTotals() {
    // Se divergir, a aba Projetos some com consumo que a aba Agora mostra, e a
    // diferenca aparece como uso que nao e de ninguem.
    let events = [event("-Users-me-a", at: -60, id: "1"),
                  event("", at: -90, id: "2")]
    let snapshot = SnapshotBuilder.build(from: events, now: now, override: nil)

    let summed = snapshot.projects.today.values.reduce(UInt64(0)) { $0 + $1.tokens }
    #expect(summed == snapshot.today.tokens)
}

@Test func theUnattributedKeySurvivesInTheBreakdown() {
    let snapshot = SnapshotBuilder.build(
        from: [event("", at: -60, id: "1")], now: now, override: nil)
    #expect(snapshot.projects.today[""]?.tokens == 100)
}

@Test func anEmptySnapshotHasAnEmptyBreakdown() {
    #expect(UsageSnapshot.empty(at: now).projects == .empty)
}
