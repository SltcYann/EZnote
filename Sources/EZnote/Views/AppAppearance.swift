import AppKit

/// Mode d'affichage choisi dans les Réglages : comme le système, clair ou sombre.
enum AppAppearance: String, CaseIterable {
    case system, light, dark

    static let defaultsKey = "appearance"

    var label: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    @MainActor
    static func apply(_ raw: String? = UserDefaults.standard.string(forKey: defaultsKey)) {
        switch AppAppearance(rawValue: raw ?? "") ?? .system {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
