import Foundation
import Testing
@testable import CCUsageCore

private let base = Date(timeIntervalSince1970: 1_787_000_000)

private func event(_ project: String, at offset: TimeInterval,
                   output: UInt32 = 100, id: String = UUID().uuidString) -> UsageEvent {
    UsageEvent(timestamp: base.addingTimeInterval(offset), model: .opus5, isFast: false,
               input: 0, output: output, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0,
               dedupeKey: id, project: project)
}

private let aggregator = PeriodAggregator(calendar: .current)
private let window = DateInterval(start: base, end: base.addingTimeInterval(3600))

@Test func totalsAreGroupedByProject() {
    let events = [event("alpha", at: 10), event("alpha", at: 20), event("beta", at: 30)]
    let byProject = aggregator.totalsByProject(from: events, in: window)

    #expect(byProject.count == 2)
    #expect(byProject["alpha"]?.tokens == 200)
    #expect(byProject["beta"]?.tokens == 100)
}

@Test func theIntervalFiltersBeforeGrouping() {
    // Fora da janela não deve criar chave: um projeto sem uso no período não é
    // um projeto com zero, é um projeto que não aparece na lista.
    let events = [event("alpha", at: 10), event("beta", at: -60)]
    let byProject = aggregator.totalsByProject(from: events, in: window)

    #expect(byProject.keys.sorted() == ["alpha"])
}

@Test func theEndBoundaryBelongsToTheNextPeriod() {
    // Mesmo intervalo semiaberto [start, end) que o `totals` usa. Divergir aqui
    // faria a soma por projeto não bater com o total geral na virada da hora.
    let events = [event("alpha", at: 3600), event("alpha", at: 3599)]
    #expect(aggregator.totalsByProject(from: events, in: window)["alpha"]?.tokens == 100)
}

@Test func eventsWithoutAProjectGroupUnderTheEmptyKey() {
    // Evento vindo de cache antigo tem projeto vazio. Ele não pode sumir da
    // agregação: a soma das partes deixaria de bater com o total, e a diferença
    // apareceria como consumo que não é de ninguém.
    let events = [event("", at: 10), event("alpha", at: 20)]
    let byProject = aggregator.totalsByProject(from: events, in: window)

    #expect(byProject[""]?.tokens == 100)
    #expect(byProject.count == 2)
}

@Test func theSumOfProjectsMatchesTheOverallTotal() {
    let events = [event("alpha", at: 10), event("beta", at: 20), event("", at: 30)]
    let overall = aggregator.totals(from: events, in: window)
    let summed = aggregator.totalsByProject(from: events, in: window)
        .values.reduce(UInt64(0)) { $0 + $1.tokens }

    #expect(summed == overall.tokens)
}

@Test func noEventsProducesAnEmptyMap() {
    #expect(aggregator.totalsByProject(from: [], in: window).isEmpty)
}
