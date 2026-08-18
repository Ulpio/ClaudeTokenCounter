import Foundation
import Testing
@testable import CCUsageCore

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "cctc-test-\(UUID().uuidString)")!
}

@Test func planPricesMatchTheSubscriptionTiers() {
    #expect(Plan.pro.monthlyPrice == 20)
    #expect(Plan.max5.monthlyPrice == 100)
    #expect(Plan.max20.monthlyPrice == 200)
}

@Test func returnMultipleDividesMonthlyValueByThePlanPrice() {
    #expect(Plan.max20.returnMultiple(forMonthly: Money(usd: 600, isPartial: false)) == 3.0)
    #expect(Plan.max5.returnMultiple(forMonthly: Money(usd: 600, isPartial: false)) == 6.0)
}

@Test func noReturnMultipleBeforeAnyConsumption() {
    // 0× no dia 1 do mês não informa nada; melhor não mostrar linha nenhuma.
    #expect(Plan.max20.returnMultiple(forMonthly: .zero) == nil)
}

/// Detector neutralizado de propósito: sem isso o teste lê o keychain real,
/// depende do plano de quem executa e paga o custo do prompt.
@MainActor
@Test func defaultsToMax20WithAutomaticCeiling() {
    let settings = AppSettings(defaults: freshDefaults(), detectPlan: { nil })
    #expect(settings.plan == .max20)
    #expect(settings.manualBlockCeiling == nil)
    #expect(settings.ceilingOverride == nil)
}

@MainActor
@Test func settingsSurviveARestart() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults, detectPlan: { nil })
    first.plan = .max5
    first.manualBlockCeiling = 500_000

    let restarted = AppSettings(defaults: defaults, detectPlan: { nil })
    #expect(restarted.plan == .max5)
    #expect(restarted.manualBlockCeiling == 500_000)
}

@MainActor
@Test func manualCeilingBecomesAnOverrideAndAutomaticClearsIt() {
    let settings = AppSettings(defaults: freshDefaults(), detectPlan: { nil })
    settings.manualBlockCeiling = 214_400_000
    #expect(settings.ceilingOverride == Ceilings(blockTokens: 214_400_000))

    settings.manualBlockCeiling = nil
    #expect(settings.ceilingOverride == nil)
}

@MainActor
@Test func corruptedDefaultsFallBackToTheDefaults() {
    // Payload inválido não pode impedir o app de abrir.
    let defaults = freshDefaults()
    defaults.set(Data("não é json".utf8), forKey: AppSettings.storageKey)
    let settings = AppSettings(defaults: defaults, detectPlan: { nil })
    #expect(settings.plan == .max20)
}

@MainActor
@Test func liveUsageIsOffUntilTheUserSaysOtherwise() {
    // O app passa a depender de credencial de outro app. Isso é escolha do
    // usuário, não default.
    let settings = AppSettings(defaults: freshDefaults(), detectPlan: { nil })
    #expect(settings.liveUsageEnabled == false)
}

@MainActor
@Test func liveUsageChoiceSurvivesRestart() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults, detectPlan: { nil })
    first.liveUsageEnabled = true

    let restarted = AppSettings(defaults: defaults, detectPlan: { nil })
    #expect(restarted.liveUsageEnabled)
}

@MainActor
@Test func settingsSavedBeforeTheToggleExistedStayOff() {
    // Payload gravado por uma versão anterior não tem o campo. Ausência não
    // pode virar "ligado" — seria autorizar a leitura do token sem perguntar.
    let defaults = freshDefaults()
    let legacy = #"{"plan":"max5"}"#
    defaults.set(Data(legacy.utf8), forKey: AppSettings.storageKey)

    let settings = AppSettings(defaults: defaults, detectPlan: { nil })
    #expect(settings.plan == .max5)
    #expect(settings.liveUsageEnabled == false)
}
