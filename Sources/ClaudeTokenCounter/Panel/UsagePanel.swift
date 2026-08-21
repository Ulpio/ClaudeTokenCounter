import AppKit
import SwiftUI
import CCUsageCore

struct UsagePanel: View {
    let snapshot: UsageSnapshot
    let plan: Plan
    /// `true` quando a busca ao vivo está desligada — o único estado em que
    /// ligar é uma ação disponível.
    let canEnableLive: Bool
    let onEnableLive: () -> Void
    let state: PanelTabState

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: Bindable(state).tab) {
                    ForEach(PanelTab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Altura fixa ditada pela aba mais alta: trocar de aba nao pode
                // fazer o painel pular de tamanho. O custo e espaco vazio em
                // "Agora", que e a mais curta — previsibilidade vale mais que
                // densidade aqui.
                Group {
                    switch state.tab {
                    case .now:
                        NowTab(snapshot: snapshot, plan: plan,
                               canEnableLive: canEnableLive, onEnableLive: onEnableLive)
                    case .projects:
                        ProjectsTab(breakdown: snapshot.projects, state: state.projects)
                    }
                }
                .frame(minHeight: 260, alignment: .top)

                footer
            }
            .padding(16)
            .frame(width: 330)
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("panel.settings", systemImage: "gearshape")
            }
            // O app é `LSUIElement`: não tem Dock e nunca se ativa sozinho.
            // `SettingsLink` cria a janela, mas sem ativação ela nasce atrás de
            // todas as outras — medido: a janela existia com `onscreen=false`, e
            // ativar o app a trouxe para a frente sem tocar em mais nada. Sem
            // isto o clique parece não fazer coisa alguma.
            //
            // Vai no toque, não no `onAppear` da janela: a janela é criada uma
            // vez e reaproveitada, então `onAppear` não dispararia da segunda
            // vez em diante — que é justamente quando o usuário já está
            // confuso e clicando de novo.
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("panel.quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
