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
