import AppKit
import SwiftUI
import CCUsageCore


/// Ícone de ajuda com a explicação longa atrás dele.
///
/// Tooltip em vez de popover porque `@State` não existe neste toolchain: é
/// macro do SwiftUI e o plugin só acompanha o Xcode. Não se perde nada — o
/// tooltip é o idioma que o macOS já usa para isto.
private struct HelpTip: View {
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.tertiary)
            .help(text)
    }
}

/// Uma linha de controle: rótulo à esquerda, ajuda à direita.
private struct ControlRow<Content: View>: View {
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 8)
            HelpTip(text: help)
        }
    }
}

/// Chip selecionável. `.button` porque a alternativa seria uma pilha de
/// checkboxes ocupando uma linha cada.
private struct Chip: View {
    let label: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle(label, isOn: Binding(get: { isOn }, set: { _ in toggle() }))
            .toggleStyle(.button)
            .controlSize(.small)
    }
}

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
                          ? "Sua conta indica \(detected.label)."
                          : "Detectado pela sua conta.",
                          systemImage: settings.planDisagreesWithDetection
                          ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(settings.planDisagreesWithDetection
                                         ? UsageColor.warning : .secondary)
                        .help(settings.planDisagreesWithDetection
                              ? "A detecção lê o plano do keychain do Claude Code. Sua "
                                + "seleção manual está sobrescrevendo — o que é o certo "
                                + "se você mudou de plano há pouco."
                              : "Lido do keychain do Claude Code.")
                } else {
                    Label("Não foi possível ler o plano — selecione manualmente.",
                          systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Números de uso") {
                ControlRow(help: "Ligado, o app lê o token de acesso que o Claude Code "
                           + "guarda no keychain e consulta a mesma API que ele consulta, "
                           + "a cada 5 minutos. O macOS pode pedir autorização na primeira "
                           + "leitura.\n\nDesligado, o app usa o número que o Claude Code "
                           + "deixou em cache — que só se move quando ele roda, e já foi "
                           + "medido 13 horas atrasado.") {
                    Toggle("Buscar ao vivo", isOn: $settings.liveUsageEnabled)
                }
                Text(settings.liveUsageEnabled
                     ? "Consulta a API a cada 5 minutos."
                     : "Usando o cache do Claude Code, que pode estar horas atrasado.")
                    .font(.caption)
                    .foregroundStyle(settings.liveUsageEnabled ? .secondary : UsageColor.warning)
            }

            Section("Alertas") {
                ControlRow(help: "Notifica ao passar de um limiar de consumo. O alerta "
                           + "só sai com a busca ao vivo ligada: sobre o cache, ele "
                           + "erraria nos dois sentidos — e o pior deles é o silêncio "
                           + "enquanto você estoura o teto.") {
                    Toggle("Avisar ao aproximar do teto",
                           isOn: $settings.alerts.thresholdsEnabled)
                }

                if settings.alerts.thresholdsEnabled {
                    LabeledContent("Limiares") {
                        HStack(spacing: 6) {
                            ForEach(AlertPreferences.offeredThresholds, id: \.self) { value in
                                Chip(label: "\(value)%",
                                     isOn: settings.alerts.thresholds.contains(value)) {
                                    toggleThreshold(value)
                                }
                            }
                        }
                    }
                    if settings.alerts.thresholds.isEmpty {
                        Label("Nenhum limiar selecionado — nada será avisado.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(UsageColor.warning)
                    }
                }

                ControlRow(help: "Avisa quando a janela reseta e a capacidade volta — é "
                           + "quando dá para retomar trabalho pesado. Não vira ruído de "
                           + "madrugada: parando de usar o Claude Code, a janela deixa de "
                           + "ser substituída por outra ativa e o aviso não acontece.") {
                    Toggle("Avisar quando a janela resetar",
                           isOn: $settings.alerts.resetEnabled)
                }

                if settings.alerts.anyEnabled {
                    LabeledContent("Janelas") {
                        HStack(spacing: 6) {
                            Chip(label: "5 horas",
                                 isOn: settings.alerts.windows.contains(.session)) {
                                toggleWindow(.session)
                            }
                            Chip(label: "semanal",
                                 isOn: settings.alerts.windows.contains(.weekly)) {
                                toggleWindow(.weekly)
                            }
                        }
                    }

                    // Alerta sobre cache defasada erraria nos dois sentidos, e o
                    // pior é o silêncio enquanto o usuário estoura. Em vez de
                    // notificar mal, a tela oferece a saída.
                    if !settings.liveUsageEnabled {
                        Label("Alertas precisam da busca ao vivo.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(UsageColor.warning)
                        Button("Ligar busca ao vivo") { settings.liveUsageEnabled = true }
                            .controlSize(.small)
                    }

                    // Uma chave ligada sobre permissão negada é uma chave que mente.
                    if alerts.isDenied {
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
                        .controlSize(.small)
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
                }
                ControlRow(help: "A Anthropic não publica os limites do plano, então o "
                           + "teto não é lido de lugar nenhum: é o maior consumo que o "
                           + "app já observou num bloco de 5h completo do seu histórico.") {
                    Text("Calibrado: \(Format.tokens(calibratedCeiling)) tokens")
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

    private func toggleThreshold(_ value: Int) {
        if settings.alerts.thresholds.contains(value) {
            settings.alerts.thresholds.remove(value)
        } else {
            settings.alerts.thresholds.insert(value)
        }
    }

    private func toggleWindow(_ window: CCUsageCore.Alert.Window) {
        if settings.alerts.windows.contains(window) {
            settings.alerts.windows.remove(window)
        } else {
            settings.alerts.windows.insert(window)
        }
    }
}
