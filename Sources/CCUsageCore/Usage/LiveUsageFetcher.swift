import Foundation

/// Por que a busca falhou. Cada caso vira uma frase diferente na UI, porque a
/// saída para o usuário é diferente: reautenticar, esperar, ou nada a fazer.
public enum LiveUsageError: Error, Equatable {
    /// Sem token legível, ou o token venceu. Nenhuma chamada foi feita.
    case noToken
    /// 401 ou 403. Caminho normal, não excepcional: o token vive horas.
    case unauthorized
    /// Rede indisponível.
    case transport
    /// Resposta que não dá para interpretar — inclui erro de servidor.
    case malformed
}

/// Busca os números de uso ao vivo, na mesma chamada que o próprio Claude Code
/// faz.
///
/// Existe porque o cache de `~/.claude.json` só se move quando o Claude Code
/// roda: numa medição real ele estava 13h defasado e reportava 35% numa janela
/// de 5h cujo valor verdadeiro era 6% — a janela inteira já tinha resetado.
///
/// Endpoint interno e indocumentado (a spec §5 C5): toda falha é tipada e quem
/// chama degrada para o cache.
public struct LiveUsageFetcher: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Obrigatório: sem ele o endpoint não responde o formato esperado.
    public static let betaHeaderValue = "oauth-2025-04-20"

    private let source: any CredentialSource
    private let session: URLSession

    public init(source: any CredentialSource, session: URLSession = .shared) {
        self.source = source
        self.session = session
    }

    public func fetch(at now: Date) async throws -> UsageReport {
        // Confere a validade antes de gastar rede: um token vencido só pode
        // voltar 401, e o usuário merece a frase certa mais rápido.
        guard let token = source.credentials()?.usableToken(at: now) else {
            throw LiveUsageError.noToken
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LiveUsageError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw LiveUsageError.malformed }
        // 403 chega quando o token não tem o escopo `user:profile`. A saída para
        // o usuário é a mesma do 401: reautenticar pelo Claude Code.
        if http.statusCode == 401 || http.statusCode == 403 { throw LiveUsageError.unauthorized }

        guard http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let report = UsageReportDecoder.decode(root, fetchedAt: now)
        else { throw LiveUsageError.malformed }

        return report
    }
}
