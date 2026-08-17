import Foundation

public struct Ceilings: Sendable, Equatable, Codable {
    public var blockTokens: UInt64
    public var weeklyTokens: UInt64

    public init(blockTokens: UInt64, weeklyTokens: UInt64) {
        self.blockTokens = blockTokens
        self.weeklyTokens = weeklyTokens
    }
}

/// Deriva o denominador dos percentuais de risco.
///
/// A Anthropic não publica os limites do Max, então o teto é o **maior consumo
/// já observado** — se o usuário chegou até ali sem travar, o limite real é ao
/// menos isso. Sempre uma estimativa, e a UI diz isso.
public enum CeilingCalibrator {
    public static let defaultLookback: TimeInterval = 90 * 24 * 60 * 60

    /// Pisos para o primeiro launch, quando ainda não há histórico suficiente.
    /// Existem só para o percentual não dividir por zero.
    static let floorBlockTokens: UInt64 = 1_000_000
    static let floorWeeklyTokens: UInt64 = 10_000_000

    public static func blockCeiling(
        blocks: [UsageBlock], now: Date, lookback: TimeInterval = defaultLookback
    ) -> UInt64 {
        let cutoff = now.addingTimeInterval(-lookback)
        return blocks
            .filter { $0.isComplete(at: now) && $0.start >= cutoff }
            .map(\.tokens)
            .max() ?? 0
    }

    /// Maior soma em qualquer janela deslizante de 7 dias, por dois ponteiros
    /// sobre os eventos ordenados.
    public static func weeklyCeiling(
        events: [UsageEvent], now: Date, lookback: TimeInterval = defaultLookback
    ) -> UInt64 {
        let cutoff = now.addingTimeInterval(-lookback)
        let window: TimeInterval = 7 * 24 * 60 * 60
        let sorted = events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        var best: UInt64 = 0
        var running: UInt64 = 0
        var tail = 0
        for head in sorted.indices {
            running += sorted[head].totalTokens
            while sorted[head].timestamp.timeIntervalSince(sorted[tail].timestamp) > window {
                running -= sorted[tail].totalTokens
                tail += 1
            }
            best = max(best, running)
        }
        return best
    }

    /// Override manual vence. Sem override, calibra pelo histórico e nunca
    /// devolve zero.
    public static func calibrate(
        blocks: [UsageBlock], events: [UsageEvent], now: Date, override: Ceilings?
    ) -> Ceilings {
        if let override { return override }
        return Ceilings(
            blockTokens: max(blockCeiling(blocks: blocks, now: now), floorBlockTokens),
            weeklyTokens: max(weeklyCeiling(events: events, now: now), floorWeeklyTokens)
        )
    }
}
