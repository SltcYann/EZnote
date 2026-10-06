import AppKit
import SwiftUI

/// Tokens du design system UY (Liquid Glass, en couleur), repris d'iSocial.
enum UY {
    // MARK: Couleurs
    static let surfaceBase = Color(light: 0xF2F2F7, dark: 0x0B0B10)
    static let ink = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkSecondary = Color(light: 0x515154, dark: 0xAEAEB2)
    static let inkTertiary = Color(light: 0x6E6E73, dark: 0x8E8E93)
    static let track = Color(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.2))

    static let green = Color(light: 0x1EA64A, dark: 0x30D158)
    static let focusRing = Color(light: 0x0A6CFF, dark: 0x5AC8FA)
    /// Orange de Claude : le bouton EZifier et le contour des ajouts de Claude.
    static let claude = Color(nsColor: .claude)
    /// Orange plus marqué pour une icône active posée sur le verre orangé de la barre d'outils.
    static let claudeStrong = Color(light: 0x9E3412, dark: 0xFFC2A8)
    static let danger = Color(light: 0xD70015, dark: 0xFF453A)

    // MARK: Espacements
    static let space8: CGFloat = 8, space12: CGFloat = 12, space14: CGFloat = 14
    static let space18: CGFloat = 18, space22: CGFloat = 22, space24: CGFloat = 24, space32: CGFloat = 32

    // MARK: Rayons
    static let radiusField: CGFloat = 14, radiusTile: CGFloat = 18
    static let radiusPanel: CGFloat = 28, radiusCapsule: CGFloat = 999

    // MARK: Typographie
    static let title3 = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17)
    static let subheadline = Font.system(size: 15)
    static let footnote = Font.system(size: 13)
    static let caption = Font.system(size: 12, weight: .medium)

    // MARK: Mouvement
    static func ease(_ d: Double = 0.4) -> Animation { .smooth(duration: d) }
    static let mood = Animation.easeInOut(duration: 0.9)
}

/// Ambiances du MeshBackground, toujours dans les couleurs de Claude :
/// orange doux au calme, plus intense quand Claude travaille.
enum Mood: Equatable {
    case calm
    case claude

    var colors: [Color] {
        switch self {
        case .calm: return [Color(hex: 0xD97757), Color(hex: 0xF0B07A), Color(hex: 0xE89070)]
        case .claude: return [Color(hex: 0xC8553D), Color(hex: 0xF2A65A), Color(hex: 0xD97757)]
        }
    }
}

extension NSColor {
    convenience init(srgb hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let claude = dynamic(light: NSColor(srgb: 0xD97757), dark: NSColor(srgb: 0xE8896B))
    /// Feuille de papier sous le texte.
    static let ezPaper = dynamic(light: .white, dark: NSColor(srgb: 0x1C1C22))
    static let ezPaperStroke = dynamic(light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.08))
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(srgb: hex)) }

    init(light: UInt32, dark: UInt32) {
        self.init(light: NSColor(srgb: light), dark: NSColor(srgb: dark))
    }

    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: .dynamic(light: light, dark: dark))
    }
}
