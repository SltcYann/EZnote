import AppKit
import SwiftUI

/// Pilote l'éditeur : mise en forme depuis la barre d'outils, et EZifier (notes → leçon par Claude).
@MainActor
final class EditorController: NSObject, ObservableObject, NSTextViewDelegate, NSTextStorageDelegate {
    enum Phase: Equatable { case idle, reading, searching, writing }
    enum Recording: Equatable { case off, preparing, on(since: Date) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recording: Recording = .off
    @Published var errorMessage: String?
    @Published var needsAPIKey = false

    /// Mise en forme à l'endroit du curseur, pour allumer les boutons de la barre d'outils.
    enum Format: Hashable { case bold, italic, underline, bullets, numbers }
    @Published private(set) var formats: Set<Format> = []
    @Published private(set) var block: LessonStyle.Block = .body

    weak var undoManager: UndoManager?
    private weak var textView: PageTextView?
    private var storage: NSTextStorage?
    private var task: Task<Void, Never>?
    /// Qui rédige la leçon en cours (étiquette des ajouts, capsule d'état).
    @Published private(set) var author = "Claude"

    var isWorking: Bool { phase != .idle }
    var isRecording: Bool { recording != .off }
    /// Nom du fichier : indice sur la matière pour Claude.
    var documentTitle: String?

    private let recorder = LectureRecorder()
    /// Fin du texte transcrit définitif ; le texte provisoire (en gris) suit sur `volatileLength` caractères.
    private var transcriptEnd = 0
    private var volatileLength = 0
    private var writingTranscript = false

    func attach(textView: PageTextView, storage: NSTextStorage) {
        self.textView = textView
        self.storage = storage
        textView.delegate = self
        storage.delegate = self
        storage.beginEditing()
        LessonStyle.normalizeSpacing(storage, around: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    // MARK: Délégués

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textViewDidChangeSelection(_ notification: Notification) { refreshFormats() }
    func textDidChange(_ notification: Notification) { refreshFormats() }

    func refreshFormats() {
        guard let textView, let storage else { return }
        let selection = textView.selectedRange()
        let attributes = selection.length == 0 || selection.location >= storage.length
            ? textView.typingAttributes : storage.attributes(at: selection.location, effectiveRange: nil)
        let font = attributes[.font] as? NSFont
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        var found: Set<Format> = []
        if traits.contains(.boldFontMask) { found.insert(.bold) }
        if traits.contains(.italicFontMask) { found.insert(.italic) }
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 { found.insert(.underline) }
        switch (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.first?.markerFormat {
        case .some(.disc): found.insert(.bullets)
        case .some(LessonStyle.numbered), .some(.decimal): found.insert(.numbers)
        default: break
        }
        let current = LessonStyle.Block.of(font)
        // Un titre est gras par nature : on n'allume pas « Gras » pour autant.
        if current != .body { found.remove(.bold) }
        if found != formats { formats = found }
        if current != block { block = current }
    }

    // MARK: Mise en forme

    func toggleBold() { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage, !isWorking else { return }
        let fm = NSFontManager.shared
        func convert(_ font: NSFont, add: Bool) -> NSFont {
            add ? fm.convert(font, toHaveTrait: trait) : fm.convert(font, toNotHaveTrait: trait)
        }
        let range = textView.selectedRange()
        if range.length == 0 {
            let font = textView.typingAttributes[.font] as? NSFont ?? LessonStyle.bodyFont
            textView.typingAttributes[.font] = convert(font, add: !fm.traits(of: font).contains(trait))
            refreshFormats()
            return
        }
        let firstFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? LessonStyle.bodyFont
        let add = !fm.traits(of: firstFont).contains(trait)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            storage.addAttribute(.font, value: convert(value as? NSFont ?? LessonStyle.bodyFont, add: add), range: run)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func toggleUnderline() {
        guard let textView, let storage, !isWorking else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            let on = (textView.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            textView.typingAttributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
            refreshFormats()
            return
        }
        let on = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        if on { storage.removeAttribute(.underlineStyle, range: range) }
        else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        textView.didChangeText()
    }

    /// Titre, section, sous-section ou texte : s'applique aux paragraphes sélectionnés.
    func setBlock(_ block: LessonStyle.Block) {
        guard let textView, let storage, !isWorking else { return }
        let ns = storage.string as NSString
        let range = ns.paragraphRange(for: textView.selectedRange())
        let fm = NSFontManager.shared
        func font(from old: NSFont?) -> NSFont {
            let italic = old.map { fm.traits(of: $0).contains(.italicFontMask) } ?? false
            return italic ? fm.convert(block.font, toHaveTrait: .italicFontMask) : block.font
        }
        if range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                storage.addAttribute(.font, value: font(from: value as? NSFont), range: run)
            }
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                let style = (value as? NSParagraphStyle ?? LessonStyle.paragraph(block)).mutableCopy() as! NSMutableParagraphStyle
                style.lineHeightMultiple = LessonStyle.paragraph(block).lineHeightMultiple
                storage.addAttribute(.paragraphStyle, value: style, range: run)
            }
            storage.endEditing()
            textView.didChangeText()
        }
        textView.typingAttributes[.font] = font(from: textView.typingAttributes[.font] as? NSFont)
        textView.typingAttributes[.paragraphStyle] = LessonStyle.paragraph(block)
        refreshFormats()
    }

    /// Liste à puces ou numérotée sur les paragraphes sélectionnés (un second appel l'enlève).
    func toggleList(_ format: NSTextList.MarkerFormat) {
        guard let textView, let storage, !isWorking else { return }
        let ns = storage.string as NSString
        let selection = textView.selectedRange()
        let range = ns.paragraphRange(for: selection)

        var paragraphs: [NSRange] = []
        var location = range.location
        repeat {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < NSMaxRange(range)

        func style(at paragraph: NSRange) -> NSParagraphStyle? {
            paragraph.length > 0 ? storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                : textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        let removing = paragraphs.allSatisfy { style(at: $0)?.textLists.first?.markerFormat == format }
        let list = NSTextList(markerFormat: format, options: 0)

        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paragraph))
            let attributes = text.length > 0 ? text.attributes(at: 0, effectiveRange: nil) : textView.typingAttributes
            if let marker = LessonStyle.markerRange(in: text.string) { text.deleteCharacters(in: marker) }
            let newStyle = (style(at: paragraph) ?? LessonStyle.paragraph(.body)).mutableCopy() as! NSMutableParagraphStyle
            LessonStyle.applyList(removing ? nil : list, to: newStyle)
            if !removing {
                text.insert(NSAttributedString(string: LessonStyle.marker(list, number: index + 1), attributes: attributes), at: 0)
            }
            text.addAttribute(.paragraphStyle, value: newStyle, range: NSRange(location: 0, length: text.length))
            if text.length == 0 { textView.typingAttributes[.paragraphStyle] = newStyle }
            result.append(text)
        }

        guard textView.shouldChangeText(in: range, replacementString: result.string) else { return }
        storage.replaceCharacters(in: range, with: result)
        textView.didChangeText()
        let end = range.location + result.length - (result.string.hasSuffix("\n") ? 1 : 0)
        textView.setSelectedRange(NSRange(location: max(range.location, end), length: 0))
        if result.length > 0, let style = result.attribute(.paragraphStyle, at: result.length - 1, effectiveRange: nil) {
            textView.typingAttributes[.paragraphStyle] = style
        }
        refreshFormats()
    }

    // MARK: EZifier

    func ezify() {
        if isWorking { task?.cancel(); return }
        guard !isRecording else { errorMessage = "Arrête d'abord l'enregistrement du cours."; return }
        let connection = ClaudeConnection.current
        let apiKey = Keychain.apiKey ?? ""
        if connection == .apiKey && apiKey.isEmpty { needsAPIKey = true; return }
        guard let textView, let storage else { return }
        let notes = NotesExporter.markdown(from: storage)
        let context = LessonPrompt.Context(title: documentTitle)
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Écris d'abord quelques notes, puis appuie sur EZifier."
            return
        }

        let original = NSAttributedString(attributedString: storage)
        author = connection == .local ? LocalModelClient.displayName : "Claude"
        textView.breakUndoCoalescing()
        textView.isEditable = false
        phase = .reading
        let webSearch = UserDefaults.standard.object(forKey: "webSearch") as? Bool ?? true

        task = Task { [weak self] in
            var markdown = ""
            var lastRender = ContinuousClock.now
            do {
                let events: AsyncThrowingStream<ClaudeClient.Event, Error>
                switch connection {
                case .subscription: events = ClaudeCodeClient().lesson(from: notes, context: context, webSearch: webSearch)
                case .apiKey: events = ClaudeClient(apiKey: apiKey).lesson(from: notes, context: context, webSearch: webSearch)
                case .local: events = LocalModelClient().lesson(from: notes, context: context)
                }
                for try await event in events {
                    guard let self else { return }
                    switch event {
                    case .searching:
                        self.phase = .searching
                    case .restart:
                        markdown = ""
                    case .text(let delta):
                        markdown += delta
                        self.phase = .writing
                        // Affichage en direct, ~15 fois par seconde : la leçon s'écrit sous les yeux.
                        if ContinuousClock.now - lastRender > .milliseconds(66) {
                            self.show(markdown)
                            lastRender = .now
                        }
                    }
                }
                guard let self else { return }
                guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeError.empty }
                self.show(markdown)
                self.finish(original: original)
            } catch {
                guard let self else { return }
                self.replaceAll(with: original)
                self.end()
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func show(_ markdown: String) {
        replaceAll(with: LessonRenderer.render(markdown, author: author))
        textView?.scrollRangeToVisible(NSRange(location: storage?.length ?? 0, length: 0))
    }

    /// Remplace tout le texte sans passer par l'annulation (l'EZification entière s'annule en une fois).
    private func replaceAll(with text: NSAttributedString) {
        guard let storage, let textView else { return }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
    }

    private func finish(original: NSAttributedString) {
        guard let storage else { return }
        registerSwap(back: original, current: NSAttributedString(attributedString: storage))
        end()
        textView?.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func end() {
        task = nil
        phase = .idle
        textView?.isEditable = true
        textView?.typingAttributes = LessonStyle.attributes(.body)
        if let textView { textView.window?.makeFirstResponder(textView) }
    }

    // MARK: Enregistrement du cours

    func toggleRecording() {
        switch recording {
        case .on: Task { await stopRecording() }
        case .preparing: return
        case .off:
            guard !isWorking, let storage, let textView else { return }
            recording = .preparing
            Task {
                do {
                    recorder.onVolatile = { [weak self] in self?.showVolatile($0) }
                    recorder.onFinal = { [weak self] in self?.appendFinal($0) }
                    try await recorder.start()
                    let original = NSAttributedString(attributedString: storage)
                    textView.breakUndoCoalescing()
                    textView.allowsUndo = false
                    beginTranscript()
                    registerTranscriptUndo(original: original)
                    recording = .on(since: .now)
                } catch {
                    recording = .off
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func stopRecording() async {
        guard case .on = recording else { return }
        await recorder.stop()
        writeTranscript { storage, _ in
            storage.deleteCharacters(in: NSRange(location: transcriptEnd, length: volatileLength))
            volatileLength = 0
        }
        recording = .off
        textView?.allowsUndo = true
    }

    /// Arrêt immédiat, sans attendre les derniers mots (annulation pendant l'enregistrement).
    private func abandonRecording() {
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

    private func appendFinal(_ text: String) {
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
            let attributed = NSAttributedString(string: piece, attributes: attributes)
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
    private func writeTranscript(_ edit: (NSTextStorage, [NSAttributedString.Key: Any]) -> Void) {
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

    /// ⌘Z après un enregistrement remet le document d'avant le cours.
    private func registerTranscriptUndo(original: NSAttributedString) {
        guard let undoManager, let storage else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.abandonRecording()
            let now = NSAttributedString(attributedString: storage)
            controller.replaceAll(with: original)
            controller.registerSwap(back: now, current: original)
        }
        undoManager.setActionName("Enregistrement du cours")
    }

    /// ⌘Z remet les notes, ⇧⌘Z remet la leçon.
    private func registerSwap(back old: NSAttributedString, current: NSAttributedString) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.replaceAll(with: old)
            controller.registerSwap(back: current, current: old)
        }
        undoManager.setActionName("EZifier")
    }
}
