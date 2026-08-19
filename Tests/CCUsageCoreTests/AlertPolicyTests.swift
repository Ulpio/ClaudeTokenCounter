import Foundation
import Testing
@testable import CCUsageCore

private let noon = Date(timeIntervalSince1970: 1_755_000_000)
private let resetA = noon.addingTimeInterval(3600)
private let resetB = noon.addingTimeInterval(7200)

private func gauge(_ percent: Double,
                   resetsAt: Date?,
                   provenance: UsageSnapshot.Provenance = .live(at: noon)) -> UsageSnapshot.Gauge {
    UsageSnapshot.Gauge(rawFraction: percent / 100, resetsAt: resetsAt, provenance: provenance,
                        severity: nil, isActive: true, tokens: nil, ceiling: nil)
}

private func snapshot(_ session: UsageSnapshot.Gauge,
                      weekly: UsageSnapshot.Gauge? = nil) -> UsageSnapshot {
    UsageSnapshot(session: session, weekly: weekly, scopedWeekly: [],
                  weeklyPace: Pace(tokens: 0, typical: 0),
                  today: .zero, week: .zero, month: .zero,
                  burnRatePerMinute: nil, unknownModels: [], generatedAt: noon,
                  calibratedBlockCeiling: 1, sourceStatus: .live(at: noon))
}

/// Atalho: alertas ligados, ao vivo ligado — o cenário em que a política de fato
/// trabalha. Os casos de desligado são explícitos nos testes que os exercitam.
private func evaluate(_ policy: inout AlertPolicy, _ s: UsageSnapshot) -> [Alert] {
    policy.evaluate(s, alertsEnabled: true, liveEnabled: true)
}

// MARK: - Linha de base

/// O app não viu o consumo subir, ele chegou depois. Disparar aqui afirmaria um
/// cruzamento que ninguém observou.
@Test func firstSnapshotOfAWindowNeverAlerts() {
    var policy = AlertPolicy()
    #expect(evaluate(&policy, snapshot(gauge(92, resetsAt: resetA))).isEmpty)
}

@Test func crossingAThresholdAlertsOnce() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    let alerts = evaluate(&policy, snapshot(gauge(81, resetsAt: resetA)))
    #expect(alerts == [.threshold(window: .session, percent: 80, resetsAt: resetA)])
}

@Test func theSameThresholdNeverAlertsTwiceInOneWindow() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(81, resetsAt: resetA)))
    #expect(evaluate(&policy, snapshot(gauge(85, resetsAt: resetA))).isEmpty)
}

@Test func aNewWindowRearmsTheThresholds() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(81, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(2, resetsAt: resetB)))
    let alerts = evaluate(&policy, snapshot(gauge(82, resetsAt: resetB)))
    #expect(alerts.contains(.threshold(window: .session, percent: 80, resetsAt: resetB)))
}

// MARK: - Confiança na fonte

@Test func cachedProvenanceNeverAlerts() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA, provenance: .cached(at: noon))))
    #expect(evaluate(&policy, snapshot(gauge(85, resetsAt: resetA, provenance: .cached(at: noon)))).isEmpty)
}

/// Um snapshot pode ter procedência mista: a semanal vem oficial enquanto a
/// sessão cai no derivado. Checar o status do snapshot em vez do medidor
/// deixaria passar alerta sobre número estimado.
@Test func aDerivedGaugeInsideALiveSnapshotNeverAlerts() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA, provenance: .derived)))
    #expect(evaluate(&policy, snapshot(gauge(85, resetsAt: resetA, provenance: .derived))).isEmpty)
}

@Test func aWindowWithoutResetDateNeverAlerts() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: nil)))
    #expect(evaluate(&policy, snapshot(gauge(85, resetsAt: nil))).isEmpty)
}

/// Caso medido: a troca de cache velho para ao vivo derrubou a fração de 35%
/// para 6%. Subir de novo não pode redisparar o que já saiu.
@Test func aFractionThatFallsAndRisesDoesNotRealert() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(81, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(6, resetsAt: resetA)))
    #expect(evaluate(&policy, snapshot(gauge(83, resetsAt: resetA))).isEmpty)
}

// MARK: - Reset

@Test func resetAlertsWhenTheWindowHadFired() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(81, resetsAt: resetA)))
    let alerts = evaluate(&policy, snapshot(gauge(1, resetsAt: resetB)))
    #expect(alerts == [.windowReset(window: .session)])
}

/// Quatro ou cinco resets por dia; avisar todos seria spam. Só quem encostou no
/// teto tem interesse em saber que a capacidade voltou.
@Test func resetIsSilentWhenTheWindowNeverFired() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(10, resetsAt: resetA)))
    #expect(evaluate(&policy, snapshot(gauge(1, resetsAt: resetB))).isEmpty)
}

// MARK: - Chaves

@Test func liveRequiredIsEmittedOncePerRun() {
    var policy = AlertPolicy()
    let first = policy.evaluate(snapshot(gauge(50, resetsAt: resetA)),
                                alertsEnabled: true, liveEnabled: false)
    let second = policy.evaluate(snapshot(gauge(60, resetsAt: resetA)),
                                 alertsEnabled: true, liveEnabled: false)
    #expect(first == [.liveRequired])
    #expect(second.isEmpty)
}

@Test func nothingIsEmittedWhileAlertsAreOff() {
    var policy = AlertPolicy()
    _ = policy.evaluate(snapshot(gauge(70, resetsAt: resetA)), alertsEnabled: false, liveEnabled: true)
    let crossing = policy.evaluate(snapshot(gauge(96, resetsAt: resetA)),
                                   alertsEnabled: false, liveEnabled: true)
    let reset = policy.evaluate(snapshot(gauge(1, resetsAt: resetB)),
                                alertsEnabled: false, liveEnabled: true)
    #expect(crossing.isEmpty)
    #expect(reset.isEmpty)
}

// MARK: - Semanal

@Test func theWeeklyWindowAlertsIndependently() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(10, resetsAt: resetA), weekly: gauge(70, resetsAt: resetB)))
    let alerts = evaluate(&policy, snapshot(gauge(10, resetsAt: resetA), weekly: gauge(82, resetsAt: resetB)))
    #expect(alerts == [.threshold(window: .weekly, percent: 80, resetsAt: resetB)])
}

/// Um salto que passa por dois limiares de uma vez rende **um** alerta, o mais
/// alto. Dois banners pelo mesmo evento é a sensação de spam que a feature
/// existe para não produzir, e o de 80% já nasceria como notícia velha.
@Test func crossingTwoThresholdsAtOnceAlertsOnlyTheHighest() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    let alerts = evaluate(&policy, snapshot(gauge(96, resetsAt: resetA)))
    #expect(alerts == [.threshold(window: .session, percent: 95, resetsAt: resetA)])
}

/// E o limiar pulado fica marcado como resolvido, não pendente: ele não pode
/// disparar depois, quando a fração já passou muito dele.
@Test func aSkippedThresholdDoesNotFireLater() {
    var policy = AlertPolicy()
    _ = evaluate(&policy, snapshot(gauge(70, resetsAt: resetA)))
    _ = evaluate(&policy, snapshot(gauge(96, resetsAt: resetA)))
    #expect(evaluate(&policy, snapshot(gauge(97, resetsAt: resetA))).isEmpty)
}
