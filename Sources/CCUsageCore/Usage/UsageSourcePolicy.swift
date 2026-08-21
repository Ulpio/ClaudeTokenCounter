import Foundation

/// De onde veio o número que está na tela, e o que fazer se não for o ideal.
///
/// Cada caso é uma frase diferente na UI porque cada um pede uma ação diferente
/// do usuário — ou nenhuma.
public enum UsageSourceStatus: Sendable, Equatable {
    case live(at: Date)
    case cached(age: TimeInterval)
    /// Cache em uso porque o token não serve. Saída: rodar o Claude Code.
    case credentialExpired(age: TimeInterval)
    /// Cache em uso porque a chamada falhou. Saída: esperar.
    case liveUnavailable(age: TimeInterval)
    /// Cache em uso porque o payload ao vivo não tem mais a forma conhecida.
    /// Saída: atualizar o app, ou abrir issue. Não adianta esperar nem rodar o
    /// Claude Code — nenhuma das duas muda o formato que a API devolve.
    case contractUnrecognized(age: TimeInterval)
    /// Nenhuma fonte oficial; o `SnapshotBuilder` segue pelo caminho derivado.
    case derivedOnly
}

/// Relatório escolhido, com a origem que a UI precisa saber.
public struct OfficialSource: Sendable, Equatable {
    public let report: UsageReport
    public let isLive: Bool

    public init(report: UsageReport, isLive: Bool) {
        self.report = report
        self.isLive = isLive
    }
}

/// Escolhe entre a busca ao vivo e o cache.
///
/// Função pura, sem relógio próprio e sem I/O: `now` entra por parâmetro. É o
/// que torna as cinco combinações testáveis sem rede e sem keychain.
public enum UsageSourcePolicy {
    /// **Primeira condição que casar vence**, de cima para baixo. O último caso
    /// é o fundo do poço: qualquer linha acima que aponte para o cache cai nele
    /// quando o cache também está ausente.
    public static func select(
        liveEnabled: Bool,
        live: Result<UsageReport, LiveUsageError>?,
        cached: UsageReport?,
        now: Date
    ) -> (source: OfficialSource?, status: UsageSourceStatus) {
        // Sucesso de rede não é sucesso de leitura: 200 com `limits[]` vazio
        // decodifica sem erro e produz zeros. Deixar isso vencer seria mostrar
        // número errado com carimbo de "ao vivo".
        var liveWasUnrecognizable = false
        if liveEnabled, case let .success(report)? = live {
            if report.isRecognizable {
                return (OfficialSource(report: report, isLive: true), .live(at: report.fetchedAt))
            }
            liveWasUnrecognizable = true
        }

        // Cache irreconhecível não serve de fundo do poço: seus zeros são a
        // mesma mentira, só que carimbada de cache.
        guard let cached, cached.isRecognizable else { return (nil, .derivedOnly) }
        let source = OfficialSource(report: cached, isLive: false)
        // Relógio ajustado para trás não pode produzir idade negativa.
        let age = max(0, now.timeIntervalSince(cached.fetchedAt))

        if liveWasUnrecognizable {
            return (source, .contractUnrecognized(age: age))
        }

        guard liveEnabled, case let .failure(error)? = live else {
            // Live desligado, ou ligado mas ainda sem resposta na primeira
            // abertura. Nos dois casos o cache é o melhor disponível e não há
            // nada de errado a relatar.
            return (source, .cached(age: age))
        }

        switch error {
        case .noToken, .unauthorized:
            return (source, .credentialExpired(age: age))
        case .transport, .malformed:
            return (source, .liveUnavailable(age: age))
        }
    }
}
