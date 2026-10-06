import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ezNote = UTType(exportedAs: "local.eznote.note")
}

struct NoteSnapshot {
    var text: NSAttributedString
    var info: DocumentInfo
}

/// Un document EZnote. Le texte vit dans un `NSTextStorage` partagé avec l'éditeur :
/// aucune copie à chaque frappe, seulement à l'enregistrement.
/// `@unchecked Sendable` : le texte n'est modifié que sur le fil principal ; l'enregistrement travaille sur
/// une copie (`snapshot`).
final class EZDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.ezNote, .flatRTFD, .rtf, .plainText] }
    static var writableContentTypes: [UTType] { [.ezNote, .rtf] }

    let storage: NSTextStorage
    @Published var info = DocumentInfo()

    init() {
        storage = NSTextStorage(string: "", attributes: LessonStyle.attributes(.body))
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        let (text, info) = try NoteFile.read(data, type: configuration.contentType)
        storage = NSTextStorage(attributedString: text)
        self.info = info
    }

    func snapshot(contentType: UTType) throws -> NoteSnapshot {
        NoteSnapshot(text: NSAttributedString(attributedString: storage), info: info)
    }

    func fileWrapper(snapshot: NoteSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try NoteFile.write(snapshot, type: configuration.contentType))
    }
}

/// Format `.eznote` : JSON avec le texte en RTFD (qui garde les images), les passages marqués
/// (ajouts de l'IA, transcription, audio, marque-pages) que le RTF ne sait pas garder, et les infos du cours.
enum NoteFile {
    struct Payload: Codable {
        var version = 2
        var rtfd: Data?
        var rtf: Data?          // version 1
        var additions: [Span] = []
        var transcripts: [Span]?
        var audio: [Span]?
        var marks: [Span]?
        /// Passages en police système (San Francisco), que le RTF remplace par Helvetica.
        var systemFonts: [Span]?
        var info: DocumentInfo?
        /// Texte brut, pour la recherche de la bibliothèque sans tout décoder.
        var plainText: String?
    }

    struct Span: Codable {
        var location = 0
        var length = 0
        var kind: String
        var author: String?
    }

    static func read(_ data: Data, type: UTType) throws -> (NSAttributedString, DocumentInfo) {
        let text: NSMutableAttributedString
        var info = DocumentInfo()
        if type.conforms(to: .ezNote) {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            if let rtfd = payload.rtfd, let decoded = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
                text = NSMutableAttributedString(attributedString: decoded)
            } else {
                text = try rtf(payload.rtf ?? Data())
            }
            restoreListMarkers(text)
            func apply(_ spans: [Span]?, key: NSAttributedString.Key, _ value: (Span) -> Any) {
                for span in spans ?? [] where span.location >= 0 && span.location + span.length <= text.length {
                    text.addAttribute(key, value: value(span), range: NSRange(location: span.location, length: span.length))
                }
            }
            apply(payload.transcripts, key: .ezTranscript) { _ in true }
            apply(payload.audio, key: .ezAudio) { $0.kind }
            apply(payload.marks, key: .ezMark) { $0.kind }
            apply(payload.additions, key: .ezAddition) { ClaudeAddition(kind: $0.kind, author: $0.author ?? "Claude") }
            apply(payload.systemFonts, key: .font) { systemFont($0.kind) }
            info = payload.info ?? DocumentInfo()
        } else if type.conforms(to: .flatRTFD), let decoded = NSAttributedString(rtfd: data, documentAttributes: nil) {
            text = NSMutableAttributedString(attributedString: decoded)
            restoreListMarkers(text)
        } else if type.conforms(to: .rtf) {
            text = try rtf(data)
            restoreListMarkers(text)
        } else {
            text = NSMutableAttributedString(string: String(decoding: data, as: UTF8.self), attributes: LessonStyle.attributes(.body))
        }
        // La couleur du texte n'est pas enregistrée : on remet la couleur système, qui suit le mode sombre.
        // Le RTF ajoute aussi une couleur de soulignement noire, invisible en mode sombre : on l'enlève.
        let all = NSRange(location: 0, length: text.length)
        text.removeAttribute(.underlineColor, range: all)
        text.removeAttribute(.strikethroughColor, range: all)
        text.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NSColor.textColor, range: range) }
        }
        return (text, info)
    }

    static func write(_ snapshot: NoteSnapshot, type: UTType) throws -> Data {
        let text = NSMutableAttributedString(attributedString: snapshot.text)
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            if (value as? NSColor) == NSColor.textColor { text.removeAttribute(.foregroundColor, range: range) }
        }
        guard type.conforms(to: .ezNote) else {
            return try text.data(from: all, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        }

        func spans(_ key: NSAttributedString.Key, _ describe: (Any) -> Span?) -> [Span] {
            var result: [Span] = []
            text.enumerateAttribute(key, in: all) { value, range, _ in
                guard let value, var span = describe(value) else { return }
                span.location = range.location
                span.length = range.length
                result.append(span)
            }
            return result
        }
        compressImages(text)
        var payload = Payload(rtfd: text.rtfd(from: all, documentAttributes: [:]))
        payload.additions = spans(.ezAddition) { ($0 as? ClaudeAddition).map { Span(kind: $0.kind, author: $0.author) } }
        payload.transcripts = spans(.ezTranscript) { _ in Span(kind: "transcription") }
        payload.audio = spans(.ezAudio) { ($0 as? String).map { Span(kind: $0) } }
        payload.marks = spans(.ezMark) { ($0 as? String).map { Span(kind: $0) } }
        payload.systemFonts = spans(.font) { value in
            guard let font = value as? NSFont, font.fontName.hasPrefix(".") else { return nil }
            return Span(kind: describe(font))
        }
        payload.info = snapshot.info
        payload.plainText = text.string
        return try JSONEncoder().encode(payload)
    }

    /// Pièces jointes prêtes à enregistrer : seulement leur fichier (l'image affichée, redimensionnée par
    /// l'éditeur, ferait réencoder chaque image), et les grosses photos (TIFF, plus de 1,5 Mo) en JPEG.
    private static func compressImages(_ text: NSMutableAttributedString) {
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            var wrapper = attachment.fileWrapper
            if wrapper?.regularFileContents == nil, let image = attachment.image, let png = image.tiffRepresentation
                .flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]) {
                wrapper = FileWrapper(regularFileWithContents: png)
                wrapper?.preferredFilename = "image.png"
            }
            guard let data = wrapper?.regularFileContents else { return }
            let name = wrapper?.preferredFilename?.lowercased() ?? ""
            // Les PDF de diapositives restent des PDF ; les schémas et petites images restent nets.
            let heavy = !Slides.isPDF(data) && (name.hasSuffix(".tiff") || name.hasSuffix(".tif") || data.count > 1_500_000)
            if heavy, let image = NSImage(data: data), let jpeg = jpeg(image, maxSide: 2400) {
                wrapper = FileWrapper(regularFileWithContents: jpeg)
                wrapper?.preferredFilename = "image.jpg"
            }
            guard let wrapper else { return }
            let clean = NSTextAttachment(fileWrapper: wrapper)
            clean.bounds = attachment.bounds
            text.addAttribute(.attachment, value: clean, range: range)
        }
    }

    private static func jpeg(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let rep = NSBitmapImageRep(cgImage: cg)
        guard scale < 1 else { return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) }
        let resized = NSImage(size: NSSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
        resized.lockFocus()
        NSImage(cgImage: cg, size: .zero).draw(in: NSRect(origin: .zero, size: resized.size))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// Police système décrite par « taille|graisse|italique » (ex. « 15|0.4|1 »).
    private static func describe(_ font: NSFont) -> String {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = traits?[.weight] as? CGFloat ?? 0
        let italic = NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        return "\(font.pointSize)|\(weight)|\(italic ? 1 : 0)"
    }

    private static func systemFont(_ description: String) -> NSFont {
        let parts = description.split(separator: "|").compactMap { Double($0) }
        guard parts.count == 3 else { return LessonStyle.bodyFont }
        let font = NSFont.systemFont(ofSize: parts[0], weight: NSFont.Weight(parts[1]))
        return parts[2] == 1 ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
    }

    /// Le lecteur RTF de macOS garde les listes dans le style des paragraphes mais supprime le texte des
    /// puces (« \t•\t », « \t1.\t ») : on le remet, sinon les puces disparaissent et les passages marqués
    /// (enregistrés par position) se décalent.
    static func restoreListMarkers(_ text: NSMutableAttributedString) {
        let ns = text.string as NSString
        var paragraphs: [NSRange] = []
        var location = 0
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
        }
        var numbers: [ObjectIdentifier: Int] = [:]
        var previousList: NSTextList?
        // Numérotation dans l'ordre, puis insertion de la fin vers le début (sans décaler ce qui reste à faire).
        var inserts: [(Int, NSAttributedString)] = []
        for paragraph in paragraphs {
            guard let style = text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
                  let list = style.textLists.last else { previousList = nil; continue }
            let key = ObjectIdentifier(list)
            let number = (previousList === list || numbers[key] != nil) ? (numbers[key] ?? 0) + 1 : list.startingItemNumber
            numbers[key] = number
            previousList = list
            let existing = ns.substring(with: paragraph)
            guard LessonStyle.markerRange(in: existing) == nil else { continue }
            var attributes = text.attributes(at: paragraph.location, effectiveRange: nil)
            attributes.removeValue(forKey: .attachment)
            inserts.append((paragraph.location, NSAttributedString(string: LessonStyle.marker(list, number: number), attributes: attributes)))
        }
        for (location, marker) in inserts.reversed() { text.insert(marker, at: location) }
    }

    /// Lecture rapide pour la bibliothèque : infos et texte brut seulement.
    static func summary(of url: URL) -> (info: DocumentInfo, text: String)? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        var text = payload.plainText ?? ""
        if text.isEmpty, let rtf = payload.rtf, let decoded = try? Self.rtf(rtf) { text = decoded.string }
        return (payload.info ?? DocumentInfo(), text)
    }

    private static func rtf(_ data: Data) throws -> NSMutableAttributedString {
        try NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                      documentAttributes: nil)
    }
}
