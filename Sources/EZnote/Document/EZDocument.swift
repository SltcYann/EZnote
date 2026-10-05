import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ezNote = UTType(exportedAs: "local.eznote.note")
}

/// Un document EZnote. Le texte vit dans un `NSTextStorage` partagé avec l'éditeur :
/// aucune copie à chaque frappe, seulement à l'enregistrement.
final class EZDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.ezNote, .rtf, .plainText] }
    static var writableContentTypes: [UTType] { [.ezNote, .rtf] }

    let storage: NSTextStorage

    init() {
        storage = NSTextStorage(string: "", attributes: LessonStyle.attributes(.body))
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        storage = NSTextStorage(attributedString: try NoteFile.read(data, type: configuration.contentType))
    }

    func snapshot(contentType: UTType) throws -> NSAttributedString {
        NSAttributedString(attributedString: storage)
    }

    func fileWrapper(snapshot: NSAttributedString, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try NoteFile.write(snapshot, type: configuration.contentType))
    }
}

/// Format `.eznote` : le texte en RTF, plus la liste des passages ajoutés par Claude
/// (le RTF ne sait pas les garder).
enum NoteFile {
    private struct Payload: Codable {
        var version = 1
        var rtf: Data
        var additions: [Span]
        var transcripts: [Span]?
    }

    private struct Span: Codable {
        var location: Int
        var length: Int
        var kind: String
    }

    static func read(_ data: Data, type: UTType) throws -> NSAttributedString {
        let text: NSMutableAttributedString
        if type.conforms(to: .ezNote) {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            text = try rtf(payload.rtf)
            for span in payload.transcripts ?? [] where span.location >= 0 && span.location + span.length <= text.length {
                text.addAttribute(.ezTranscript, value: true, range: NSRange(location: span.location, length: span.length))
            }
            for span in payload.additions where span.location >= 0 && span.location + span.length <= text.length {
                text.addAttribute(.ezAddition, value: ClaudeAddition(kind: span.kind),
                                  range: NSRange(location: span.location, length: span.length))
            }
        } else if type.conforms(to: .rtf) {
            text = try rtf(data)
        } else {
            text = NSMutableAttributedString(string: String(decoding: data, as: UTF8.self), attributes: LessonStyle.attributes(.body))
        }
        // La couleur du texte n'est pas enregistrée : on remet la couleur système, qui suit le mode sombre.
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NSColor.textColor, range: range) }
        }
        return text
    }

    static func write(_ snapshot: NSAttributedString, type: UTType) throws -> Data {
        let text = NSMutableAttributedString(attributedString: snapshot)
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            if (value as? NSColor) == NSColor.textColor { text.removeAttribute(.foregroundColor, range: range) }
        }
        let rtf = try text.data(from: all, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        guard type.conforms(to: .ezNote) else { return rtf }

        var spans: [Span] = []
        text.enumerateAttribute(.ezAddition, in: all) { value, range, _ in
            if let addition = value as? ClaudeAddition {
                spans.append(Span(location: range.location, length: range.length, kind: addition.kind))
            }
        }
        var transcripts: [Span] = []
        text.enumerateAttribute(.ezTranscript, in: all) { value, range, _ in
            if value != nil { transcripts.append(Span(location: range.location, length: range.length, kind: "transcription")) }
        }
        return try JSONEncoder().encode(Payload(rtf: rtf, additions: spans, transcripts: transcripts))
    }

    private static func rtf(_ data: Data) throws -> NSMutableAttributedString {
        try NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                      documentAttributes: nil)
    }
}
