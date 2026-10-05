import AppKit

extension NSAttributedString.Key {
    /// Texte ajouté par Claude (précision, exemple…). Valeur : `ClaudeAddition`.
    static let ezAddition = NSAttributedString.Key("EZClaudeAddition")
    /// Texte transcrit depuis l'audio du cours. Valeur : `true`.
    static let ezTranscript = NSAttributedString.Key("EZTranscript")
    /// Passage transcrit dont on garde l'audio. Valeur : « idAudio@secondes ».
    static let ezAudio = NSAttributedString.Key("EZAudio")
    /// Marque-page « Important » / « Pas compris ». Valeur : `LessonStyle.Mark.rawValue`.
    static let ezMark = NSAttributedString.Key("EZMark")
}

/// Un ajout de Claude. Chaque bloc a sa propre instance : deux blocs voisins restent distincts.
final class ClaudeAddition: NSObject {
    let kind: String
    /// Qui a écrit l'ajout : « Claude », ou le modèle local (« Qwen3.5 »).
    let author: String
    init(kind: String, author: String = "Claude") {
        self.kind = kind
        self.author = author
    }
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

        /// Taille d'aperçu dans la liste des styles.
        var previewSize: CGFloat {
            switch self {
            case .title: return 20
            case .heading: return 17
            case .subheading: return 15
            case .body: return 13
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

    /// `level` : 0 pour une liste, 1 ou 2 pour une sous-liste (décalée de 22 pt par niveau).
    static func applyList(_ list: NSTextList?, to style: NSMutableParagraphStyle, level: Int = 0) {
        if let list {
            let shift = CGFloat(level) * 22
            style.textLists = [list]
            style.tabStops = [NSTextTab(textAlignment: .left, location: 8 + shift), NSTextTab(textAlignment: .left, location: 30 + shift)]
            style.headIndent = 30 + shift
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

    // MARK: Marque-pages

    enum Mark: String {
        case important, unclear

        var label: String { self == .important ? "★ Important" : "? Pas compris" }

        /// Petite étiquette orange insérée dans le texte.
        func attributed(base: [NSAttributedString.Key: Any]) -> NSAttributedString {
            var attributes = base
            attributes[.font] = NSFont.systemFont(ofSize: 12.5, weight: .bold)
            attributes[.foregroundColor] = NSColor.claude
            attributes[.ezMark] = rawValue
            attributes.removeValue(forKey: .ezAudio)
            attributes.removeValue(forKey: .backgroundColor)
            // Fond arrondi dessiné par ClaudeLayoutManager ; espaces fines pour l'air autour du texte.
            let chip = NSMutableAttributedString(string: "\u{2009}\(label)\u{2009}", attributes: attributes)
            chip.append(NSAttributedString(string: " ", attributes: base))
            return chip
        }
    }

    // MARK: Images

    /// L'image d'origine (pleine résolution) d'une pièce jointe.
    static func image(of attachment: NSTextAttachment) -> NSImage? {
        if let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents, let image = NSImage(data: data) {
            return image
        }
        return attachment.image
    }

    /// Les photos collées ou glissées gardent leurs proportions mais ne dépassent pas la largeur de la colonne.
    static func fitAttachments(_ storage: NSTextStorage, in range: NSRange, width: CGFloat = PageTextView.column) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.attachment, in: range) { value, run, _ in
            guard let attachment = value as? NSTextAttachment, let image = image(of: attachment),
                  image.size.width > 0, image.size.height > 0 else { return }
            // Toujours recalculé : à la relecture d'un fichier, la taille enregistrée n'est pas fiable.
            let scale = min(1, width / image.size.width, 520 / image.size.height)
            let bounds = CGRect(x: 0, y: 0, width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            guard attachment.bounds != bounds || attachment.image?.size != bounds.size else { return }
            attachment.bounds = bounds
            // À la relecture d'un RTFD, l'image est dessinée par une cellule qui ignore `bounds` :
            // on lui donne une image déjà à la bonne taille.
            let shown = image.copy() as! NSImage
            shown.size = bounds.size
            attachment.image = shown
            (attachment.attachmentCell as? NSTextAttachmentCell)?.image = shown
            // Remettre l'attribut fait refaire la mise en page de l'image à sa nouvelle taille.
            storage.addAttribute(.attachment, value: attachment, range: run)
        }
    }
}
