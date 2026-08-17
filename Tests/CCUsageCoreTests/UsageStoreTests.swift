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
    #expect(store.snapshot.activeBlock != nil)
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
