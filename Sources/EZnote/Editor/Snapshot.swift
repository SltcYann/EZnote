#if DEBUG
import AppKit

/// Outil de développement : `EZnote --snapshot fichier.png [dark]` rend une leçon d'exemple dans l'éditeur
/// et l'enregistre en image, sans ouvrir de fenêtre.
enum Snapshot {
    static let sample = """
    # La photosynthèse
    La photosynthèse est le processus par lequel les plantes fabriquent leur matière organique à partir de la lumière.
    :::claude Définition
    Une **matière organique** est une matière fabriquée par un être vivant et qui contient du *carbone*.
    :::
    ## Les ingrédients
    - de l'eau, puisée par les racines ;
    - du dioxyde de carbone, capté par les feuilles ;
    - de la lumière : $6CO_2 + 6H_2O \\to C_6H_{12}O_6 + 6O_2$
      - sous-point capté par la chlorophylle
        - sous-sous-point
    :::claude À retenir
    Un chêne adulte capte environ 20 kg de CO₂ par an.

    1. premier point
    2. second point
    :::
    La réaction a lieu dans les chloroplastes.
    """

    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--menu-dump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                func walk(_ menu: NSMenu, _ path: String) {
                    for item in menu.items {
                        if path.contains("Format") || item.keyEquivalent.lowercased() == "b" {
                            let line = "\(path) › \(item.title) [\(item.keyEquivalent)] \(item.keyEquivalentModifierMask.rawValue) \(item.action.map(NSStringFromSelector) ?? "-")\n"
                            FileHandle.standardError.write(Data(line.utf8))
                        }
                        if let sub = item.submenu { walk(sub, path + " › " + item.title) }
                    }
                }
                if let main = NSApp.mainMenu { walk(main, "") }
                exit(0)
            }
        }
        if let i = args.firstIndex(of: "--ai-test") {
            // `EZnote --ai-test [lesson|cards|quiz|summary]` : interroge l'IA réglée sur des notes d'exemple.
            let mode = i + 1 < args.count ? args[i + 1] : "lesson"
            Task { @MainActor in
                let notes = "photosynthèse\nplantes → matière organique avec lumière\nchloroplastes, CO2 + eau"
                let context = StudyContext(title: nil, info: DocumentInfo(subject: "SVT", context: "Cours de seconde"))
                let system = ["cards": AssistPrompt.flashcards, "quiz": AssistPrompt.quiz, "summary": AssistPrompt.summary][mode]
                    ?? LessonPrompt.system
                let user = mode == "lesson" ? LessonPrompt.userMessage(notes: notes, context: context)
                    : AssistPrompt.lesson(notes, context: context)
                do { print(try await AI.text(AIRequest(system: system, user: user))) }
                catch { print("ERREUR:", error.localizedDescription) }
                exit(0)
            }
            RunLoop.main.run()
        }
        if args.contains("--record-test") {
            // Enregistrement réel : la synthèse vocale lit un cours, le micro l'écoute, la transcription
            // s'écrit dans un document ; marque-page au milieu ; puis réécoute.
            Task { @MainActor in
                let document = EZDocument()
                document.info = DocumentInfo(subject: "Histoire", context: "Cours sur Robespierre et la Terreur")
                document.storage.setAttributedString(NSAttributedString(string: "Mes notes", attributes: LessonStyle.attributes(.body)))
                let layoutManager = ClaudeLayoutManager()
                document.storage.addLayoutManager(layoutManager)
                let container = NSTextContainer(size: NSSize(width: 600, height: 100_000))
                layoutManager.addTextContainer(container)
                let view = PageTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
                let editor = EditorController()
                editor.attach(textView: view, storage: document.storage, document: document)
                editor.toggleRecording()
                var waited = 0
                while editor.recording == .preparing && waited < 120 { try? await Task.sleep(for: .seconds(1)); waited += 1 }
                guard case .on = editor.recording else { print("ÉCHEC du démarrage :", editor.errorMessage ?? "?"); exit(1) }
                print("enregistrement démarré après", waited, "s")
                let say = Process()
                say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                say.arguments = ["-v", "Thomas", "En 1793, Robespierre et le Comité de salut public instaurent la Terreur. Des milliers de suspects sont guillotinés. La Terreur prend fin le 27 juillet 1794 avec la chute de Robespierre."]
                try? say.run()
                try? await Task.sleep(for: .seconds(6))
                editor.insertMark(.important)
                say.waitUntilExit()
                try? await Task.sleep(for: .seconds(3))
                await editor.stopRecording()
                let text = document.storage.string
                print("TEXTE :", text.debugDescription)
                var audio: String?
                var marks = 0
                document.storage.enumerateAttribute(.ezAudio, in: NSRange(location: 0, length: document.storage.length)) { v, _, _ in
                    if let v = v as? String, audio == nil { audio = v }
                }
                document.storage.enumerateAttribute(.ezMark, in: NSRange(location: 0, length: document.storage.length)) { v, _, _ in
                    if v != nil { marks += 1 }
                }
                print("marque-pages :", marks, "| repère audio :", audio ?? "aucun")
                if let id = audio?.split(separator: "@").first {
                    let url = AudioStore.url(for: String(id))
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    print("fichier audio :", url.lastPathComponent, size, "octets")
                    if let index = document.storage.string.range(of: "robespierre", options: .caseInsensitive).map({ NSRange($0, in: document.storage.string).location }) {
                        editor.replayAudio(at: index)
                        try? await Task.sleep(for: .seconds(2))
                        print("réécoute :", editor.isPlaying ? "en cours" : "arrêtée", editor.errorMessage ?? "")
                        editor.stopAudio()
                    }
                    try? FileManager.default.removeItem(at: url)
                    print("fichier audio de test supprimé")
                }
                exit(0)
            }
            RunLoop.main.run()
        }
        if args.contains("--bold-test") {
            Task { @MainActor in
                let document = EZDocument()
                document.storage.setAttributedString(NSAttributedString(string: "Révolution française\nCauses : crise", attributes: LessonStyle.attributes(.body)))
                let layoutManager = ClaudeLayoutManager()
                document.storage.addLayoutManager(layoutManager)
                let container = NSTextContainer(size: NSSize(width: 600, height: 1000))
                layoutManager.addTextContainer(container)
                let view = PageTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
                view.allowsUndo = true
                let editor = EditorController()
                editor.attach(textView: view, storage: document.storage, document: document)
                view.setSelectedRange(NSRange(location: 0, length: 21))
                editor.toggleItalic()
                let before = (document.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName ?? "-"
                editor.toggleBold()
                let after = (document.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName ?? "-"
                print("avant", before, "après", after, "formats", editor.formats)
                exit(0)
            }
            RunLoop.main.run()
        }
        if let i = args.firstIndex(of: "--write-samples"), i + 1 < args.count {
            let folder = URL(fileURLWithPath: args[i + 1])
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, subject, markdown) in [("Photosynthèse", "SVT", sample),
                                              ("Révolution française", "Histoire", "# La Révolution française\nLa prise de la Bastille a lieu le 14 juillet 1789."),
                                              ("Notes en vrac", "", "Penser à réviser les dérivées.")] {
                var info = DocumentInfo(subject: subject)
                info.cards = [Flashcard(question: "Q", answer: "R")]
                let data = try? NoteFile.write(NoteSnapshot(text: LessonRenderer.render(markdown), info: info), type: .ezNote)
                try? data?.write(to: folder.appendingPathComponent(name + ".eznote"))
            }
            exit(0)
        }
        if args.contains("--math-test") {
            for latex in [#"x^2 + y_1 \leq \sqrt{n}"#, #"\frac{a}{b} \to \infty"#, #"\sum_{i=1}^{n} i^2"#,
                          #"\alpha \in \mathbb{R}, \Delta = b^2 - 4ac"#, #"\frac{x+1}{2y}"#, #"e^{i\pi} = -1"#] {
                print(latex, "→", MathText.convert(latex))
            }
            print(MathText.convertInline("Prix : 5 $ et 6 $ ; aire $\\pi r^2$."))
            exit(0)
        }
        if let i = args.firstIndex(of: "--file-test"), i + 1 < args.count {
            // Aller-retour du format .eznote avec image, marque-page, audio et fiches ; export PDF et Word.
            Task { @MainActor in
                let folder = URL(fileURLWithPath: args[i + 1])
                let text = NSMutableAttributedString(attributedString: LessonRenderer.render(sample))
                let image = NSImage(size: NSSize(width: 1200, height: 600), flipped: false) { rect in
                    NSColor.systemTeal.setFill(); rect.fill(); return true
                }
                let attachment = NSTextAttachment()
                attachment.image = image
                let wrapper = FileWrapper(regularFileWithContents: image.tiffRepresentation!)
                wrapper.preferredFilename = "tableau.tiff"
                attachment.fileWrapper = wrapper
                text.append(NSAttributedString(string: "\n"))
                text.append(NSAttributedString(attachment: attachment))
                text.append(LessonStyle.Mark.important.attributed(base: LessonStyle.attributes(.body)))
                text.append(NSAttributedString(string: "phrase du prof", attributes: [.ezAudio: "abc@12.5", .ezTranscript: true]))
                var info = DocumentInfo(subject: "SVT", context: "Cours de M. Martin")
                info.cards = [Flashcard(question: "Q ?", answer: "R.")]
                do {
                    let data = try NoteFile.write(NoteSnapshot(text: text, info: info), type: .ezNote)
                    let (back, backInfo) = try NoteFile.read(data, type: .ezNote)
                    var attachments = 0, marks = 0, audio = 0, additions = 0
                    let all = NSRange(location: 0, length: back.length)
                    back.enumerateAttribute(.attachment, in: all) { v, _, _ in if v != nil { attachments += 1 } }
                    back.enumerateAttribute(.ezMark, in: all) { v, _, _ in if v != nil { marks += 1 } }
                    back.enumerateAttribute(.ezAudio, in: all) { v, _, _ in if v != nil { audio += 1 } }
                    back.enumerateAttribute(.ezAddition, in: all) { v, _, _ in if v != nil { additions += 1 } }
                    if back.string != text.string {
                        let a = Array(text.string.utf16), b = Array(back.string.utf16)
                        let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
                        print("différence à", i, "longueurs", a.count, b.count, "avant:", a[max(0,i-3)..<min(a.count,i+3)], "après:", b[max(0,i-3)..<min(b.count,i+3)])
                    }
                    var fontDiffs = 0
                    for i in stride(from: 0, to: min(text.length, back.length), by: 1) {
                        let a = (text.attribute(.font, at: i, effectiveRange: nil) as? NSFont)
                        let b = (back.attribute(.font, at: i, effectiveRange: nil) as? NSFont)
                        let fm = NSFontManager.shared
                        func key(_ f: NSFont?) -> String {
                            guard let f else { return "-" }
                            return "\(f.fontName.hasPrefix(".") ? "système" : f.familyName ?? "") \(f.pointSize) \(fm.traits(of: f).rawValue & (NSFontTraitMask.boldFontMask.rawValue | NSFontTraitMask.italicFontMask.rawValue))"
                        }
                        if key(a) != key(b) {
                            if fontDiffs == 0 { print("police différente à", i, a?.fontName ?? "-", a?.pointSize ?? 0, "→", b?.fontName ?? "-", b?.pointSize ?? 0) }
                            fontDiffs += 1
                        }
                    }
                    print("polices différentes :", fontDiffs)
                    print("taille", data.count, "| texte identique", back.string == text.string,
                          "| images", attachments, "| marques", marks, "| audio", audio, "| ajouts", additions,
                          "| infos", backInfo == info)
                    let exported = NotesExporter.export(back)
                    print("sous-listes :", exported.markdown.split(separator: "\n").filter { $0.contains("sous") })
                    print("notes pour l'IA :", exported.markdown.replacingOccurrences(of: "\n", with: " ⏎ ").suffix(160), "| images jointes", exported.images.count)
                    try Exporter.pdf(back, to: folder.appendingPathComponent("test.pdf"))
                    try Exporter.word(back).write(to: folder.appendingPathComponent("test.docx"))
                    print("PDF et Word écrits")
                } catch { print("ERREUR", error) }
                exit(0)
            }
            RunLoop.main.run()
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dark = args.contains("dark")
        let markdown = sample
        _ = """
        # La photosynthèse
        La photosynthèse est le processus par lequel les plantes fabriquent leur matière organique à partir de la lumière.
        :::claude Définition
        Une **matière organique** est une matière fabriquée par un être vivant et qui contient du *carbone*.
        :::
        ## Les ingrédients
        - de l'eau, puisée par les racines ;
        - du dioxyde de carbone, capté par les feuilles ;
        - de la lumière.
        :::claude Exemple
        Un chêne adulte capte environ 20 kg de CO₂ par an.

        1. premier point
        2. second point
        :::
        La réaction a lieu dans les chloroplastes.
        """
        let rendered = NSMutableAttributedString(attributedString: LessonRenderer.render(markdown))
        rendered.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 16))
        let storage = NSTextStorage(attributedString: rendered)
        LessonStyle.normalizeSpacing(storage, around: NSRange(location: 0, length: storage.length))
        let layoutManager = ClaudeLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: PageTextView.column, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        let view = PageTextView(frame: NSRect(x: 0, y: 0, width: 960, height: 1100), textContainer: container)
        view.drawsBackground = false
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.layoutColumn()
        layoutManager.ensureLayout(for: container)

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        let backdrop = NSImage(size: view.bounds.size, flipped: false) { rect in
            (dark ? NSColor(srgb: 0x0B0B10) : NSColor(srgb: 0x9FC7F0)).setFill()
            rect.fill()
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        backdrop.draw(in: view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
}
#endif
