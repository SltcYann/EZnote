import AppKit
import UniformTypeIdentifiers

/// Images (photos du tableau, diapos, schémas) et formules.
extension EditorController {
    /// Insérer › Image… (on peut aussi glisser ou coller une image dans le texte).
    func insertImage() {
        guard let textView, !isWorking else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Photos du tableau, diapositives ou schémas"
        panel.prompt = "Insérer"
        guard panel.runModal() == .OK else { return }
        let pictures = NSMutableAttributedString()
        for url in panel.urls {
            guard let wrapper = try? FileWrapper(url: url) else { continue }
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            pictures.append(NSAttributedString(attachment: attachment))
            pictures.append(NSAttributedString(string: "\n", attributes: LessonStyle.attributes(.body)))
        }
        guard pictures.length > 0 else { return }
        let range = textView.selectedRange()
        let atLineStart = range.location == 0
            || (textView.string as NSString).character(at: range.location - 1) == 10
        if !atLineStart { pictures.insert(NSAttributedString(string: "\n", attributes: LessonStyle.attributes(.body)), at: 0) }
        textView.insertText(pictures, replacementRange: range)
    }

    /// Taper le « $ » qui ferme `$\frac{a}{b}$` remplace la formule par « a⁄b ».
    /// Seulement s'il y a du LaTeX dedans (une commande, un exposant, un indice) : « 5 $ et 6 $ » reste tel quel.
    func convertFormula(endingAt range: NSRange) -> Bool {
        guard let textView, range.length == 0 else { return false }
        let ns = textView.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
        let before = ns.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
        guard let open = before.lastIndex(of: "$") else { return false }
        let latex = String(before[before.index(after: open)...])
        guard !latex.isEmpty, latex.contains(where: { "\\^_".contains($0) }) else { return false }
        let start = paragraph.location + before[..<open].utf16.count
        let converted = MathText.convert(latex)
        // Après le refus de la frappe du « $ », pour ne pas modifier le texte pendant sa propre vérification.
        DispatchQueue.main.async {
            textView.insertText(converted, replacementRange: NSRange(location: start, length: range.location - start))
        }
        return true
    }
}

/// Export et impression du document.
extension EditorController {
    func export(_ format: Exporter.Format) {
        guard let storage else { return }
        Exporter.export(NSAttributedString(attributedString: storage), as: format,
                        name: textView?.window?.title ?? "EZnote", from: textView?.window)
    }

    func printDocument() {
        guard let storage else { return }
        Exporter.printDocument(NSAttributedString(attributedString: storage), from: textView?.window)
    }
}
