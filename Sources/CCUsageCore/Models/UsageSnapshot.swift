import Foundation

/// Tudo que a UI precisa desenhar, já calculado. Nenhuma shell conhece JSONL,
/// bloco ou preço — só recebe isto.
public struct UsageSnapshot: Sendable, Equatable {
    /// Um medidor de janela. Pode vir da leitura oficial do Claude Code ou da
    /// derivação local — e sabe qual dos dois é, porque a UI precisa dizer.
    public struct Gauge: Sendable, Equatable {
        /// Razão real, sem saturação. Passa de 1 quando o consumo supera o
        /// denominador — e é aí que o número mais informa.
        public let rawFraction: Double
        public let resetsAt: Date?
        /// Preenchido só no caminho oficial: quando o Claude Code buscou o dado.
        public let officialFetchedAt: Date?
        /// Tokens e teto existem apenas no caminho derivado; o oficial devolve
        /// percentual pronto e não expõe os absolutos.
        public let tokens: UInt64?
        public let ceiling: UInt64?

        public var isOfficial: Bool { officialFetchedAt != nil }

        /// Saturada em 1, para a barra de progresso — que não pode encher além
        /// do fim.
        public var fraction: Double { min(1.0, rawFraction) }

        public func timeRemaining(at now: Date) -> TimeInterval? {
            guard let resetsAt else { return nil }
            return max(0, resetsAt.timeIntervalSince(now))
        }

        /// Há quanto tempo o dado oficial foi buscado. O cache só se move quando
        /// o Claude Code roda, então a idade é parte do dado.
        public func age(at now: Date) -> TimeInterval? {
            officialFetchedAt.map { now.timeIntervalSince($0) }
        }

        public static func official(fraction: Double, resetsAt: Date?, fetchedAt: Date) -> Gauge {
            Gauge(rawFraction: fraction, resetsAt: resetsAt, officialFetchedAt: fetchedAt,
                  tokens: nil, ceiling: nil)
        }

        public static func derived(tokens: UInt64, ceiling: UInt64, resetsAt: Date?) -> Gauge {
            Gauge(rawFraction: ceiling > 0 ? Double(tokens) / Double(ceiling) : 0,
                  resetsAt: resetsAt, officialFetchedAt: nil,
                  tokens: tokens, ceiling: ceiling)
        }
    }

    /// Sempre presente. Sem sessão em curso vem zerado e com `resetsAt` nulo —
    /// a UI continua desenhando a barra vazia em vez de trocar de layout.
    public let session: Gauge
    /// Só existe com leitura oficial: a janela semanal da Anthropic tem reset
    /// próprio, que não dá para derivar do histórico local.
    public let weekly: Gauge?
    /// Comparação com o ritmo típico. Usada quando não há semanal oficial.
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
        session: Gauge, weekly: Gauge?, weeklyPace: Pace,
        today: Totals, week: Totals, month: Totals,
        burnRatePerMinute: Double?, unknownModels: Set<String>, generatedAt: Date
    ) {
        self.session = session
        self.weekly = weekly
        self.weeklyPace = weeklyPace
        self.today = today
        self.week = week
        self.month = month
        self.burnRatePerMinute = burnRatePerMinute
        self.unknownModels = unknownModels
        self.generatedAt = generatedAt
    }

    public static func empty(at now: Date) -> UsageSnapshot {
        UsageSnapshot(session: .derived(tokens: 0, ceiling: 1, resetsAt: nil),
                      weekly: nil,
                      weeklyPace: Pace(tokens: 0, typical: 0),
                      today: .zero, week: .zero, month: .zero,
                      burnRatePerMinute: nil, unknownModels: [], generatedAt: now)
    }
}
