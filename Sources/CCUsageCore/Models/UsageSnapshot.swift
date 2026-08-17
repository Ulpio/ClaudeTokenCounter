import Foundation

/// Tudo que a UI precisa desenhar, já calculado. Nenhuma shell conhece JSONL,
/// bloco ou preço — só recebe isto.
public struct UsageSnapshot: Sendable, Equatable {
    public struct Gauge: Sendable, Equatable {
        public let tokens: UInt64
        public let ceiling: UInt64
        public let resetsAt: Date?

        public init(tokens: UInt64, ceiling: UInt64, resetsAt: Date?) {
            self.tokens = tokens
            self.ceiling = ceiling
            self.resetsAt = resetsAt
        }

        /// 0…1, saturado em 1. Para a barra de progresso, que não pode encher
        /// além do fim.
        public var fraction: Double {
            guard ceiling > 0 else { return 0 }
            return min(1.0, rawFraction)
        }

        /// Razão real, sem saturação. Passa de 1 quando o consumo supera o
        /// maior já observado — e é exatamente aí que o número importa: "140%"
        /// diz que você está em território inédito, "100%" esconde isso.
        public var rawFraction: Double {
            guard ceiling > 0 else { return 0 }
            return Double(tokens) / Double(ceiling)
        }

        public func timeRemaining(at now: Date) -> TimeInterval? {
            guard let resetsAt else { return nil }
            return max(0, resetsAt.timeIntervalSince(now))
        }
    }

    /// Sempre presente. Quando não há sessão em curso vem zerado e com
    /// `resetsAt == nil` — a UI continua desenhando a barra vazia em vez de
    /// trocar de layout, porque um medidor que some é pior que um medidor a zero.
    public let session: Gauge
    public let weeklyPace: Pace
    public let today: Totals
    public let week: Totals
    public let month: Totals
    /// Tokens por minuto no bloco ativo; `nil` sem bloco ativo.
    public let burnRatePerMinute: Double?
    /// Nomes crus de modelos sem preço conhecido — a UI mostra quais são.
    public let unknownModels: Set<String>
    public let generatedAt: Date

    public init(
        session: Gauge, weeklyPace: Pace,
        today: Totals, week: Totals, month: Totals,
        burnRatePerMinute: Double?, unknownModels: Set<String>, generatedAt: Date
    ) {
        self.session = session
        self.weeklyPace = weeklyPace
        self.today = today
        self.week = week
        self.month = month
        self.burnRatePerMinute = burnRatePerMinute
        self.unknownModels = unknownModels
        self.generatedAt = generatedAt
    }

    public static func empty(at now: Date) -> UsageSnapshot {
        UsageSnapshot(session: Gauge(tokens: 0, ceiling: 1, resetsAt: nil),
                      weeklyPace: Pace(tokens: 0, typical: 0),
                      today: .zero, week: .zero, month: .zero,
                      burnRatePerMinute: nil, unknownModels: [], generatedAt: now)
    }
}
