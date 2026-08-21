import Observation
import SwiftUI

enum PanelTab: CaseIterable {
    case now, projects
    // Historico chega em 1.5b.

    /// Cada caso carrega o proprio titulo para o seletor poder iterar
    /// `allCases`: acrescentar um caso passa a acrescentar a aba, em vez de
    /// compilar calado e sumir da barra ate alguem notar.
    var title: LocalizedStringKey {
        switch self {
        case .now: return "panel.tab.now"
        case .projects: return "panel.tab.projects"
        }
    }
}

/// A aba volta para `.now` a cada abertura do painel.
///
/// Nao se lembra a ultima de proposito: o painel existe para uma olhada de
/// relance, e reabrir em "Projetos" faria a olhada falhar — o usuario teria que
/// clicar para voltar ao que queria ver. Lembrar otimizaria o uso raro as custas
/// do comum.
@Observable
@MainActor
final class PanelTabState {
    var tab: PanelTab = .now
    let projects = ProjectsTabState()

    func reset() {
        tab = .now
        // O padrao da aba de projetos e dela: repetir `.week` aqui faria mudar
        // o padrao exigir lembrar dos dois lugares, e esquecer um nao quebra
        // nada visivel — o painel so abriria no periodo errado.
        projects.reset()
    }
}
