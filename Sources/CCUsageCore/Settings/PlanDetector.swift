import Foundation
import Security

extension Plan {
    /// Mapeia o `rateLimitTier` que o Claude Code grava no keychain.
    ///
    /// Só `default_claude_max_5x` foi observado de verdade; as outras variantes
    /// são inferidas pela nomenclatura. Por isso o casamento é por trecho e não
    /// por igualdade: se a Anthropic mudar o prefixo, `enterprise_claude_max_5x`
    /// continua resolvendo.
    ///
    /// Tier desconhecido devolve `nil` em vez de chutar — um plano errado vira
    /// um múltiplo de retorno errado, e é melhor cair no seletor manual.
    public init?(rateLimitTier: String) {
        let tier = rateLimitTier.lowercased()
        if tier.contains("max_20x") { self = .max20 }
        else if tier.contains("max_5x") { self = .max5 }
        else if tier.contains("pro") { self = .pro }
        else { return nil }
    }
}

/// Lê o plano do keychain, do item que o Claude Code já mantém.
///
/// **Lê exclusivamente `rateLimitTier`.** O mesmo item guarda `accessToken` e
/// `refreshToken`; nada aqui os toca, e não há caminho de código neste app que
/// os leia. Isso é deliberado: o tier responde a pergunta do plano sem que o
/// app precise de credencial nenhuma.
///
/// A primeira leitura dispara o prompt de keychain do macOS, porque o item
/// pertence ao Claude Code. Negar só faz a detecção falhar — o seletor manual
/// continua valendo.
public enum PlanDetector {
    static let service = "Claude Code-credentials"

    public static func detect() -> Plan? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let tier = oauth["rateLimitTier"] as? String
        else { return nil }

        return Plan(rateLimitTier: tier)
    }
}
