import Foundation

/// Decide o que notificar, a partir da sequência de snapshots.
///
/// Pura e determinística: mesma sequência de entradas, mesma saída. Não lê
/// relógio, não fala com o sistema de notificação, e por isso o comportamento
/// inteiro — inclusive rearme e anti-repetição — cabe em teste.
public struct AlertPolicy {
    /// Fixos por decisão de projeto: menos botão, e configurável só quando
    /// houver evidência de que alguém precisa de outro valor.
    public static let thresholds = [80, 95]

    /// O que já foi disparado numa instância de janela. A instância é
    /// identificada pelo `resetsAt`: mudou, é outra janela.
    private struct WindowState {
        let resetsAt: Date
        var firedThresholds: Set<Int>
    }

    private var states: [Alert.Window: WindowState] = [:]
    private var liveRequiredEmitted = false

    public init() {}

    /// Consome um snapshot e devolve o que emitir.
    ///
    /// Primeira condição que casar vence, de cima para baixo — mesmo padrão do
    /// `UsageSourcePolicy`.
    public mutating func evaluate(_ snapshot: UsageSnapshot,
                                  alertsEnabled: Bool,
                                  liveEnabled: Bool) -> [Alert] {
        guard alertsEnabled else { return [] }

        // Sem busca ao vivo o app lê o cache do Claude Code, que já foi medido
        // 13h25 defasado. Alertar sobre aquilo erra nos dois sentidos, e o pior
        // é o silêncio enquanto o usuário estoura. Então avisa uma vez que os
        // alertas dependem do ao vivo, e não afirma mais nada.
        guard liveEnabled else {
            defer { liveRequiredEmitted = true }
            return liveRequiredEmitted ? [] : [.liveRequired]
        }

        return Alert.Window.allCases.flatMap { window in
            evaluate(window: window, gauge: gauge(for: window, in: snapshot))
        }
    }

    private func gauge(for window: Alert.Window,
                       in snapshot: UsageSnapshot) -> UsageSnapshot.Gauge? {
        switch window {
        case .session: snapshot.session
        case .weekly: snapshot.weekly
        }
    }

    private mutating func evaluate(window: Alert.Window,
                                   gauge: UsageSnapshot.Gauge?) -> [Alert] {
        // A procedência é verificada **no medidor**, não no status do snapshot:
        // um snapshot `.live` pode conter medidor derivado, quando o payload
        // veio sem a janela de 5h. Checar o status deixaria passar alerta sobre
        // número estimado sob a etiqueta de ao vivo.
        guard let gauge, case .live = gauge.provenance, let resetsAt = gauge.resetsAt else {
            return []
        }

        let percent = gauge.fraction * 100
        guard let state = states[window], state.resetsAt == resetsAt else {
            return openWindow(window, resetsAt: resetsAt, at: percent)
        }

        // Só o limiar mais alto entre os recém-cruzados vira alerta; os menores
        // são marcados como resolvidos. Dois banners pelo mesmo salto é
        // exatamente a sensação de spam que esta feature evita.
        let crossed = Self.thresholds.filter { !state.firedThresholds.contains($0)
                                               && percent >= Double($0) }
        guard let highest = crossed.max() else { return [] }

        states[window]?.firedThresholds.formUnion(crossed)
        return [.threshold(window: window, percent: highest, resetsAt: resetsAt)]
    }

    /// Abre uma instância de janela, estabelecendo a linha de base.
    ///
    /// Nada dispara aqui: o app não observou o consumo chegar até onde está —
    /// ele começou a olhar agora. Marcar os limiares já ultrapassados como
    /// disparados é o que impede um alerta de afirmar cruzamento que ninguém viu.
    ///
    /// É também o que dispensa persistir estado: reiniciando no meio de uma
    /// janela, esta linha reconstrói o estado correto a partir do próprio dado.
    private mutating func openWindow(_ window: Alert.Window,
                                     resetsAt: Date,
                                     at percent: Double) -> [Alert] {
        let closing = states[window]
        states[window] = WindowState(
            resetsAt: resetsAt,
            firedThresholds: Set(Self.thresholds.filter { percent >= Double($0) }))

        // A janela anterior só merece aviso de reset se o usuário tinha
        // encostado no teto nela. São quatro ou cinco resets por dia.
        guard let closing, !closing.firedThresholds.isEmpty else { return [] }
        return [.windowReset(window: window)]
    }
}
