import SwiftUI
import CCUsageCore

// Funções livres porque saíram do shell do painel: `UsagePanel` deixou de ser
// dono de título de seção e coluna de totais quando o painel virou abas. Hoje só
// `NowTab` chama; a aba de histórico de 1.5b deve reusar os mesmos, e virar
// método de uma view específica obrigaria a outra a depender dela só para isto.

@ViewBuilder
func sectionTitle(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
}

@ViewBuilder
func column(_ title: LocalizedStringKey, _ totals: Totals) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption2).foregroundStyle(.secondary)
        Text(Format.tokens(totals.tokens)).font(.callout.monospacedDigit())
        Text(Format.money(totals.money))
            .font(.callout.weight(.medium).monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
