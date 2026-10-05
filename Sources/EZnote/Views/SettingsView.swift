import SwiftUI

/// Réglages (⌘,) : abonnement Claude ou clé API, et recherche web.
struct SettingsView: View {
    @State private var key = Keychain.apiKey ?? ""
    @State private var saved = false
    @AppStorage("webSearch") private var webSearch = true
    @AppStorage(ClaudeConnection.defaultsKey) private var connection = ClaudeConnection.subscription.rawValue

    var body: some View {
        VStack(spacing: UY.space22) {
            VStack(spacing: UY.space8) {
                UYSymbol(name: "sparkles", size: 28)
                    .foregroundStyle(UY.claude)
                Text("EZifier").font(UY.title3)
            }

            Picker("", selection: $connection) {
                Text("Abonnement Claude").tag(ClaudeConnection.subscription.rawValue)
                Text("Clé API").tag(ClaudeConnection.apiKey.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            if connection == ClaudeConnection.subscription.rawValue {
                subscription
            } else {
                apiKey
            }

            Toggle("Autoriser Claude à chercher sur le web", isOn: $webSearch)
                .toggleStyle(.switch)
                .font(UY.subheadline)
        }
        .padding(UY.space32)
        .frame(width: 440)
        .animation(UY.ease(0.25), value: connection)
        .onChange(of: key) { _, _ in saved = false }
    }

    private var subscription: some View {
        VStack(spacing: UY.space8) {
            Label(ClaudeCodeClient.isAvailable ? "Claude Code est installé" : "Claude Code est introuvable",
                  systemImage: ClaudeCodeClient.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(UY.subheadline.weight(.semibold))
                .foregroundStyle(ClaudeCodeClient.isAvailable ? UY.green : UY.danger)
            Text("EZnote passe par Claude Code, connecté à ton compte claude.ai : l'EZification compte dans les limites de ton abonnement, sans clé API.")
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var apiKey: some View {
        VStack(spacing: UY.space12) {
            Text("EZnote utilise ta clé API Anthropic, facturée à l'usage.")
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
            GlassField(placeholder: "Clé API (sk-ant-…)", text: $key, secure: true)
            HStack(spacing: UY.space12) {
                Button(saved ? "Enregistrée" : "Enregistrer") {
                    Keychain.save(key)
                    withAnimation(UY.ease(0.25)) { saved = true }
                }
                .buttonStyle(.glassProminent)
                .tint(UY.claude)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Obtenir une clé", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }
}

/// Demandée au premier EZifier si aucune clé n'est enregistrée.
struct APIKeySheet: View {
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        VStack(spacing: UY.space18) {
            UYSymbol(name: "key.fill", size: 26).foregroundStyle(UY.claude)
            Text("Connecte Claude").font(UY.title3)
            Text("Colle ta clé API Anthropic. Elle reste sur ce Mac, dans le trousseau.")
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
            GlassField(placeholder: "Clé API (sk-ant-…)", text: $key, secure: true)
            HStack(spacing: UY.space12) {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("EZifier") {
                    Keychain.save(key)
                    dismiss()
                    onSaved()
                }
                .buttonStyle(.glassProminent)
                .tint(UY.claude)
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
            Link("Obtenir une clé", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                .font(UY.footnote)
        }
        .padding(UY.space32)
        .frame(width: 400)
    }
}
