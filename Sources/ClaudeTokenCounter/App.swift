import SwiftUI
import CCUsageCore

@main
struct ClaudeTokenCounterApp: App {
    /// Sem `@State`: no SDK do macOS 26 ele é uma macro do SwiftUI, e o plugin
    /// `SwiftUIMacros` só acompanha o Xcode — não o Command Line Tools.
    ///
    /// Não se perde nada aqui. `@State` governa posse e tempo de vida, e este
    /// app tem exatamente um store que vive enquanto o processo vive. O
    /// redesenho quando `snapshot` muda vem do `@Observable` (cujo plugin de
    /// macro *está* no CLT), que rastreia o acesso à propriedade dentro do
    /// `body` — independentemente de como a referência é guardada.
    @MainActor private static let settings = AppSettings()
    @MainActor private static let store = UsageStore(
        liveUsageEnabled: Self.settings.liveUsageEnabled)
    @MainActor private static let loginItem = LoginItem()
    @MainActor private static let form = SettingsFormState()
    @MainActor private static let alerts = AlertCoordinator(settings: Self.settings)

    init() {
        // A varredura inicial roda em task destacada, então a menu bar aparece
        // imediatamente e o painel preenche quando o disco termina de ser lido.
        Self.store.ceilingOverride = Self.settings.ceilingOverride
        // O gancho antes do start: a primeira reconstrução já estabelece a
        // linha de base da política, em vez de a política começar cega.
        Self.store.onSnapshot = { snapshot in Self.alerts.handle(snapshot) }
        Self.store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(snapshot: Self.store.snapshot, plan: Self.settings.plan)
                .onAppear { Self.store.panelDidOpen() }
        } label: {
            MenuBarLabel(snapshot: Self.store.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: Self.settings,
                         form: Self.form,
                         loginItem: Self.loginItem,
                         alerts: Self.alerts,
                         calibratedCeiling: Self.store.snapshot.calibratedBlockCeiling)
                // O store é a única fonte do denominador; as settings só
                // publicam a intenção do usuário e esta ponte a aplica.
                .onChange(of: Self.settings.ceilingOverride) { _, override in
                    Self.store.ceilingOverride = override
                }
                .onChange(of: Self.settings.liveUsageEnabled) { _, enabled in
                    Self.store.liveUsageEnabled = enabled
                }
                .onChange(of: Self.settings.alertsEnabled) { _, enabled in
                    Self.alerts.alertsEnabledChanged(to: enabled)
                }
        }
    }
}
