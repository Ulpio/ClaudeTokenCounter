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

            // Só as que dizem algo. Uma linha "Fable 0%" permanente é ruído: a
            // janela existe no payload mas não informa nada.
            ForEach(snapshot.scopedWeekly.filter { $0.gauge.isActive || $0.gauge.rawFraction > 0 },
                    id: \.self) { scoped in
                gauge(title: scoped.modelName,
                      gauge: scoped.gauge,
                      detail: resetDetail(scoped.gauge))
            }

            if let rate = snapshot.burnRatePerMinute {
                Text("\(Format.tokens(UInt64(rate)))/min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            provenanceRow
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// De onde vieram os números. Substitui o rótulo binário anterior, que só
    /// sabia dizer "oficial" ou "estimado" — e chamava de oficial um cache que
    /// podia estar treze horas atrasado.
    private var provenanceRow: some View {
        let (text, icon, isWarning) = provenance
        return Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(isWarning
                             ? AnyShapeStyle(UsageColor.warning)
                             : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
    }

    private var provenance: (String, String, Bool) {
        switch snapshot.sourceStatus {
        case .live:
            return ("ao vivo", "bolt.horizontal.circle", false)
        case let .cached(age):
            // Uma hora é 20% de uma janela de 5h. Cache mais velho que isso já
            // pode estar descrevendo uma sessão que resetou — foi exatamente o
            // estado que mostrava 35% quando o valor real era 6%.
            return age < 3600
                ? ("cache do Claude Code · há \(Format.duration(age))", "clock", false)
                : ("cache defasada · há \(Format.duration(age))", "exclamationmark.triangle", true)
        case let .credentialExpired(age):
            return ("credencial expirada · rode o Claude Code (cache de há \(Format.duration(age)))",
                    "exclamationmark.triangle", true)
        case let .liveUnavailable(age):
            return ("sem conexão · cache de há \(Format.duration(age))", "wifi.slash", true)
        case .derivedOnly:
            return ("estimado do seu histórico", "info.circle", false)
        }
    }

    private func resetDetail(_ gauge: UsageSnapshot.Gauge) -> String {
        var text: String
        if let resetsAt = gauge.resetsAt {
            text = "reseta \(Format.clockTime(resetsAt))"
            if let remaining = gauge.timeRemaining(at: snapshot.generatedAt) {
                text += " · em \(Format.duration(remaining))"
            }
        } else {
            text = gauge.isOfficial ? "" : "nenhuma sessão ativa"
        }

        // Um snapshot pode ter procedências mistas: a semanal vem do relatório
        // oficial e a sessão cai no derivado quando o payload não traz a janela
        // de 5h — cache antigo com `five_hour: null`, que é o estado justamente
        // quando o cache está mais velho. A linha de procedência é uma só, do
        // snapshot inteiro, então sem esta marca o medidor derivado apareceria
        // sob "ao vivo", prometendo um frescor que ele não tem. O código
        // anterior estampava a idade por medidor e não tinha esse buraco; a
        // linha única é melhor, mas precisa disto para não mentir.
        if gauge.provenance == .derived, snapshot.sourceStatus != .derivedOnly {
            text = text.isEmpty ? "estimado do seu histórico" : text + " · estimado"
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
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
