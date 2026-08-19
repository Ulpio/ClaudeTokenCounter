import Foundation
import Observation

/// Assinatura do Claude. O preço é dado de negócio, não de apresentação — mora
/// aqui junto da `PricingTable`, não na UI.
public enum Plan: String, CaseIterable, Codable, Sendable {
    case pro
    case max5
    case max20

    public var monthlyPrice: Decimal {
        switch self {
        case .pro: 20
        case .max5: 100
        case .max20: 200
        }
    }

    public var label: String {
        switch self {
        case .pro: "Pro"
        case .max5: "Max 5×"
        case .max20: "Max 20×"
        }
    }

    /// Quantas vezes o valor equivalente de API consumido no mês cobre a
    /// mensalidade. `nil` sem consumo — "0×" no dia 1 do mês não informa nada.
    ///
    /// Quando o total do mês está parcial (algum modelo sem preço conhecido),
    /// este múltiplo é piso, não valor exato; quem exibe deve marcar isso.
    public func returnMultiple(forMonthly money: Money) -> Double? {
        guard money.usd > 0 else { return nil }
        return NSDecimalNumber(decimal: money.usd / monthlyPrice).doubleValue
    }
}

/// Preferências do usuário, persistidas em `UserDefaults`.
///
/// Fica no core em vez da camada de UI para ser exercitável sem instanciar
/// janela — mesma regra do resto do módulo.
@MainActor
@Observable
public final class AppSettings {
    public static let storageKey = "settings.v1"

    public var plan: Plan {
        didSet { save() }
    }

    /// `nil` = calibração automática pelo histórico.
    ///
    /// Só o teto do bloco de 5h é ajustável: a semana típica é uma comparação
    /// com o próprio ritmo, não um teto, então não há o que sobrescrever.
    public var manualBlockCeiling: UInt64? {
        didSet { save() }
    }

    /// Liga a busca ao vivo em `/api/oauth/usage`.
    ///
    /// Desligado por padrão, e por decisão explícita: ligado, o app lê o
    /// `accessToken` que o Claude Code guarda no keychain. Depender da
    /// credencial de outro app é escolha do usuário, e ausência de escolha não
    /// pode ser lida como consentimento.
    public var liveUsageEnabled: Bool {
        didSet { save() }
    }

    /// Liga as notificações de consumo.
    ///
    /// Desligado por padrão: notificação é interrupção, e interrupção não pode
    /// ser o estado inicial de nada. Ligar dispara o pedido de permissão do
    /// sistema — que é o momento certo para pedir, porque aí há contexto.
    public var alertsEnabled: Bool {
        didSet { save() }
    }

    /// Plano lido do keychain, quando disponível. Exposto mesmo quando o
    /// usuário escolheu outro: a divergência é informação, não erro — a
    /// detecção pode estar desatualizada depois de um upgrade de plano.
    public private(set) var detectedPlan: Plan?

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard,
                detectPlan: () -> Plan? = { PlanDetector.detect() }) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        let detected = detectPlan()
        self.detectedPlan = detected
        // Escolha explícita vence a detecção, que vence o default. Payload
        // corrompido não pode impedir o app de abrir.
        self.plan = stored?.plan ?? detected ?? .max20
        self.manualBlockCeiling = stored?.manualBlockCeiling
        self.liveUsageEnabled = stored?.liveUsageEnabled ?? false
        self.alertsEnabled = stored?.alertsEnabled ?? false
    }

    /// `true` quando a detecção discorda do que está selecionado — a UI avisa
    /// em vez de trocar por baixo do usuário.
    public var planDisagreesWithDetection: Bool {
        guard let detectedPlan else { return false }
        return detectedPlan != plan
    }

    public var ceilingOverride: Ceilings? {
        manualBlockCeiling.map { Ceilings(blockTokens: $0) }
    }

    private struct Payload: Codable {
        var plan: Plan
        var manualBlockCeiling: UInt64?
        /// Ausente em payload gravado antes deste campo existir. `nil` resolve
        /// para `false` no init — nunca para ligado.
        var liveUsageEnabled: Bool?
        /// Idem: ausente em payload gravado antes deste campo existir.
        var alertsEnabled: Bool?
    }

    private func save() {
        let payload = Payload(plan: plan, manualBlockCeiling: manualBlockCeiling,
                              liveUsageEnabled: liveUsageEnabled,
                              alertsEnabled: alertsEnabled)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
