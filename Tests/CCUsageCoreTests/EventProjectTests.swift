import Foundation
import Testing
@testable import CCUsageCore

// O ProjectScanner anda em ~/.claude/projects/**, mas até aqui o UsageEvent não
// carregava de qual projeto a linha veio — a origem passava pelo parser e era
// descartada. Sem ela, "qual projeto comeu minha semana" é impossível de
// responder com dados que o app já lê.

private func line(id: String, timestamp: String = "2026-08-20T10:00:00.000Z") -> Data {
    Data("""
    {"type":"assistant","requestId":"req-\(id)","timestamp":"\(timestamp)",\
    "message":{"id":"msg-\(id)","model":"claude-opus-5",\
    "usage":{"input_tokens":10,"output_tokens":20}}}
    """.utf8)
}

private func makeTree(_ projects: [String: [String]]) throws -> URL {
    let root = URL.temporaryDirectory.appending(path: "ctc-proj-\(UUID().uuidString)")
    for (project, ids) in projects {
        let dir = root.appending(path: project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = ids.map { String(decoding: line(id: $0), as: UTF8.self) }
                      .joined(separator: "\n") + "\n"
        try Data(body.utf8).write(to: dir.appending(path: "session.jsonl"))
    }
    return root
}

// MARK: - O parser recebe o projeto de fora

@Test func theParserCarriesTheProjectItWasGiven() {
    let event = JSONLParser.event(from: line(id: "a"), project: "-Users-me-Projects-Alpha")
    #expect(event?.project == "-Users-me-Projects-Alpha")
}

// MARK: - O scanner deriva o projeto do caminho

@Test func theScannerDerivesTheProjectFromTheDirectoryUnderRoot() throws {
    let root = try makeTree(["-Users-me-Projects-Alpha": ["a"],
                             "-Users-me-Projects-Beta": ["b"]])
    defer { try? FileManager.default.removeItem(at: root) }

    let (events, _) = try ProjectScanner(root: root)
        .ingest(since: .distantPast, cache: ParseCache())

    #expect(Set(events.map(\.project)) == ["-Users-me-Projects-Alpha",
                                           "-Users-me-Projects-Beta"])
}

@Test func nestedFilesStillReportTheTopLevelProject() throws {
    // O Claude Code aninha sessões em subdiretórios. O projeto é sempre o
    // componente logo abaixo da raiz, não o diretório que contém o arquivo.
    let root = URL.temporaryDirectory.appending(path: "ctc-nested-\(UUID().uuidString)")
    let deep = root.appending(path: "-Users-me-Projects-Alpha/subdir")
    try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
    try Data((String(decoding: line(id: "z"), as: UTF8.self) + "\n").utf8)
        .write(to: deep.appending(path: "session.jsonl"))
    defer { try? FileManager.default.removeItem(at: root) }

    let (events, _) = try ProjectScanner(root: root)
        .ingest(since: .distantPast, cache: ParseCache())

    #expect(events.count == 1)
    #expect(events.first?.project == "-Users-me-Projects-Alpha")
}

// MARK: - Cache antigo continua decodificando

@Test func aCacheWrittenBeforeTheFieldExistedStillLoads() throws {
    // O ParseCache descarta em silêncio o que não decodifica, e um descarte
    // custa reparse de 90 dias — mais os eventos cujos .jsonl já sumiram do
    // disco, que o cache é o único lugar a guardar.
    let url = URL.temporaryDirectory.appending(path: "ctc-old-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    // A fixture sai do encoder de verdade, com o campo removido depois. Escrita
    // à mão ela codificaria um palpite sobre a forma de ModelID e testaria o
    // palpite, não a compatibilidade.
    let event = JSONLParser.event(from: line(id: "a"), project: "-Users-me-Projects-Alpha")!
    let encoded = try JSONEncoder().encode(ParseCache(files: [:], events: [event]))
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    var events = object["events"] as! [[String: Any]]
    events[0].removeValue(forKey: "project")
    object["events"] = events
    try JSONSerialization.data(withJSONObject: object).write(to: url)

    let loaded = ParseCache.load(from: url)
    #expect(loaded.events.count == 1, "cache antigo foi descartado em vez de migrar")
    #expect(loaded.events.first?.project == "")
}

@Test func theProjectSurvivesASaveAndLoad() throws {
    let url = URL.temporaryDirectory.appending(path: "ctc-rt-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    let event = JSONLParser.event(from: line(id: "a"), project: "-Users-me-Projects-Alpha")!
    try ParseCache(files: [:], events: [event]).save(to: url)

    #expect(ParseCache.load(from: url).events.first?.project == "-Users-me-Projects-Alpha")
}
