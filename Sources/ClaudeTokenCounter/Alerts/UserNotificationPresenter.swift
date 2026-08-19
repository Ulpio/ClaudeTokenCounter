import Foundation
import UserNotifications
import CCUsageCore

/// Entrega um alerta ao usuário. Protocolo para o coordenador ser exercitável
/// sem disparar notificação de verdade.
@MainActor
protocol AlertPresenting {
    func present(_ alert: Alert)
}

/// Traduz `Alert` — que carrega fato, não frase — em notificação do sistema.
///
/// Toda a redação em português vive aqui, junto do resto das strings de usuário,
/// e não no `CCUsageCore`. É o que vai permitir localizar o app sem localizar o
/// core junto.
@MainActor
struct UserNotificationPresenter: AlertPresenting {
    func present(_ alert: Alert) {
        let content = UNMutableNotificationContent()
        (content.title, content.body) = Self.copy(for: alert)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.identifier(for: alert),
                                  content: content,
                                  trigger: nil))
    }

    private static func copy(for alert: Alert) -> (title: String, body: String) {
        switch alert {
        case let .threshold(window, percent, resetsAt):
            switch window {
            case .session:
                ("\(percent)% da janela de 5h", sessionReset(resetsAt))
            case .weekly:
                ("\(percent)% da janela semanal", weeklyReset(resetsAt))
            }
        case let .windowReset(window):
            switch window {
            case .session: ("Janela de 5h resetou", "Capacidade cheia de novo.")
            case .weekly: ("Janela semanal resetou", "Capacidade cheia de novo.")
            }
        case .liveRequired:
            ("Alertas precisam da busca ao vivo",
             "Sem ela o app lê o cache do Claude Code, que pode estar horas "
             + "atrasado — e um alerta em cima disso erra nos dois sentidos. "
             + "Ligue em Ajustes → Números de uso.")
        }
    }

    private static func sessionReset(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        let remaining = max(0, resetsAt.timeIntervalSince(Date()))
        return "Reseta às \(Format.clockTime(resetsAt)), em \(Format.duration(remaining))."
    }

    /// A semanal reseta daqui a dias, então hora sozinha não localiza nada.
    private static func weeklyReset(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        return "Reseta \(resetsAt.formatted(date: .abbreviated, time: .shortened))."
    }

    /// Identificador estável em vez de aleatório: se o mesmo alerta for
    /// entregue duas vezes, o sistema substitui em vez de empilhar. A política
    /// já impede a repetição — isto é a rede embaixo dela.
    private static func identifier(for alert: Alert) -> String {
        switch alert {
        case let .threshold(window, percent, resetsAt):
            "threshold-\(window)-\(percent)-\(Int(resetsAt?.timeIntervalSince1970 ?? 0))"
        case let .windowReset(window):
            "reset-\(window)"
        case .liveRequired:
            "live-required"
        }
    }
}
