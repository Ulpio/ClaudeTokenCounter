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

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        // Payload corrompido não pode impedir o app de abrir.
        self.plan = stored?.plan ?? .max20
        self.manualBlockCeiling = stored?.manualBlockCeiling
    }

    public var ceilingOverride: Ceilings? {
        manualBlockCeiling.map { Ceilings(blockTokens: $0) }
    }

    private struct Payload: Codable {
        var plan: Plan
        var manualBlockCeiling: UInt64?
    }

    private func save() {
        let payload = Payload(plan: plan, manualBlockCeiling: manualBlockCeiling)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
