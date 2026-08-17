import SwiftUI
import CCUsageCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var form: SettingsFormState
    let loginItem: LoginItem
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
                Text("Usado só para o múltiplo de retorno na seção Valor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .onChange(of: form.useManualCeiling) { _, _ in form.commit(to: settings) }
    }
}
