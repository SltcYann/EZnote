import AppKit

/// Markdown simple renvoyé par Claude → texte mis en forme de l'éditeur.
/// Les blocs « :::claude Type … ::: » deviennent des ajouts de Claude (contour orange).
enum LessonRenderer {
    private static let numbered = try! NSRegularExpression(pattern: "^(\\d+)[.)]\\s+")

    static func render(_ markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var addition: ClaudeAddition?
        let bullets = NSTextList(markerFormat: .disc, options: 0)
        var numbers = NSTextList(markerFormat: LessonStyle.numbered, options: 0)
        var lastWasNumbered = false

        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix(":::") {
                let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if rest.lowercased().hasPrefix("claude") {
                    let kind = rest.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    addition = ClaudeAddition(kind: kind.isEmpty ? "Précision" : kind.prefix(1).uppercased() + kind.dropFirst())
                } else {
                    addition = nil
                }
                continue
            }
            if line.isEmpty { continue }

            var block = LessonStyle.Block.body
            var text = Substring(line)
            var list: NSTextList?
            var number = 1

            if line.hasPrefix("### ") { block = .subheading; text = text.dropFirst(4) }
            else if line.hasPrefix("## ") { block = .heading; text = text.dropFirst(3) }
            else if line.hasPrefix("# ") { block = .title; text = text.dropFirst(2) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") { list = bullets; text = text.dropFirst(2) }
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
                LessonStyle.applyList(list, to: style)
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

/// Texte de l'éditeur → notes en Markdown simple, envoyées à Claude.
enum NotesExporter {
    static func markdown(from text: NSAttributedString) -> String {
        let ns = text.string as NSString
        let fm = NSFontManager.shared
        var lines: [String] = []
        var open: ClaudeAddition?
        var location = 0

        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraph)
            let addition = text.attribute(.ezAddition, at: paragraph.location, effectiveRange: nil) as? ClaudeAddition
            if addition !== open {
                if open != nil { lines.append(":::") }
                if let addition { lines.append(":::claude \(addition.kind)") }
                open = addition
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
                prefix = symbol.first?.isNumber == true ? symbol + " " : "- "
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
            text.enumerateAttribute(.font, in: content) { value, run, _ in
                let piece = ns.substring(with: run)
                guard block == .body, let font = value as? NSFont, !piece.trimmingCharacters(in: .whitespaces).isEmpty else {
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
        if open != nil { lines.append(":::") }
        return lines.joined(separator: "\n")
    }
}
