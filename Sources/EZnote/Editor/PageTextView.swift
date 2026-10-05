import AppKit

/// Éditeur : un NSTextView (TextKit 1, le même moteur que TextEdit et Pages) posé sur une feuille de papier
/// arrondie, avec une colonne de texte centrée.
final class PageTextView: NSTextView {
    static let column: CGFloat = 680
    static let margin: CGFloat = 64
    static let top: CGFloat = 76

    var placeholder = "Commence à prendre tes notes…"

    /// ⌥-clic sur une phrase transcrite : réécouter le cours à cet endroit.
    var onOptionClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let onOptionClick {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            if index < (textStorage?.length ?? 0), textStorage?.attribute(.ezAudio, at: index, effectiveRange: nil) != nil {
                onOptionClick(index)
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Curseur : la barre de texte seulement sur la feuille, la flèche autour.

    override func resetCursorRects() {
        addCursorRect(visibleRect.intersection(paperRect), cursor: .iBeam)
    }

    override func mouseMoved(with event: NSEvent) {
        if paperRect.contains(convert(event.locationInWindow, from: nil)) { super.mouseMoved(with: event) }
        else { NSCursor.arrow.set() }
    }

    override func cursorUpdate(with event: NSEvent) {
        if paperRect.contains(convert(event.locationInWindow, from: nil)) { super.cursorUpdate(with: event) }
        else { NSCursor.arrow.set() }
    }

    private var paperRect: NSRect {
        let width = textContainer?.size.width ?? Self.column
        return NSRect(x: textContainerOrigin.x - Self.margin, y: 24,
                      width: width + 2 * Self.margin, height: max(0, bounds.height - 48))
    }

    override func drawBackground(in rect: NSRect) {
        let paper = NSBezierPath(roundedRect: paperRect, xRadius: 28, yRadius: 28)
        NSColor.ezPaper.setFill()
        paper.fill()
        NSColor.ezPaperStroke.setStroke()
        paper.lineWidth = 1
        paper.stroke()

        (layoutManager as? ClaudeLayoutManager)?.drawClaudeBoxes(in: rect, origin: textContainerOrigin)

        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: LessonStyle.bodyFont, .foregroundColor: NSColor.placeholderTextColor]
            placeholder.draw(at: textContainerOrigin, withAttributes: attrs)
        }
    }

    /// Le contour des ajouts déborde de la colonne et des lignes : on redessine toute la largeur,
    /// avec la marge du contour au-dessus et au-dessous.
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        let pad = LessonStyle.Box.top + LessonStyle.Box.bottom
        super.setNeedsDisplay(NSRect(x: 0, y: rect.minY - pad, width: bounds.width, height: rect.height + 2 * pad),
                              avoidAdditionalLayout: flag)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutColumn()
    }

    /// Colonne de 680 pt centrée ; elle ne rétrécit que si la fenêtre est trop étroite.
    func layoutColumn() {
        guard let container = textContainer else { return }
        let width = max(280, min(Self.column, bounds.width - 2 * (Self.margin + 24))).rounded()
        if container.size.width != width {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        let inset = NSSize(width: max(0, ((bounds.width - width) / 2).rounded()), height: Self.top)
        if textContainerInset != inset { textContainerInset = inset }
    }
}

/// La vue défilante garde l'éditeur au moins aussi haut que la fenêtre, pour que le papier la remplisse.
final class PageScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let textView = documentView as? NSTextView else { return }
        let height = contentSize.height
        if textView.minSize.height != height { textView.minSize = NSSize(width: 0, height: height) }
        if textView.frame.height < height {
            textView.setFrameSize(NSSize(width: contentSize.width, height: height))
        }
    }
}

/// Dessine le contour orange autour des ajouts de Claude, avec l'étiquette « Claude · Exemple ».
/// Appelé par la page (et non par la colonne de texte, qui couperait les côtés du contour).
final class ClaudeLayoutManager: NSLayoutManager {
    func drawClaudeBoxes(in rect: NSRect, origin: NSPoint) {
        drawMarkChips(in: rect, origin: origin)
        if let storage = textStorage, let container = textContainers.first, storage.length > 0 {
            let pad = LessonStyle.Box.top + LessonStyle.Box.bottom
            let area = NSRect(x: 0, y: rect.minY - origin.y - pad, width: container.size.width, height: rect.height + 2 * pad)
            let glyphsToShow = glyphRange(forBoundingRect: area, in: container)
            let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let all = NSRange(location: 0, length: storage.length)
            var drawn = Set<Int>()
            storage.enumerateAttribute(.ezAddition, in: visible) { value, range, _ in
                guard let addition = value as? ClaudeAddition else { return }
                // Le contour entoure tout l'ajout, même la partie hors de la zone à redessiner.
                var full = NSRange()
                _ = storage.attribute(.ezAddition, at: range.location, longestEffectiveRange: &full, in: all)
                guard drawn.insert(full.location).inserted else { return }
                drawBox(addition, characters: full, storage: storage, container: container, origin: origin)
            }
        }
    }

    /// Fond arrondi des marque-pages « ★ Important » / « ? Pas compris ».
    private func drawMarkChips(in rect: NSRect, origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first, storage.length > 0 else { return }
        let area = NSRect(x: 0, y: rect.minY - origin.y - 20, width: container.size.width, height: rect.height + 40)
        let characters = characterRange(forGlyphRange: glyphRange(forBoundingRect: area, in: container), actualGlyphRange: nil)
        storage.enumerateAttribute(.ezMark, in: characters) { value, range, _ in
            guard value != nil else { return }
            enumerateEnclosingRects(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil),
                                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { box, _ in
                let chip = box.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: 1)
                let path = NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2)
                NSColor.claude.withAlphaComponent(0.16).setFill()
                path.fill()
            }
        }
    }

    private func drawBox(_ addition: ClaudeAddition, characters: NSRange, storage: NSTextStorage,
                         container: NSTextContainer, origin: NSPoint) {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let first = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let last = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        let firstStyle = storage.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle
        let lastStyle = storage.attribute(.paragraphStyle, at: NSMaxRange(characters) - 1, effectiveRange: nil) as? NSParagraphStyle

        let top = first.minY + (firstStyle?.paragraphSpacingBefore ?? 0) - LessonStyle.Box.top
        // L'espace après un paragraphe n'est ajouté que s'il se termine par un retour à la ligne
        // (pas pour le dernier paragraphe du document).
        let endsWithNewline = (storage.string as NSString).character(at: NSMaxRange(characters) - 1) == 10
        let bottom = last.maxY - (endsWithNewline ? lastStyle?.paragraphSpacing ?? 0 : 0) + LessonStyle.Box.bottom
        let box = NSRect(x: origin.x - LessonStyle.Box.side, y: origin.y + top,
                         width: container.size.width + 2 * LessonStyle.Box.side, height: max(0, bottom - top))

        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 16, yRadius: 16)
        NSColor.claude.withAlphaComponent(0.07).setFill()
        path.fill()
        NSColor.claude.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        // Étiquette : ✦ Claude · Exemple
        let label = NSMutableAttributedString(string: addition.author, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: NSColor.claude,
        ])
        if !addition.kind.isEmpty {
            label.append(NSAttributedString(string: "  ·  " + addition.kind, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.claude.withAlphaComponent(0.8),
            ]))
        }
        let labelY = box.minY + 11
        var x = box.minX + LessonStyle.Box.side
        if let icon = Self.sparkle {
            icon.draw(in: NSRect(x: x, y: labelY + 1, width: 12, height: 12), from: .zero, operation: .sourceOver,
                      fraction: 1, respectFlipped: true, hints: nil)
            x += 17
        }
        label.draw(at: NSPoint(x: x, y: labelY - 1))
    }

    /// SF Symbol teinté à l'orange de Claude, rendu en bitmap pour passer aussi à l'impression et en PDF
    /// (le PDF ne sait pas teinter un symbole). Une version pour le mode clair, une pour le sombre.
    private static var sparkle: NSImage? {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? sparkleDark : sparkleLight
    }
    private static let sparkleLight = tinted(NSColor(srgb: 0xD97757))
    private static let sparkleDark = tinted(NSColor(srgb: 0xE8896B))

    private static func tinted(_ color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)) else { return nil }
        let scale: CGFloat = 4
        let size = symbol.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: size)
        symbol.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
