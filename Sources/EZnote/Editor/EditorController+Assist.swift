import AppKit

/// Outils d'IA autour de la leçon : question sur un passage, fiche de synthèse, fiches et quiz.
extension EditorController {
    /// La leçon en Markdown, telle que l'IA la lit.
    var lessonMarkdown: String { storage.map { NotesExporter.markdown(from: $0) } ?? "" }

    var hasContent: Bool { !(storage?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

    func askAboutSelection() {
        guard let textView, let storage else { return }
        let range = textView.selectedRange()
        // Sans sélection : le paragraphe du curseur.
        let passageRange = range.length > 0 ? range
            : (storage.string as NSString).paragraphRange(for: NSRange(location: min(range.location, storage.length), length: 0))
        questionPassage = (storage.string as NSString).substring(with: passageRange).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !questionPassage.isEmpty else { errorMessage = "Sélectionne le passage sur lequel porte ta question."; return }
        tool = .question
    }

    func openTool(_ tool: Tool) {
        guard hasContent else { errorMessage = "Écris ou EZifie d'abord une leçon."; return }
        self.tool = tool
    }

    /// Ajoute une réponse de l'IA dans un contour, juste après le paragraphe sélectionné (annulable).
    func insertAnswer(_ markdown: String, kind: String = "Explication") {
        guard let textView, let storage else { return }
        let ns = storage.string as NSString
        let selection = textView.selectedRange()
        let paragraph = ns.paragraphRange(for: NSRange(location: min(NSMaxRange(selection), storage.length), length: 0))
        var location = NSMaxRange(paragraph)
        let block = NSMutableAttributedString()
        if location == storage.length, storage.length > 0, !storage.string.hasSuffix("\n") {
            block.append(NSAttributedString(string: "\n", attributes: LessonStyle.attributes(.body)))
        }
        block.append(LessonRenderer.render(":::claude \(kind)\n\(markdown)\n:::", author: AI.authorName))
        if location < storage.length { block.append(NSAttributedString(string: "\n", attributes: LessonStyle.attributes(.body))) }
        location = min(location, storage.length)
        guard textView.shouldChangeText(in: NSRange(location: location, length: 0), replacementString: block.string) else { return }
        storage.insert(block, at: location)
        textView.didChangeText()
        textView.scrollRangeToVisible(NSRange(location: location, length: block.length))
    }

    /// Ajoute une fiche (synthèse…) à la fin du document (annulable).
    func appendToDocument(_ markdown: String) {
        guard let textView, let storage else { return }
        let block = NSMutableAttributedString()
        if storage.length > 0 { block.append(NSAttributedString(string: storage.string.hasSuffix("\n") ? "\n" : "\n\n", attributes: LessonStyle.attributes(.body))) }
        block.append(LessonRenderer.render(markdown, author: AI.authorName))
        let end = NSRange(location: storage.length, length: 0)
        guard textView.shouldChangeText(in: end, replacementString: block.string) else { return }
        storage.insert(block, at: end.location)
        textView.didChangeText()
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }
}
