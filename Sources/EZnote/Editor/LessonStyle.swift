import AppKit

extension NSAttributedString.Key {
    /// Texte ajouté par Claude (précision, exemple…). Valeur : `ClaudeAddition`.
    static let ezAddition = NSAttributedString.Key("EZClaudeAddition")
}

/// Un ajout de Claude. Chaque bloc a sa propre instance : deux blocs voisins restent distincts.
final class ClaudeAddition: NSObject {
    let kind: String
    init(kind: String) { self.kind = kind }
}

/// Typographie et mise en page du document.
enum LessonStyle {
    enum Block: CaseIterable {
        case title, heading, subheading, body

        var font: NSFont {
            switch self {
            case .title: return .systemFont(ofSize: 30, weight: .bold)
            case .heading: return .systemFont(ofSize: 22, weight: .bold)
            case .subheading: return .systemFont(ofSize: 18, weight: .semibold)
            case .body: return .systemFont(ofSize: 15)
            }
        }

        var label: String {
            switch self {
            case .title: return "Titre"
            case .heading: return "Section"
            case .subheading: return "Sous-section"
            case .body: return "Texte"
            }
        }

        /// Le type d'un paragraphe se déduit de la taille de sa police.
        static func of(_ font: NSFont?) -> Block {
            let size = font?.pointSize ?? 15
            if size >= 26 { return .title }
            if size >= 20 { return .heading }
            if size >= 17 { return .subheading }
            return .body
        }

        /// Espace avant / après le paragraphe.
        var spacing: (before: CGFloat, after: CGFloat) {
            switch self {
            case .title: return (6, 14)
            case .heading: return (22, 8)
            case .subheading: return (14, 6)
            case .body: return (0, 10)
            }
        }
    }

    /// Marges intérieures du contour des ajouts de Claude.
    enum Box {
        static let top: CGFloat = 32       // place pour l'étiquette « Claude · Exemple »
        static let bottom: CGFloat = 16
        static let side: CGFloat = 20      // le contour déborde dans la marge du papier
        static let gap: CGFloat = 18       // espace entre le contour et le texte voisin
        static let extraBefore = top + gap - Block.body.spacing.after
        static let extraAfter = bottom + gap - Block.body.spacing.after
    }

    static var bodyFont: NSFont { Block.body.font }

    static func paragraph(_ block: Block) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = block == .body ? 1.28 : 1.08
        style.paragraphSpacingBefore = block.spacing.before
        style.paragraphSpacing = block.spacing.after
        return style
    }

    static func attributes(_ block: Block) -> [NSAttributedString.Key: Any] {
        [.font: block.font, .paragraphStyle: paragraph(block), .foregroundColor: NSColor.textColor]
    }

    // MARK: Listes

    /// Numérotation « 1. », « 2. »… (le format décimal seul n'a pas de point).
    static let numbered = NSTextList.MarkerFormat(rawValue: "{decimal}.")

    /// Marqueur de liste au format de TextEdit (« \t•\t »), que NSTextView prolonge tout seul à chaque retour.
    static func marker(_ list: NSTextList, number: Int) -> String {
        "\t" + list.marker(forItemNumber: number) + "\t"
    }

    static func applyList(_ list: NSTextList?, to style: NSMutableParagraphStyle) {
        if let list {
            style.textLists = [list]
            style.tabStops = [NSTextTab(textAlignment: .left, location: 8), NSTextTab(textAlignment: .left, location: 30)]
            style.headIndent = 30
            style.firstLineHeadIndent = 0
        } else {
            style.textLists = []
            style.tabStops = NSParagraphStyle.default.tabStops
            style.headIndent = 0
            style.firstLineHeadIndent = 0
        }
    }

    static let markerPattern = try! NSRegularExpression(pattern: "^\\t[^\\t\\n]{1,8}\\t")

    static func markerRange(in paragraph: String) -> NSRange? {
        let range = markerPattern.rangeOfFirstMatch(in: paragraph, range: NSRange(location: 0, length: (paragraph as NSString).length))
        return range.location == NSNotFound ? nil : range
    }

    // MARK: Espacement automatique

    /// Recalcule l'espace avant / après des paragraphes touchés par une modification (et de leurs voisins) :
    /// il dépend du type de paragraphe et de sa place dans un ajout de Claude (premier ou dernier paragraphe
    /// du contour). Ne fait rien si l'espacement est déjà juste.
    static func normalizeSpacing(_ storage: NSTextStorage, around range: NSRange) {
        let ns = storage.string as NSString
        let length = ns.length
        guard length > 0 else { return }
        var start = ns.paragraphRange(for: NSRange(location: min(range.location, length), length: 0)).location
        if start > 0 { start = ns.paragraphRange(for: NSRange(location: start - 1, length: 0)).location }
        var end = NSMaxRange(ns.paragraphRange(for: NSRange(location: min(NSMaxRange(range), length), length: 0)))
        if end < length { end = NSMaxRange(ns.paragraphRange(for: NSRange(location: end, length: 0))) }

        var location = start
        while location < end {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            defer { location = NSMaxRange(paragraph) }
            guard paragraph.length > 0 else { break }

            let addition = storage.attribute(.ezAddition, at: paragraph.location, effectiveRange: nil) as AnyObject?
            let previous = paragraph.location > 0
                ? storage.attribute(.ezAddition, at: paragraph.location - 1, effectiveRange: nil) as AnyObject? : nil
            let next = NSMaxRange(paragraph) < length
                ? storage.attribute(.ezAddition, at: NSMaxRange(paragraph), effectiveRange: nil) as AnyObject? : nil
            let isFirst = addition != nil && previous !== addition
            let isLast = addition != nil && next !== addition

            let current = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                ?? NSParagraphStyle.default
            let block = Block.of(storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont)
            let isList = !current.textLists.isEmpty
            var before = block.spacing.before, after = isList ? 4 : block.spacing.after
            if isFirst { before += Box.extraBefore }
            if isLast { after = block.spacing.after + Box.extraAfter }
            if current.paragraphSpacingBefore == before && current.paragraphSpacing == after { continue }

            let style = current.mutableCopy() as! NSMutableParagraphStyle
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
    }
}
