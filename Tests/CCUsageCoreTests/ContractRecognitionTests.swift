import Foundation
import Testing
@testable import CCUsageCore

// O app depende de `limits[]` porque as chaves de topo do payload são codinomes
// que rotacionam. Se aquele array mudar de forma, tudo abaixo continua
// funcionando e mostrando zero — número errado com cara de número fresco, que é
// exatamente o defeito que motivou o app existir.

private let contractNow = Date(timeIntervalSince1970: 1_787_000_000)

private func report(_ limits: [UsageReport.Limit],
                    agedBy age: TimeInterval = 0) -> UsageReport {
    UsageReport(limits: limits, fetchedAt: contractNow.addingTimeInterval(-age))
}

private func limit(_ kind: UsageReport.Limit.Kind,
                   fraction: Double = 0.5) -> UsageReport.Limit {
    .init(kind: kind, fraction: fraction, severity: .normal,
          resetsAt: nil, modelName: nil, isActive: true)
}

// MARK: - isRecognizable

@Test func emptyLimitsIsNotRecognizable() {
    #expect(report([]).isRecognizable == false)
}

@Test func onlyUnknownKindsIsNotRecognizable() {
    let r = report([limit(.other("five_hour_v2")), limit(.other("rolling_cap"))])
    #expect(r.isRecognizable == false)
}

@Test func aSessionAmongUnknownsIsRecognizable() {
    // Critério é "algum tipo conhecido", não "tem session": a Anthropic pode
    // acrescentar janelas sem quebrar nada, e isso não é contrato rompido.
    let r = report([limit(.other("something_new")), limit(.session)])
    #expect(r.isRecognizable)
}

@Test func weeklyAloneIsRecognizable() {
    // Exigir `session` assumiria que toda conta tem janela de 5h. Se a
    // suposição estiver errada, o app acusaria contrato quebrado numa conta
    // legítima — falso positivo que destrói a confiança no aviso.
    #expect(report([limit(.weeklyAll)]).isRecognizable)
}

@Test func weeklyScopedAloneIsRecognizable() {
    #expect(report([limit(.weeklyScoped)]).isRecognizable)
}

// MARK: - O select não premia relatório irreconhecível

@Test func unrecognizableLiveFallsBackToTheCacheAndSaysWhy() {
    let broken = report([])
    let cache = report([limit(.session, fraction: 0.35)], agedBy: 900)

    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: .success(broken), cached: cache, now: contractNow)

    #expect(source?.report == cache)
    #expect(source?.isLive == false)
    #expect(status == .contractUnrecognized(age: 900))
}

@Test func unrecognizableLiveAndNoCacheIsDerivedOnly() {
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: .success(report([])), cached: nil, now: contractNow)

    #expect(source == nil)
    #expect(status == .derivedOnly)
}

@Test func unrecognizableCacheIsTreatedAsAbsent() {
    // Cache irreconhecível não serve de fundo do poço: mostrar os zeros dele
    // seria a mesma mentira, só que com carimbo de cache.
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: false, live: nil, cached: report([]), now: contractNow)

    #expect(source == nil)
    #expect(status == .derivedOnly)
}

@Test func recognizableLiveStillWins() {
    // Guarda de regressão: a checagem nova não pode roubar o caminho feliz.
    let live = report([limit(.session, fraction: 0.06)])
    let (source, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: .success(live), cached: report([limit(.session)]),
        now: contractNow)

    #expect(source?.isLive == true)
    #expect(status == .live(at: live.fetchedAt))
}

@Test func brokenLiveDoesNotMaskAnExpiredCredential() {
    // Falha de credencial continua tendo precedência sobre a de contrato: as
    // saídas são diferentes, e a do token é acionável pelo usuário.
    let cache = report([limit(.session)], agedBy: 600)
    let (_, status) = UsageSourcePolicy.select(
        liveEnabled: true, live: .failure(.unauthorized), cached: cache, now: contractNow)

    #expect(status == .credentialExpired(age: 600))
}
