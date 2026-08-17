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
