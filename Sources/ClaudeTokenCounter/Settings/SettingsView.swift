import AppKit
import SwiftUI
import CCUsageCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var form: SettingsFormState
    let loginItem: LoginItem
    let alerts: AlertCoordinator
    /// Teto que a calibração automática encontrou — mostrado como referência
    /// para o campo manual não ser preenchido no escuro.
    let calibratedCeiling: UInt64

    var body: some View {
        Form {
            Section("Plano") {
                Picker("Assinatura", selection: $settings.plan) {
                    ForEach(Plan.allCases, id: \.self) { plan in
                        Text("\(plan.label) — \(Format.planPrice(plan))").tag(plan)
                    }
                }
                .pickerStyle(.inline)
                if let detected = settings.detectedPlan {
                    Label(settings.planDisagreesWithDetection
                          ? "Sua conta indica \(detected.label) — seleção manual está sobrescrevendo."
                          : "Detectado automaticamente pela sua conta.",
                          systemImage: settings.planDisagreesWithDetection
                          ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(settings.planDisagreesWithDetection
                                         ? UsageColor.warning : .secondary)
                } else {
                    Text("Não foi possível ler o plano da sua conta — selecione manualmente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Usado só para o múltiplo de retorno na seção Valor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Números de uso") {
                Toggle("Buscar ao vivo", isOn: $settings.liveUsageEnabled)
                Text(settings.liveUsageEnabled
                     ? "O app lê o token de acesso que o Claude Code guarda no keychain "
                       + "e consulta a API da Anthropic a cada 5 minutos. O macOS pode "
                       + "pedir autorização na primeira leitura."
                     : "Desligado, o app usa o número que o Claude Code deixou em cache — "
                       + "que só se atualiza quando ele roda, e pode estar horas atrasado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Alertas") {
                Toggle("Avisar ao aproximar do teto", isOn: $settings.alertsEnabled)
                Text("Notifica ao passar de 80% e de 95% da janela de 5h e da semanal, "
                     + "e avisa quando a janela reseta — só se você tiver encostado no teto.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Alerta sobre cache defasada erraria nos dois sentidos, e o
                // pior deles é o silêncio enquanto o usuário estoura. Então em
                // vez de notificar mal, a tela oferece a saída.
                if settings.alertsEnabled && !settings.liveUsageEnabled {
                    Label("Alertas precisam da busca ao vivo — sem ela o número pode "
                          + "estar horas atrasado.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(UsageColor.warning)
                    Button("Ligar busca ao vivo") { settings.liveUsageEnabled = true }
                }

                // Uma chave ligada sobre permissão negada é uma chave que mente.
                if settings.alertsEnabled && alerts.isDenied {
                    Label("Notificações negadas nos Ajustes do Sistema.",
                          systemImage: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(UsageColor.critical)
                    Button("Abrir Ajustes do Sistema") {
                        guard let url = URL(string:
                            "x-apple.systempreferences:com.apple.preference.notifications")
                        else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("Teto do bloco de 5h") {
                Picker("", selection: $form.useManualCeiling) {
                    Text("Calibrar pelo histórico").tag(false)
                    Text("Definir manualmente").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if form.useManualCeiling {
                    TextField("Tokens", text: $form.ceilingDraft)
                        .onSubmit { form.commit(to: settings) }
                    Text("Calibrado automaticamente: \(Format.tokens(calibratedCeiling)) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A Anthropic não publica os limites do plano, então o teto "
                         + "é o maior consumo já observado em um bloco completo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sistema") {
                Toggle("Abrir no login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }))
                if let explanation = loginItem.explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(UsageColor.critical)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear {
            loginItem.refresh()
            form.load(from: settings)
            Task { await alerts.refreshAuthorization() }
        }
        .onChange(of: form.useManualCeiling) { _, _ in form.commit(to: settings) }
    }
}
