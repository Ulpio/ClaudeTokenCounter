import Observation

@Observable
@MainActor
final class ProjectsTabState {
    /// Abre em semana e nao se lembra entre aberturas, pela mesma razao da aba:
    /// o painel e para olhar de relance. "Hoje" oscila demais para comparar
    /// projetos entre si, e "mes" hoje e quase todo nao atribuido.
    var period: ProjectsTab.Period = defaultPeriod

    /// Uma constante so, lida tanto na abertura quanto no reset.
    static let defaultPeriod: ProjectsTab.Period = .week

    func reset() { period = Self.defaultPeriod }
}
