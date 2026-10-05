import AppKit

/// Markdown simple renvoyé par Claude → texte mis en forme de l'éditeur.
/// Les blocs « :::claude Type … ::: » deviennent des ajouts de Claude (contour orange).
enum LessonRenderer {
    private static let numbered = try! NSRegularExpression(pattern: "^(\\d+)[.)]\\s+")

    /// Retire la ligne « Matière : … » que l'IA met en tête quand la matière n'est pas connue.
    static func extractSubject(_ markdown: String) -> (subject: String?, lesson: String) {
        let trimmed = markdown.drop { $0.isWhitespace || $0.isNewline }
        guard trimmed.lowercased().hasPrefix("matière") || trimmed.lowercased().hasPrefix("matiere") else { return (nil, markdown) }
        guard let end = trimmed.firstIndex(of: "\n") else { return (nil, "") }   // ligne encore incomplète
        let line = trimmed[..<end]
        let subject = line.split(separator: ":", maxSplits: 1).dropFirst().first?
            .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*_."))
        return (subject, String(trimmed[trimmed.index(after: end)...]))
    }

    /// `images` : les images des notes, dans l'ordre ; « [Image n] » seul sur sa ligne les replace dans la leçon.
    static func render(_ markdown: String, author: String = "Claude", images: [NSTextAttachment] = []) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var addition: ClaudeAddition?
        let bullets = NSTextList(markerFormat: .disc, options: 0)
        // Sous-listes : « ◦ » puis « ▪ » (deux espaces ou une tabulation par niveau dans le Markdown).
        let subBullets = [NSTextList(markerFormat: .circle, options: 0), NSTextList(markerFormat: .square, options: 0)]
        var numbers = NSTextList(markerFormat: LessonStyle.numbered, options: 0)
        var lastWasNumbered = false

        var lines = markdown.components(separatedBy: "\n")[...]
        while let raw = lines.popFirst() {
            // Les petits modèles locaux écrivent parfois « #### :::claude Exemple Texte… » ou des formules « $CO_2$ ».
            var line = MathText.convertInline(raw.trimmingCharacters(in: .whitespaces))
            if line.hasPrefix("#"), let marker = line.range(of: ":::") { line = String(line[marker.lowerBound...]) }

            if line.hasPrefix(":::") {
                let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if rest.lowercased().hasPrefix("claude") {
                    let words = rest.dropFirst(6).trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                    let first = words.first.map(String.init) ?? ""
                    let label = words.joined(separator: " ")
                    // « À retenir » fait deux mots.
                    let kinds = ["À retenir", "A retenir", "Précision", "Définition", "Exemple", "Explication", "Attention"]
                    let match = kinds.first { label.lowercased().hasPrefix($0.lowercased()) }
                    let kind = match.map { $0 == "A retenir" ? "À retenir" : $0 } ?? "Précision"
                    addition = ClaudeAddition(kind: kind, author: author)
                    // Texte sur la même ligne que le marqueur : premier paragraphe de l'ajout.
                    let content = match.map { String(label.dropFirst($0.count)).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) } ?? label
                    if !content.isEmpty { lines.insert(content, at: lines.startIndex) }
                } else {
                    addition = nil
                }
                continue
            }
            if line.isEmpty { continue }

            // « [Image 2] » seul sur sa ligne : on replace l'image des notes.
            if line.hasPrefix("[Image "), line.hasSuffix("]"),
               let n = Int(line.dropFirst(7).dropLast()), n >= 1, n <= images.count {
                let picture = NSMutableAttributedString(attachment: images[n - 1])
                picture.append(NSAttributedString(string: "\n"))
                let style = LessonStyle.paragraph(.body)
                style.alignment = .center
                picture.addAttributes([.paragraphStyle: style, .font: LessonStyle.bodyFont],
                                      range: NSRange(location: 0, length: picture.length))
                if let addition { picture.addAttribute(.ezAddition, value: addition, range: NSRange(location: 0, length: picture.length)) }
                out.append(picture)
                continue
            }

            var block = LessonStyle.Block.body
            var text = Substring(line)
            var list: NSTextList?
            var number = 1
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            let level = min(2, indent / 2)

            if line.hasPrefix("#### ") { block = .subheading; text = text.dropFirst(5) }
            else if line.hasPrefix("### ") { block = .subheading; text = text.dropFirst(4) }
            else if line.hasPrefix("## ") { block = .heading; text = text.dropFirst(3) }
            else if line.hasPrefix("# ") { block = .title; text = text.dropFirst(2) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                list = level == 0 ? bullets : subBullets[level - 1]
                text = text.dropFirst(2)
            }
            else if line.hasPrefix("> ") { text = text.dropFirst(2) }
            else if let match = numbered.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                number = Int((line as NSString).substring(with: match.range(at: 1))) ?? 1
                if !lastWasNumbered && number == 1 { numbers = NSTextList(markerFormat: LessonStyle.numbered, options: 0) }
                list = numbers
                text = Substring((line as NSString).substring(from: match.range.length))
            }
            lastWasNumbered = list === numbers

            let paragraph = inline(String(text), font: block.font)
            let style = LessonStyle.paragraph(block)
            if let list {
                LessonStyle.applyList(list, to: style, level: list === numbers ? min(level, 1) : level)
                paragraph.insert(NSAttributedString(string: LessonStyle.marker(list, number: number),
                                                    attributes: [.font: block.font, .foregroundColor: NSColor.textColor]), at: 0)
            }
            paragraph.append(NSAttributedString(string: "\n", attributes: [.font: block.font, .foregroundColor: NSColor.textColor]))
            let all = NSRange(location: 0, length: paragraph.length)
            paragraph.addAttribute(.paragraphStyle, value: style, range: all)
            if let addition { paragraph.addAttribute(.ezAddition, value: addition, range: all) }
            out.append(paragraph)
        }
        if out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    /// **gras**, *italique* et `code`. Un « * » entouré d'espaces reste un astérisque.
    private static func inline(_ text: String, font: NSFont) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let fm = NSFontManager.shared
        var bold = false, italic = false, code = false
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            var f = font
            if code { f = .monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular) }
            if bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
            if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            out.append(NSAttributedString(string: buffer, attributes: [.font: f, .foregroundColor: NSColor.textColor]))
            buffer = ""
        }

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let previous: Character? = i > 0 ? chars[i - 1] : nil
            if c == "`" {
                flush(); code.toggle(); i += 1; continue
            }
            if !code && c == "*" && next == "*" {
                flush(); bold.toggle(); i += 2; continue
            }
            if !code && c == "*" {
                let opens = !italic && next != nil && !next!.isWhitespace
                let closes = italic && previous != nil && !previous!.isWhitespace
                if opens || closes { flush(); italic.toggle(); i += 1; continue }
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return out
    }
}

/// Notes prêtes à envoyer à l'IA : Markdown simple, images à joindre, et pièces jointes à replacer dans la leçon.
struct ExportedNotes {
    var markdown: String
    var images: [Data]
    var attachments: [NSTextAttachment]
}

/// Texte de l'éditeur → notes en Markdown simple, envoyées à l'IA.
enum NotesExporter {
    static func markdown(from text: NSAttributedString) -> String { export(text).markdown }

    static func export(_ text: NSAttributedString) -> ExportedNotes {
        let ns = text.string as NSString
        let fm = NSFontManager.shared
        var lines: [String] = []
        var images: [Data] = []
        var attachments: [NSTextAttachment] = []
        var open: ClaudeAddition?
        var inTranscript = false
        var location = 0

        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraph)
            let addition = text.attribute(.ezAddition, at: paragraph.location, effectiveRange: nil) as? ClaudeAddition
            let transcript = text.attribute(.ezTranscript, at: paragraph.location, effectiveRange: nil) != nil
            if addition !== open || transcript != inTranscript {
                if open != nil || inTranscript { lines.append(":::") }
                if let addition { lines.append(":::claude \(addition.kind)") }
                else if transcript { lines.append(":::transcription") }
                open = addition
                inTranscript = addition == nil && transcript
            }

            var content = NSRange(location: paragraph.location, length: paragraph.length)
            while content.length > 0, let last = UnicodeScalar(ns.character(at: NSMaxRange(content) - 1)),
                  CharacterSet.newlines.contains(last) {
                content.length -= 1
            }
            var prefix = ""
            let paragraphText = ns.substring(with: content)
            if let marker = LessonStyle.markerRange(in: paragraphText) {
                let symbol = (paragraphText as NSString).substring(with: marker).trimmingCharacters(in: .whitespaces)
                // Sous-liste : deux espaces par niveau (retrait de 22 pt par niveau au-delà de 30).
                let headIndent = (text.attribute(.paragraphStyle, at: content.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 30
                let level = max(0, Int(((headIndent - 30) / 22).rounded()))
                prefix = String(repeating: "  ", count: level) + (symbol.first?.isNumber == true ? symbol + " " : "- ")
                content = NSRange(location: content.location + marker.length, length: content.length - marker.length)
            }
            let block = content.length > 0
                ? LessonStyle.Block.of(text.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont) : .body
            switch block {
            case .title: prefix = "# "
            case .heading: prefix = "## "
            case .subheading: prefix = "### "
            case .body: break
            }

            var line = ""
            text.enumerateAttributes(in: content) { attributes, run, _ in
                // Image : « [Image n] », l'image part avec le message.
                if let attachment = attributes[.attachment] as? NSTextAttachment {
                    if let image = LessonStyle.image(of: attachment), let jpeg = AI.jpeg(image) {
                        images.append(jpeg)
                        attachments.append(attachment)
                        line += "[Image \(images.count)]"
                    }
                    return
                }
                // Marque-page posé pendant le cours.
                if let mark = attributes[.ezMark] as? String {
                    line += mark == LessonStyle.Mark.unclear.rawValue ? "[PAS COMPRIS] " : "[IMPORTANT] "
                    return
                }
                let piece = ns.substring(with: run)
                guard block == .body, let font = attributes[.font] as? NSFont,
                      !piece.trimmingCharacters(in: .whitespaces).isEmpty else {
                    line += piece; return
                }
                let traits = fm.traits(of: font)
                var wrapped = piece
                if traits.contains(.italicFontMask) { wrapped = "*\(wrapped)*" }
                if traits.contains(.boldFontMask) { wrapped = "**\(wrapped)**" }
                line += wrapped
            }
            lines.append(prefix + line)
        }
        if open != nil || inTranscript { lines.append(":::") }
        return ExportedNotes(markdown: lines.joined(separator: "\n"), images: images, attachments: attachments)
    }
}
