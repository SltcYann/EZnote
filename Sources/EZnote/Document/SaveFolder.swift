import AppKit

/// Dossier proposé par défaut quand on enregistre un nouveau document.
enum SaveFolder {
    static let defaultsKey = "saveFolder"

    static var url: URL? {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// La fenêtre « Enregistrer » de macOS s'ouvre sur le dernier dossier utilisé (`NSNavLastRootDirectory`) :
    /// on le remet sur le dossier choisi à chaque nouvelle fenêtre.
    static func apply() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set((url.path as NSString).abbreviatingWithTildeInPath, forKey: "NSNavLastRootDirectory")
    }

    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier où EZnote propose d'enregistrer tes documents"
        panel.directoryURL = url
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        UserDefaults.standard.set(chosen.path, forKey: defaultsKey)
        apply()
        return chosen
    }
}
