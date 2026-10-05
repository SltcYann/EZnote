import AppKit

/// Enregistrement du cours : la transcription s'écrit en direct à la fin du document, avec l'audio
/// pour réécouter chaque phrase, et des marque-pages « Important » / « Pas compris ».
extension EditorController {
    func toggleRecording() {
        switch recording {
        case .on: Task { await stopRecording() }
        case .preparing: return
        case .off:
            guard !isWorking, let storage, let textView else { return }
            recording = .preparing
            let id = UUID().uuidString
            Task {
                do {
                    recorder.onVolatile = { [weak self] in self?.showVolatile($0) }
                    recorder.onFinal = { [weak self] text, seconds in self?.appendFinal(text, at: seconds) }
                    try await recorder.start(vocabulary: vocabulary(), audioURL: AudioStore.url(for: id))
                    audioID = id
                    let original = NSAttributedString(attributedString: storage)
                    textView.breakUndoCoalescing()
                    textView.allowsUndo = false
                    beginTranscript()
                    registerTranscriptUndo(original: original)
                    recording = .on(since: .now)
                } catch {
                    recording = .off
                    report(error)
                }
            }
        }
    }

    /// Vocabulaire pour la dictée : mots du contexte et noms propres déjà présents dans le document.
    private func vocabulary() -> [String] {
        var words = context.vocabulary
        let text = storage?.string ?? ""
        let names = text.components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && $0.first?.isUppercase == true }
        var seen = Set(words.map { $0.lowercased() })
        for name in names where seen.insert(name.lowercased()).inserted { words.append(name) }
        return Array(words.prefix(150))
    }

    func stopRecording() async {
        guard case .on = recording else { return }
        await recorder.stop()
        writeTranscript { storage, _ in
            storage.deleteCharacters(in: NSRange(location: transcriptEnd, length: volatileLength))
            volatileLength = 0
        }
        recording = .off
        textView?.allowsUndo = true
    }

    /// ⌘Z après un enregistrement remet le document d'avant le cours (le texte transcrit est lu au moment
    /// de l'annulation, pour que ⇧⌘Z le remette).
    private func registerTranscriptUndo(original: NSAttributedString) {
        guard let undoManager, let storage else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.abandonRecording()
            let now = NSAttributedString(attributedString: storage)
            controller.replaceAll(with: original)
            controller.registerSwap(back: now, current: original, name: "Enregistrement du cours")
        }
        undoManager.setActionName("Enregistrement du cours")
    }

    /// Arrêt immédiat, sans attendre les derniers mots (annulation pendant l'enregistrement).
    func abandonRecording() {
        guard recording != .off else { return }
        recorder.onVolatile = nil
        recorder.onFinal = nil
        Task { await recorder.stop() }
        volatileLength = 0
        recording = .off
        textView?.allowsUndo = true
    }

    /// Titre « Cours enregistré · date » à la fin du document ; la transcription s'écrit dessous.
    private func beginTranscript() {
        writeTranscript { storage, _ in
            let heading = NSMutableAttributedString()
            if storage.length > 0 && !storage.string.hasSuffix("\n") {
                heading.append(NSAttributedString(string: "\n", attributes: LessonStyle.attributes(.body)))
            }
            let date = Date.now.formatted(date: .abbreviated, time: .shortened)
            heading.append(NSAttributedString(string: "Cours enregistré · \(date)\n", attributes: LessonStyle.attributes(.subheading)))
            storage.append(heading)
            transcriptEnd = storage.length
            volatileLength = 0
        }
    }

    private func showVolatile(_ text: String) {
        writeTranscript { storage, attributes in
            var volatile = attributes
            volatile[.foregroundColor] = NSColor.secondaryLabelColor
            let piece = NSAttributedString(string: spaced(text, in: storage), attributes: volatile)
            storage.replaceCharacters(in: NSRange(location: transcriptEnd, length: volatileLength), with: piece)
            volatileLength = piece.length
        }
    }

    private func appendFinal(_ text: String, at seconds: Double) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        writeTranscript { storage, attributes in
            storage.deleteCharacters(in: NSRange(location: transcriptEnd, length: volatileLength))
            volatileLength = 0
            guard !text.isEmpty else { return }
            var piece = spaced(text, in: storage)
            // Nouveau paragraphe toutes les ~600 lettres, à la fin d'une phrase.
            let ns = storage.string as NSString
            let paragraph = ns.paragraphRange(for: NSRange(location: max(0, transcriptEnd - 1), length: 0))
            if paragraph.length > 600, let last = text.last, ".?!".contains(last) { piece += "\n" }
            var phrase = attributes
            if let audioID, seconds.isFinite { phrase[.ezAudio] = "\(audioID)@\(seconds)" }
            let attributed = NSAttributedString(string: piece, attributes: phrase)
            storage.insert(attributed, at: transcriptEnd)
            transcriptEnd += attributed.length
        }
    }

    /// Une espace avant le nouveau texte, sauf en début de paragraphe.
    private func spaced(_ text: String, in storage: NSTextStorage) -> String {
        guard transcriptEnd > 0 else { return text }
        let previous = (storage.string as NSString).character(at: transcriptEnd - 1)
        return previous == 10 || previous == 32 ? text : " " + text
    }

    /// Modifie le texte de la transcription sans toucher à la sélection ni à l'annulation,
    /// et suit le bas du document si le curseur y est.
    func writeTranscript(_ edit: (NSTextStorage, [NSAttributedString.Key: Any]) -> Void) {
        guard let storage, let textView else { return }
        let following = textView.selectedRange().location >= storage.length - volatileLength
        var attributes = LessonStyle.attributes(.body)
        attributes[.ezTranscript] = true
        writingTranscript = true
        storage.beginEditing()
        edit(storage, attributes)
        storage.endEditing()
        writingTranscript = false
        if following { textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0)) }
    }

    /// Pendant l'enregistrement, ce que tu tapes avant la transcription la décale.
    func userEdited(_ range: NSRange, delta: Int) {
        guard case .on = recording, !writingTranscript, let storage else { return }
        if range.location < transcriptEnd { transcriptEnd = max(range.location, transcriptEnd + delta) }
        transcriptEnd = min(transcriptEnd, storage.length - volatileLength)
    }

    // MARK: Réécoute

    /// ⌥-clic ou clic droit sur une phrase transcrite : le cours reprend à cet endroit.
    func replayAudio(at index: Int) {
        guard let storage, index < storage.length,
              let value = storage.attribute(.ezAudio, at: index, effectiveRange: nil) as? String else { return }
        let parts = value.split(separator: "@")
        guard parts.count == 2, let seconds = Double(parts[1]) else { return }
        do { try player.play(id: String(parts[0]), from: seconds) }
        catch { errorMessage = "L'audio de ce cours n'est plus sur ce Mac." }
    }

    func stopAudio() { player.stop() }

    // MARK: Marque-pages

    /// Pendant le cours : au bout de la transcription. Sinon : au curseur.
    func insertMark(_ mark: LessonStyle.Mark) {
        guard let storage, let textView else { return }
        if case .on = recording {
            writeTranscript { storage, attributes in
                let chip = mark.attributed(base: attributes)
                let location = transcriptEnd
                let needsSpace = location > 0 && (storage.string as NSString).character(at: location - 1) != 32
                    && (storage.string as NSString).character(at: location - 1) != 10
                let piece = NSMutableAttributedString(string: needsSpace ? " " : "", attributes: attributes)
                piece.append(chip)
                storage.insert(piece, at: location)
                transcriptEnd += piece.length
            }
            return
        }
        guard !isWorking else { return }
        let range = textView.selectedRange()
        var base = textView.typingAttributes
        base.removeValue(forKey: .ezMark)
        let chip = mark.attributed(base: base)
        guard textView.shouldChangeText(in: NSRange(location: range.location, length: 0), replacementString: chip.string) else { return }
        storage.insert(chip, at: range.location)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + chip.length, length: 0))
        textView.typingAttributes = base
    }
}
