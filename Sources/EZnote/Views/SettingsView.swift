import SwiftUI

/// Réglages (⌘,) : connexion à Claude, études de l'élève, dossier des documents.
struct SettingsView: View {
    var body: some View {
        TabView {
            ClaudeSettings()
                .tabItem { Label("Claude", systemImage: "sparkles") }
            StudiesSettings()
                .tabItem { Label("Mes études", systemImage: "graduationcap") }
            DocumentsSettings()
                .tabItem { Label("Général", systemImage: "gearshape") }
        }
        .frame(width: 460)
    }
}

/// Le niveau et les études aident Claude à comprendre les notes et à deviner les mots mal transcrits.
private struct StudiesSettings: View {
    @AppStorage("studyLevel") private var level = ""
    @AppStorage("studyField") private var field = ""

    var body: some View {
        VStack(spacing: UY.space18) {
            UYSymbol(name: "graduationcap.fill", size: 26).foregroundStyle(UY.claude)
            Text("Claude s'en sert pour comprendre tes notes et deviner ce que le professeur a voulu dire quand la transcription est floue. La matière, il la déduit de tes notes et du nom du document.")
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GlassField(placeholder: "Niveau (ex. Terminale, L2, Master 1)", text: $level)
            GlassField(placeholder: "Études (ex. Droit, Médecine, Prépa MPSI)", text: $field)
        }
        .padding(UY.space32)
    }
}

private struct DocumentsSettings: View {
    @AppStorage(SaveFolder.defaultsKey) private var folder = ""
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        VStack(spacing: UY.space18) {
            Text("Apparence").font(UY.headline)
            Picker("", selection: $appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .onChange(of: appearance) { _, value in AppAppearance.apply(value) }

            Divider().padding(.horizontal, UY.space32)

            UYSymbol(name: "folder.fill", size: 26).foregroundStyle(UY.claude)
            Text("Dossier de sauvegarde par défaut")
                .font(UY.headline)
            Text(folder.isEmpty ? "Aucun : macOS propose le dernier dossier utilisé." : (folder as NSString).abbreviatingWithTildeInPath)
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: UY.space12) {
                Button("Choisir…") { _ = SaveFolder.choose() }
                    .buttonStyle(.glassProminent)
                    .tint(UY.claude)
                if !folder.isEmpty {
                    Button("Afficher") { NSWorkspace.shared.open(URL(fileURLWithPath: folder)) }
                        .buttonStyle(.glass)
                    Button("Retirer") { folder = "" }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
        .padding(UY.space32)
    }
}

private struct ClaudeSettings: View {
    @State private var key = Keychain.apiKey ?? ""
    @State private var saved = false
    @AppStorage("webSearch") private var webSearch = true
    @AppStorage(ClaudeConnection.defaultsKey) private var connection = ClaudeConnection.subscription.rawValue

    var body: some View {
        VStack(spacing: UY.space22) {
            Picker("", selection: $connection) {
                Text("Abonnement Claude").tag(ClaudeConnection.subscription.rawValue)
                Text("Clé API").tag(ClaudeConnection.apiKey.rawValue)
                Text("Modèle local").tag(ClaudeConnection.local.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 380)

            switch ClaudeConnection(rawValue: connection) ?? .subscription {
            case .subscription: subscription
            case .apiKey: apiKey
            case .local: LocalModelSettings()
            }

            Toggle("Autoriser Claude à chercher sur le web", isOn: $webSearch)
                .toggleStyle(.switch)
                .font(UY.subheadline)
                .disabled(connection == ClaudeConnection.local.rawValue)
        }
        .padding(UY.space32)
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
                .fixedSize(horizontal: false, vertical: true)
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

/// Modèle local (Ollama, LM Studio) : adresse du serveur et choix du modèle installé.
private struct LocalModelSettings: View {
    @AppStorage("localServer") private var server = LocalModelClient.defaultServer
    @AppStorage("localModel") private var model = ""
    @State private var models: [String] = []
    @State private var loading = false

    var body: some View {
        VStack(spacing: UY.space12) {
            Text("La leçon est rédigée sur ton Mac par un modèle comme Qwen, sans internet. Plus lent et moins précis que Claude, et sans recherche web : les ajouts s'appuient seulement sur ce que le modèle sait.")
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GlassField(placeholder: "Adresse (Ollama : \(LocalModelClient.defaultServer))", text: $server)
            HStack(spacing: UY.space12) {
                Picker("Modèle", selection: $model) {
                    if model.isEmpty { Text("Choisir…").tag("") }
                    ForEach(models.contains(model) || model.isEmpty ? models : [model] + models, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 240)
                Button { Task { await reload() } } label: {
                    UYSymbol(name: "arrow.clockwise", size: 13)
                }
                .buttonStyle(.glass)
                .help("Recharger la liste des modèles")
                .disabled(loading)
            }
            if models.isEmpty && !loading {
                Text("Aucun modèle trouvé. Lance Ollama (ou LM Studio) puis recharge.")
                    .font(UY.caption)
                    .foregroundStyle(UY.inkTertiary)
            }
        }
        .task { await reload() }
        .onChange(of: server) { _, _ in Task { await reload() } }
    }

    private func reload() async {
        loading = true
        models = await LocalModelClient.installedModels()
        if model.isEmpty, let first = models.first { model = first }
        loading = false
    }
}
