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
    @MainActor private static let store = UsageStore()

    init() {
        // A varredura inicial roda em task destacada, então a menu bar aparece
        // imediatamente e o painel preenche quando o disco termina de ser lido.
        Self.store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(snapshot: Self.store.snapshot)
        } label: {
            MenuBarLabel(snapshot: Self.store.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
