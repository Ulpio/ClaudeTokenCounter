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

        /// 0…1, saturado em 1 — o teto é estimado e pode ser ultrapassado.
        public var fraction: Double {
            guard ceiling > 0 else { return 0 }
            return min(1.0, Double(tokens) / Double(ceiling))
        }

        public func timeRemaining(at now: Date) -> TimeInterval? {
            guard let resetsAt else { return nil }
            return max(0, resetsAt.timeIntervalSince(now))
        }
    }

    public let activeBlock: Gauge?
    public let rollingWeek: Gauge
    public let today: Totals
    public let week: Totals
    public let month: Totals
    /// Tokens por minuto no bloco ativo; `nil` sem bloco ativo.
    public let burnRatePerMinute: Double?
    /// Nomes crus de modelos sem preço conhecido — a UI mostra quais são.
    public let unknownModels: Set<String>
    public let generatedAt: Date

    public init(
        activeBlock: Gauge?, rollingWeek: Gauge,
        today: Totals, week: Totals, month: Totals,
        burnRatePerMinute: Double?, unknownModels: Set<String>, generatedAt: Date
    ) {
        self.activeBlock = activeBlock
        self.rollingWeek = rollingWeek
        self.today = today
        self.week = week
        self.month = month
        self.burnRatePerMinute = burnRatePerMinute
        self.unknownModels = unknownModels
        self.generatedAt = generatedAt
    }

    public static func empty(at now: Date) -> UsageSnapshot {
        UsageSnapshot(activeBlock: nil,
                      rollingWeek: Gauge(tokens: 0, ceiling: 1, resetsAt: nil),
                      today: .zero, week: .zero, month: .zero,
                      burnRatePerMinute: nil, unknownModels: [], generatedAt: now)
    }
}
