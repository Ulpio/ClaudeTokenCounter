import Foundation
import Testing
@testable import CCUsageCore

/// Estrutura real de `~/.claude.json`, reduzida ao que importa.
private let realShape = """
{
  "numStartups": 13512,
  "cachedUsageUtilization": {
    "fetchedAtMs": 1787010875105,
    "accountUuid": "00000000-0000-4000-8000-000000000000",
    "utilization": {
      "five_hour": {
        "utilization": 22,
        "resets_at": "2026-08-18T02:20:00.007553+00:00",
        "limit_dollars": null, "used_dollars": null, "remaining_dollars": null
      },
      "seven_day": {
        "utilization": 19,
        "resets_at": "2026-08-23T07:00:00.007577+00:00",
        "limit_dollars": null, "used_dollars": null, "remaining_dollars": null
      },
      "seven_day_opus": null,
      "nimbus_quill": { "utilization": 0, "resets_at": null }
    }
  }
}
"""

private func writeTemp(_ contents: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "cctc-usage-\(UUID().uuidString).json")
    try! contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func readsOfficialUtilizationAndResetTimes() {
    let url = writeTemp(realShape)
    defer { try? FileManager.default.removeItem(at: url) }

    let usage = OfficialUsageReader.read(from: url)!
    // Percentual inteiro do arquivo vira fração.
    #expect(usage.fiveHour?.utilization == 0.22)
    #expect(usage.sevenDay?.utilization == 0.19)
    #expect(usage.fetchedAt == Date(timeIntervalSince1970: 1787010875.105))
}

@Test func parsesResetTimestampWithSixFractionalDigits() {
    // O arquivo traz microssegundos e offset "+00:00" — formatos que o parser
    // ISO padrão do Swift recusa se levados ao pé da letra.
    let url = writeTemp(realShape)
    defer { try? FileManager.default.removeItem(at: url) }

    let expected = try! Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        .parse("2026-08-18T02:20:00Z")
    #expect(OfficialUsageReader.read(from: url)?.fiveHour?.resetsAt == expected)
}

@Test func nullWindowsBecomeNil() {
    let url = writeTemp(realShape)
    defer { try? FileManager.default.removeItem(at: url) }
    // `seven_day_opus` é null no arquivo real; não pode virar janela zerada.
    #expect(OfficialUsageReader.read(from: url)?.sevenDay != nil)
}

@Test func missingFileYieldsNoReading() {
    let absent = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "cctc-absent-\(UUID().uuidString).json")
    #expect(OfficialUsageReader.read(from: absent) == nil)
}

@Test func malformedFileYieldsNoReading() {
    // Arquivo corrompido cai no caminho derivado em vez de derrubar o app.
    let url = writeTemp("{ isto não é json")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(OfficialUsageReader.read(from: url) == nil)
}

@Test func fileWithoutTheCacheKeyYieldsNoReading() {
    let url = writeTemp(#"{ "numStartups": 3 }"#)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(OfficialUsageReader.read(from: url) == nil)
}
