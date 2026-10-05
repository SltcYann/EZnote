import SwiftUI

/// Réglages (⌘,) : clé API et recherche web.
struct SettingsView: View {
    @State private var key = Keychain.apiKey ?? ""
    @State private var saved = false
    @AppStorage("webSearch") private var webSearch = true

    var body: some View {
        VStack(spacing: UY.space22) {
            VStack(spacing: UY.space8) {
                UYSymbol(name: "sparkles", size: 28)
                    .foregroundStyle(UY.claude)
                Text("EZifier").font(UY.title3)
                Text("EZnote utilise ta clé API Anthropic pour demander à Claude de rédiger tes leçons.")
                    .font(UY.footnote)
                    .foregroundStyle(UY.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: UY.space12) {
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

            Toggle("Autoriser Claude à chercher sur le web", isOn: $webSearch)
                .toggleStyle(.switch)
                .font(UY.subheadline)
        }
        .padding(UY.space32)
        .frame(width: 440)
        .onChange(of: key) { _, _ in saved = false }
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
