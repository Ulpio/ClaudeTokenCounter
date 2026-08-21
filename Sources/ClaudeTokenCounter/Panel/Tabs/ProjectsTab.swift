import CCUsageCore
import SwiftUI

/// Consumo por projeto no periodo escolhido.
///
/// A chave vazia — eventos anteriores ao campo `project` existir — **nao** entra
/// na lista: hoje ela seria 99% dela e enterraria os projetos reais por ate um
/// mes. Vira nota de rodape, que some sozinha quando o numero zerar.
///
/// Sem a nota, a soma por projeto nao bateria com o total da aba Agora e nada
/// explicaria a diferenca — exatamente o numero sem procedencia que este app
/// existe para nao produzir.
///
/// A linha ordena e mostra **dinheiro**, nao token: a pergunta que a aba
/// responde e qual projeto esta custando, e 10M de tokens baratos custam menos
/// que 2M dos caros — por tokens o ranking responderia outra pergunta. O total
/// em tokens continua a um hover de distancia.
struct ProjectsTab: View {
    let breakdown: UsageSnapshot.ProjectBreakdown
    let state: ProjectsTabState

    enum Period: CaseIterable {
        case today, week, month

        var title: LocalizedStringKey {
            switch self {
            case .today: return "panel.projects.period.today"
            case .week: return "panel.projects.period.week"
            case .month: return "panel.projects.period.month"
            }
        }
    }

    private var totals: [String: Totals] {
        switch state.period {
        case .today: return breakdown.today
        case .week: return breakdown.week
        case .month: return breakdown.month
        }
    }

    /// O que ficou sem projeto anotado, ou zero quando nao ha nada — assim o
    /// corpo decide com uma comparacao so, sem desembrulhar opcional duas vezes.
    private var unattributed: Totals { totals[""] ?? .zero }

    /// Ja ordenado e rotulado. Os rotulos saem de uma chamada so porque colisao
    /// so existe em conjunto — ver `ProjectLabel`.
    private var rows: [(raw: String, label: String, totals: Totals)] {
        let named = totals.filter { !$0.key.isEmpty }
        let labels = ProjectLabel.labels(for: Array(named.keys))
        return named
            .map { (raw: $0.key, label: labels[$0.key] ?? $0.key, totals: $0.value) }
            // Desempate por token e depois por chave crua porque `Dictionary`
            // nao tem ordem: dois projetos de mesmo custo trocariam de posicao
            // a cada redesenho, e a lista pareceria instavel sem motivo.
            .sorted { lhs, rhs in
                if lhs.totals.money.usd != rhs.totals.money.usd {
                    return lhs.totals.money.usd > rhs.totals.money.usd
                }
                if lhs.totals.tokens != rhs.totals.tokens {
                    return lhs.totals.tokens > rhs.totals.tokens
                }
                return lhs.raw < rhs.raw
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: Bindable(state).period) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rows.isEmpty, unattributed.tokens > 0 {
                // Frase unica, e nao "nenhum uso" mais a nota de rodape: as duas
                // juntas se contradizem ("nenhum" e "mais X" ao mesmo tempo, sem
                // nada de que ser "mais"), e este e o estado de todo mundo que
                // acabou de atualizar o app, ate voltar a usar o Claude Code.
                Text(String(format: String(localized: "panel.projects.unattributed.only.format"),
                            Format.money(unattributed.money)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if rows.isEmpty {
                Text("panel.projects.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.raw) { row in
                    HStack {
                        // truncationMode .middle porque rotulo com colisao vira
                        // "work/app": cortar o fim esconderia justamente o
                        // segmento que desambigua.
                        Text(row.label)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(tooltip(for: row))
                        Spacer()
                        Text(Format.money(row.totals.money))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !rows.isEmpty, unattributed.tokens > 0 {
                // Em dinheiro tambem: a nota reconcilia com as linhas acima, e
                // em outra unidade nao daria para somar de cabeca.
                Text(String(format: String(localized: "panel.projects.unattributed.format"),
                            Format.money(unattributed.money)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Caminho cru mais o total em tokens. O tooltip e onde o numero que saiu da
    /// linha continua alcancavel, sem disputar espaco com o custo.
    private func tooltip(for row: (raw: String, label: String, totals: Totals)) -> String {
        "\(row.raw) — \(Format.tokens(row.totals.tokens))"
    }
}
