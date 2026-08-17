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

    let store = UsageStore(scanner: ProjectScanner(root: root),
                           cacheURL: root.appending(path: "cache.json"))
    await store.refresh()

    #expect(store.snapshot.today.tokens == 1234)
    #expect(store.snapshot.session.resetsAt != nil)
}

@MainActor
@Test func historySurvivesARestart() async throws {
    // Regressão: o cache guardava só os offsets de leitura. No segundo launch
    // o ingest devolvia zero eventos ("tudo já lido") e o app acordava sem
    // histórico — tetos no piso e todos os gauges cravados em 100%.
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheURL = root.appending(path: "cache.json")

    let first = UsageStore(scanner: ProjectScanner(root: root), cacheURL: cacheURL)
    await first.refresh()
    #expect(first.snapshot.today.tokens == 1234)

    // Processo novo, mesmo cache, nenhum arquivo novo no disco.
    let restarted = UsageStore(scanner: ProjectScanner(root: root), cacheURL: cacheURL)
    restarted.start()
    #expect(restarted.snapshot.today.tokens == 1234)
    restarted.stop()
}

@MainActor
@Test func refreshIsIdempotentAcrossRuns() async throws {
    let root = try makeRootWithOneEvent()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = UsageStore(scanner: ProjectScanner(root: root),
                           cacheURL: root.appending(path: "cache.json"))
    await store.refresh()
    await store.refresh()   // segunda passada não pode duplicar

    #expect(store.snapshot.today.tokens == 1234)
}
