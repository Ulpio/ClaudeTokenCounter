import AppKit
import SwiftUI
import CCUsageCore

struct UsagePanel: View {
    let snapshot: UsageSnapshot
    let plan: Plan

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

            gauge(title: "Atual",
                  gauge: snapshot.session,
                  detail: resetDetail(snapshot.session))

            if let weekly = snapshot.weekly {
                gauge(title: "Semanal", gauge: weekly, detail: resetDetail(weekly))
            } else {
                paceRow(snapshot.weeklyPace)
            }

            if let rate = snapshot.burnRatePerMinute {
                Text("\(Format.tokens(UInt64(rate)))/min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshot.session.isOfficial {
                Label("Números oficiais da sua conta", systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Label("Estimativa calibrada pelo seu histórico", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func resetDetail(_ gauge: UsageSnapshot.Gauge) -> String {
        guard let resetsAt = gauge.resetsAt else {
            return gauge.isOfficial ? "" : "nenhuma sessão ativa"
        }
        var text = "reseta \(Format.clockTime(resetsAt))"
        if let remaining = gauge.timeRemaining(at: snapshot.generatedAt) {
            text += " · em \(Format.duration(remaining))"
        }
        // A idade importa: o cache oficial só se move quando o Claude Code roda.
        if let age = gauge.age(at: snapshot.generatedAt), age > 120 {
            text += " · lido há \(Format.duration(age))"
        }
        return text
    }

    /// Sem barra, deliberadamente: barra implica um teto, e aqui não há teto a
    /// prometer — só a comparação com o ritmo habitual.
    private func paceRow(_ pace: Pace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Semanal").font(.callout)
                Spacer()
                if let multiple = pace.multiple {
                    Text(String(format: "%.1f×", multiple))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(multiple >= 2 ? UsageColor.warning : .primary)
                } else {
                    Text("—").font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(pace.multiple == nil
                 ? "\(Format.tokens(pace.tokens)) nos últimos 7 dias"
                 : "\(Format.tokens(pace.tokens)) · típico \(Format.tokens(pace.typical))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                    .foregroundStyle(g.rawFraction > 1 ? UsageColor.critical : .primary)
            }
            ProgressView(value: fraction)
                .tint(UsageColor.bar(fraction))
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
            returnRow
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// Quanto o valor equivalente de API do mês cobre a mensalidade. Some
    /// enquanto não há consumo: "0×" no dia 1 não informa nada.
    @ViewBuilder
    private var returnRow: some View {
        if let multiple = plan.returnMultiple(forMonthly: snapshot.month.money) {
            Divider()
            HStack(spacing: 4) {
                Text("\(plan.label) · \(Format.planPrice(plan))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // Herda o "+" do total parcial: um piso não pode ser
                // apresentado como número exato.
                Text(String(format: "%.1f×", multiple)
                     + (snapshot.month.money.isPartial ? "+" : ""))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(multiple >= 1 ? UsageColor.calm : .secondary)
                Text("de retorno")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
            SettingsLink {
                Label("Ajustes", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
