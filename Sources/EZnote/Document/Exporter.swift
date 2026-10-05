import AppKit
import UniformTypeIdentifiers

/// Export PDF et Word, et impression, avec les encadrés des ajouts de l'IA.
@MainActor
enum Exporter {
    enum Format {
        case pdf, word

        var type: UTType { self == .pdf ? .pdf : UTType(filenameExtension: "docx") ?? .data }
        var label: String { self == .pdf ? "PDF" : "Word" }
    }

    /// Demande où enregistrer, puis exporte.
    static func export(_ text: NSAttributedString, as format: Format, name: String, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = name
        panel.directoryURL = SaveFolder.url
        panel.message = "Exporter en \(format.label)"
        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                switch format {
                case .pdf: try pdf(text, to: url)
                case .word: try word(text).write(to: url)
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: save) } else { save(panel.runModal()) }
    }

    static func printDocument(_ text: NSAttributedString, from window: NSWindow?) {
        let info = printInfo()
        let operation = NSPrintOperation(view: printView(text, info: info), printInfo: info)
        operation.jobTitle = window?.title ?? "EZnote"
        if let window { operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { operation.run() }
    }

    // MARK: PDF

    private static func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595, height: 842)   // A4
        info.topMargin = 56; info.bottomMargin = 56
        info.leftMargin = 50; info.rightMargin = 50
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.isHorizontallyCentered = false
        return info
    }

    static func pdf(_ text: NSAttributedString, to url: URL) throws {
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: printView(text, info: info), printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Le texte mis en page à la largeur d'une feuille A4, en clair, avec les encadrés.
    private static func printView(_ text: NSAttributedString, info: NSPrintInfo) -> NSView {
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let storage = NSTextStorage(attributedString: text)
        // Espace autour des encadrés et taille des images, comme dans l'éditeur.
        LessonStyle.normalizeSpacing(storage, around: NSRange(location: 0, length: storage.length))
        let layoutManager = ClaudeLayoutManager()
        storage.addLayoutManager(layoutManager)
        let inset = LessonStyle.Box.side + 4
        let container = NSTextContainer(size: NSSize(width: width - 2 * inset, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        LessonStyle.fitAttachments(storage, in: NSRange(location: 0, length: storage.length), width: width - 2 * inset)
        let view = PrintTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
        view.keptStorage = storage
        view.textContainerInset = NSSize(width: inset, height: 0)
        view.appearance = NSAppearance(named: .aqua)
        layoutManager.ensureLayout(for: container)
        let height = layoutManager.usedRect(for: container).height + 8
        view.setFrameSize(NSSize(width: width, height: max(height, 100)))
        return view
    }

    // MARK: Word

    /// Word ne connaît pas les contours : chaque ajout devient un paragraphe surligné d'orange,
    /// précédé de son étiquette « Claude · Exemple ».
    static func word(_ text: NSAttributedString) throws -> Data {
        let out = NSMutableAttributedString(attributedString: text)
        let all = NSRange(location: 0, length: out.length)
        var runs: [(NSRange, ClaudeAddition)] = []
        out.enumerateAttribute(.ezAddition, in: all) { value, range, _ in
            if let addition = value as? ClaudeAddition { runs.append((range, addition)) }
        }
        let tint = NSColor(srgb: 0xFBEAE3)
        for (range, addition) in runs.reversed() {
            out.addAttribute(.backgroundColor, value: tint, range: range)
            let label = NSAttributedString(string: "\(addition.author) · \(addition.kind)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor(srgb: 0xC2603F),
                .backgroundColor: tint,
                .paragraphStyle: LessonStyle.paragraph(.body),
            ])
            out.insert(label, at: range.location)
        }
        // Couleurs fixes : le noir du texte, pas la couleur du mode sombre.
        out.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            if (value as? NSColor) == NSColor.textColor || value == nil { out.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }
        return try out.data(from: NSRange(location: 0, length: out.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }
}

/// Vue d'impression : fond blanc et encadrés, sans la feuille arrondie de l'éditeur.
final class PrintTextView: NSTextView {
    var keptStorage: NSTextStorage?

    override func drawBackground(in rect: NSRect) {
        NSColor.white.setFill()
        rect.fill()
        (layoutManager as? ClaudeLayoutManager)?.drawClaudeBoxes(in: rect, origin: textContainerOrigin)
    }
}
