import Foundation

public enum SnapshotBuilder {
    /// Função pura: mesmos eventos + mesmo `now` = mesmo snapshot.
    /// É o que torna toda a lógica de apresentação testável sem UI.
    public static func build(
        from events: [UsageEvent],
        now: Date,
        calendar: Calendar = .current,
        override: Ceilings?
    ) -> UsageSnapshot {
        guard !events.isEmpty else { return .empty(at: now) }

        let blocks = BlockBuilder.blocks(from: events, calendar: calendar)
        let ceilings = CeilingCalibrator.calibrate(
            blocks: blocks, now: now, override: override)

        let aggregator = PeriodAggregator(calendar: calendar)
        let today = aggregator.totals(from: events, in: aggregator.todayInterval(now: now))
        let week = aggregator.totals(from: events, in: aggregator.weekInterval(now: now))
        let month = aggregator.totals(from: events, in: aggregator.monthInterval(now: now))
        let rolling = aggregator.totals(from: events, in: aggregator.rolling7Days(now: now))

        let active = blocks.last { $0.isActive(at: now) }

        let blockGauge = active.map {
            UsageSnapshot.Gauge(tokens: $0.tokens, ceiling: ceilings.blockTokens, resetsAt: $0.end)
        }

        let burnRate: Double? = active.flatMap { block in
            let elapsedMinutes = now.timeIntervalSince(block.start) / 60
            guard elapsedMinutes > 0 else { return nil }
            return Double(block.tokens) / elapsedMinutes
        }

        var unknown = Set<String>()
        for event in events {
            if let name = event.model.unknownName { unknown.insert(name) }
        }

        return UsageSnapshot(
            activeBlock: blockGauge,
            weeklyPace: Pace(
                tokens: rolling.tokens,
                typical: CeilingCalibrator.typicalWeek(events: events, now: now)),
            today: today, week: week, month: month,
            burnRatePerMinute: burnRate,
            unknownModels: unknown,
            generatedAt: now)
    }
}
