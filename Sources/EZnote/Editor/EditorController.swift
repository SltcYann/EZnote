import AppKit
import SwiftUI

/// Pilote l'éditeur : mise en forme depuis la barre d'outils, et EZifier (notes → leçon par Claude).
@MainActor
final class EditorController: NSObject, ObservableObject, NSTextViewDelegate, NSTextStorageDelegate {
    enum Phase: Equatable { case idle, reading, searching, writing }

    @Published private(set) var phase: Phase = .idle
    @Published var errorMessage: String?
    @Published var needsAPIKey = false

    weak var undoManager: UndoManager?
    private weak var textView: PageTextView?
    private var storage: NSTextStorage?
    private var task: Task<Void, Never>?

    var isWorking: Bool { phase != .idle }

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

    nonisolated func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        LessonStyle.normalizeSpacing(textStorage, around: editedRange)
    }

    /// Retour sur un paragraphe vide au bout d'un ajout de Claude : on sort du contour (comme pour une liste).
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
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
    }

    // MARK: EZifier

    func ezify() {
        if isWorking { task?.cancel(); return }
        guard let apiKey = Keychain.apiKey, !apiKey.isEmpty else { needsAPIKey = true; return }
        guard let textView, let storage else { return }
        let notes = NotesExporter.markdown(from: storage)
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Écris d'abord quelques notes, puis appuie sur EZifier."
            return
        }

        let original = NSAttributedString(attributedString: storage)
        textView.breakUndoCoalescing()
        textView.isEditable = false
        phase = .reading
        let webSearch = UserDefaults.standard.object(forKey: "webSearch") as? Bool ?? true

        task = Task { [weak self] in
            var markdown = ""
            var lastRender = ContinuousClock.now
            do {
                for try await event in ClaudeClient(apiKey: apiKey).lesson(from: notes, webSearch: webSearch) {
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
        replaceAll(with: LessonRenderer.render(markdown))
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
