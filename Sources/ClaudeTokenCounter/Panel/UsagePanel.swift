import AppKit
import SwiftUI
import CCUsageCore

struct UsagePanel: View {
    let snapshot: UsageSnapshot

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                sessionSection
                valueSection
                if !snapshot.unknownModels.isEmpty { unknownModelsNotice }
                footer
            }
            .padding(16)
            .frame(width: 330)
        }
    }

    // MARK: - Sessão

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("SESSÃO")

            if let block = snapshot.activeBlock {
                gauge(title: "Atual", gauge: block, detail: resetDetail(block))
            } else {
                Text("Nenhuma sessão ativa")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            gauge(title: "Semanal", gauge: snapshot.rollingWeek, detail: "")

            if let rate = snapshot.burnRatePerMinute {
                Text("\(Format.tokens(UInt64(rate)))/min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label("Estimativa calibrada pelo seu histórico", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func resetDetail(_ block: UsageSnapshot.Gauge) -> String {
        guard let resetsAt = block.resetsAt else { return "" }
        var text = "reseta \(Format.clockTime(resetsAt))"
        if let remaining = block.timeRemaining(at: snapshot.generatedAt) {
            text += " · em \(Format.duration(remaining))"
        }
        return text
    }

    /// A barra usa a fração saturada; o texto usa a bruta, para não esconder
    /// que o consumo passou do maior já observado.
    private func gauge(title: String, gauge g: UsageSnapshot.Gauge, detail: String) -> some View {
        let fraction = g.fraction
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(Format.percent(g.rawFraction))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(g.rawFraction > 1 ? .orange : .primary)
            }
            ProgressView(value: fraction)
                .tint(fraction >= 0.85 ? .red : (fraction >= 0.6 ? .orange : .accentColor))
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Valor

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("VALOR")
            HStack(alignment: .top, spacing: 0) {
                column("HOJE", snapshot.today)
                column("SEMANA", snapshot.week)
                column("MÊS", snapshot.month)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func column(_ title: String, _ totals: Totals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(Format.tokens(totals.tokens)).font(.callout.monospacedDigit())
            Text(Format.money(totals.money))
                .font(.callout.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rodapé

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var unknownModelsNotice: some View {
        Label("Sem preço conhecido: \(snapshot.unknownModels.sorted().joined(separator: ", "))",
              systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
