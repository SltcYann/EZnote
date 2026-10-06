import AppKit
import SwiftUI

/// Pilote l'éditeur d'une fenêtre. Ce fichier : état, délégués du texte et mise en forme.
/// Les autres fonctions sont dans les extensions `EditorController+…`.
@MainActor
final class EditorController: NSObject, ObservableObject, NSTextViewDelegate, NSTextStorageDelegate {
    enum Phase: Equatable { case idle, reading, searching, writing }
    enum Recording: Equatable { case off, preparing, on(since: Date) }
    /// Mise en forme à l'endroit du curseur, pour allumer les boutons de la barre d'outils.
    enum Format: Hashable { case bold, italic, underline, bullets, numbers }
    /// Fenêtres d'outils (une à la fois).
    enum Tool: String, Identifiable { case revision, summary, question; var id: String { rawValue } }

    @Published var phase: Phase = .idle
    @Published var recording: Recording = .off
    @Published var errorMessage: String?
    @Published var needsAPIKey = false
    @Published var formats: Set<Format> = []
    @Published var block: LessonStyle.Block = .body
    /// Qui rédige (étiquette des ajouts, capsule d'état) : « Claude » ou le modèle local.
    @Published var author = "Claude"
    @Published var tool: Tool?
    /// Passage sélectionné pour « Poser une question ».
    @Published var questionPassage = ""
    /// Lecture de l'audio du cours en cours.
    @Published var isPlaying = false

    weak var undoManager: UndoManager?
    weak var textView: PageTextView?
    weak var document: EZDocument?
    var storage: NSTextStorage?
    var task: Task<Void, Never>?
    /// Nom du fichier : indice sur la matière pour l'IA.
    var documentTitle: String?
    var fileURL: URL?

    // Enregistrement du cours
    let recorder = LectureRecorder()
    let player = AudioPlayer()
    /// Fin du texte transcrit définitif ; le texte provisoire (en gris) suit sur `volatileLength` caractères.
    var transcriptEnd = 0
    var volatileLength = 0
    var writingTranscript = false
    var audioID: String?
    /// Plan du cours, mis à jour par l'IA pendant l'enregistrement.
    @Published var outline: [String] = []
    @Published var showsOutline = true
    var transcriptStart = 0
    var outlineTask: Task<Void, Never>?
    /// Marque-pages posés pendant le cours, en attente de la phrase prononcée à ce moment-là.
    var pendingMarks: [(mark: LessonStyle.Mark, time: Double)] = []

    var isWorking: Bool { phase != .idle }
    var isRecording: Bool { recording != .off }

    var context: StudyContext { StudyContext(title: documentTitle, info: document?.info ?? DocumentInfo()) }

    func attach(textView: PageTextView, storage: NSTextStorage, document: EZDocument) {
        self.textView = textView
        self.storage = storage
        self.document = document
        textView.delegate = self
        storage.delegate = self
        textView.onOptionClick = { [weak self] index in self?.replayAudio(at: index) }
        storage.beginEditing()
        let all = NSRange(location: 0, length: storage.length)
        LessonStyle.normalizeSpacing(storage, around: all)
        LessonStyle.fitAttachments(storage, in: all)
        storage.endEditing()
        player.onChange = { [weak self] playing in self?.isPlaying = playing }
    }

    /// Le document a changé ailleurs que dans le texte (contexte, fiches) : à enregistrer.
    func markDirty() {
        guard let window = textView?.window else { return }
        NSDocumentController.shared.document(for: window)?.updateChangeCount(.changeDone)
    }

    func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if case AIError.needsAPIKey = error { needsAPIKey = true; return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Délégués

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textViewDidChangeSelection(_ notification: Notification) { refreshFormats() }
    func textDidChange(_ notification: Notification) { refreshFormats() }

    nonisolated func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        LessonStyle.normalizeSpacing(textStorage, around: editedRange)
        guard editedMask.contains(.editedCharacters) else { return }
        LessonStyle.fitAttachments(textStorage, in: editedRange)
        MainActor.assumeIsolated { userEdited(editedRange, delta: delta) }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        if text == "$", convertFormula(endingAt: range) { return false }
        return leaveAdditionOnReturn(textView, range: range, text: text)
    }

    /// Retour à la fin d'un titre : la ligne suivante repart en texte normal (comme dans Pages ou Word).
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let storage else { return false }
        let range = textView.selectedRange()
        let ns = storage.string as NSString
        let font = textView.typingAttributes[.font] as? NSFont
        guard range.length == 0, LessonStyle.Block.of(font) != .body else { return false }
        let paragraph = ns.paragraphRange(for: range)
        let contentEnd = NSMaxRange(paragraph) - (ns.substring(with: paragraph).hasSuffix("\n") ? 1 : 0)
        guard range.location == contentEnd else { return false }
        textView.insertNewline(nil)
        var body = LessonStyle.attributes(.body)
        if let addition = textView.typingAttributes[.ezAddition] { body[.ezAddition] = addition }
        textView.typingAttributes = body
        refreshFormats()
        return true
    }

    /// Retour sur un paragraphe vide au bout d'un ajout de l'IA : on sort du contour (comme pour une liste).
    private func leaveAdditionOnReturn(_ textView: NSTextView, range: NSRange, text: String?) -> Bool {
        guard text == "\n", range.length == 0, let storage else { return true }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: range)
        guard ns.substring(with: paragraph).trimmingCharacters(in: .newlines).isEmpty else { return true }
        let inside = paragraph.length > 0
            ? storage.attribute(.ezAddition, at: paragraph.location, effectiveRange: nil) != nil
            : textView.typingAttributes[.ezAddition] != nil
        guard inside else { return true }
        if paragraph.length > 0, textView.shouldChangeText(in: paragraph, replacementString: nil) {
            storage.removeAttribute(.ezAddition, range: paragraph)
            textView.didChangeText()
        }
        textView.typingAttributes.removeValue(forKey: .ezAddition)
        return false
    }

    /// Clic droit : réécouter le cours, poser une question, marque-pages.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        var items: [NSMenuItem] = []
        if let storage, charIndex < storage.length, storage.attribute(.ezAudio, at: charIndex, effectiveRange: nil) != nil {
            items.append(MenuAction.item("Réécouter à partir d'ici", symbol: "play.fill") { [weak self] in self?.replayAudio(at: charIndex) })
        }
        if view.selectedRange().length > 0 {
            items.append(MenuAction.item("Poser une question à \(AI.authorName)…", symbol: "questionmark.bubble") { [weak self] in
                self?.askAboutSelection()
            })
            // Liens entre cours : les autres cours qui parlent de la notion sélectionnée.
            let term = (view.string as NSString).substring(with: view.selectedRange()).trimmingCharacters(in: .whitespacesAndNewlines)
            if term.count >= 3, term.count <= 60 {
                let others = LibraryIndex.courses(mentioning: term, excluding: fileURL)
                let links = NSMenuItem(title: "« \(term.prefix(30)) » dans mes autres cours", action: nil, keyEquivalent: "")
                links.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
                let submenu = NSMenu()
                if others.isEmpty {
                    submenu.addItem(withTitle: "Aucun autre cours n'en parle", action: nil, keyEquivalent: "").isEnabled = false
                }
                for course in others.prefix(12) {
                    let label = course.subject.isEmpty ? course.title : "\(course.title) — \(course.subject)"
                    submenu.addItem(MenuAction.item(label, symbol: "doc.text") {
                        NSDocumentController.shared.openDocument(withContentsOf: course.url, display: true) { _, _, _ in }
                    })
                }
                links.submenu = submenu
                items.append(links)
            }
        }
        items.append(MenuAction.item("Marquer comme important", symbol: "star") { [weak self] in self?.insertMark(.important) })
        items.append(MenuAction.item("Marquer « pas compris »", symbol: "questionmark.circle") { [weak self] in self?.insertMark(.unclear) })
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        menu.insertItem(.separator(), at: items.count)
        return menu
    }

    // MARK: Boutons allumés

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

    /// Format › Police › Plus grand / Plus petit, d'un point.
    func changeSize(by delta: CGFloat) {
        guard let textView, let storage, !isWorking else { return }
        let fm = NSFontManager.shared
        let range = textView.selectedRange()
        func resized(_ font: NSFont) -> NSFont { fm.convert(font, toSize: max(8, font.pointSize + delta)) }
        if range.length == 0 {
            textView.typingAttributes[.font] = resized(textView.typingAttributes[.font] as? NSFont ?? LessonStyle.bodyFont)
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            storage.addAttribute(.font, value: resized(value as? NSFont ?? LessonStyle.bodyFont), range: run)
        }
        storage.endEditing()
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

    // MARK: Remplacement global (EZifier, enregistrement) avec annulation en un bloc

    /// Remplace tout le texte sans passer par l'annulation du texte.
    func replaceAll(with text: NSAttributedString) {
        guard let storage, let textView else { return }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
    }

    /// ⌘Z remet l'ancien texte, ⇧⌘Z le nouveau.
    func registerSwap(back old: NSAttributedString, current: NSAttributedString, name: String = "EZifier") {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.abandonRecording()
            controller.replaceAll(with: old)
            controller.registerSwap(back: current, current: old, name: name)
        }
        undoManager.setActionName(name)
    }
}

/// Élément de menu qui exécute une fermeture.
final class MenuAction: NSObject {
    private let action: () -> Void
    private init(_ action: @escaping () -> Void) { self.action = action }
    @objc private func run() { action() }

    static func item(_ title: String, symbol: String, action: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = target
        item.representedObject = target   // garde la cible en vie
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}
