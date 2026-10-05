import AppKit
import SwiftUI

@main
struct EZnoteApp: App {
    init() {
        #if DEBUG
        Snapshot.runIfRequested()
        #endif
        SaveFolder.apply()
        DateNames.install()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { EZDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        // Assez large pour que la barre d'outils laisse le titre en entier (« 5 octobre 2026 (2) »).
        .defaultSize(width: 1120, height: 780)
        .commands {
            EZnoteCommands()
        }

        Window("Bibliothèque", id: "library") {
            LibraryView()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        Settings {
            SettingsView()
        }
    }
}

/// Menus de la fenêtre active : IA, insertion, export, impression, bibliothèque.
struct EZnoteCommands: Commands {
    @FocusedObject private var editor: EditorController?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Menu Format : mêmes actions que les boutons de la barre d'outils (le ⌘B du menu système
        // n'atteignait pas le texte).
        CommandGroup(replacing: .textFormatting) {
            Menu("Police") {
                Button("Afficher les polices") { NSFontManager.shared.orderFrontFontPanel(nil) }
                    .keyboardShortcut("t")
                Divider()
                Button("Gras") { editor?.toggleBold() }.keyboardShortcut("b")
                Button("Italique") { editor?.toggleItalic() }.keyboardShortcut("i")
                Button("Souligné") { editor?.toggleUnderline() }.keyboardShortcut("u")
                Divider()
                Button("Plus grand") { editor?.changeSize(by: 1) }.keyboardShortcut("=")
                Button("Plus petit") { editor?.changeSize(by: -1) }.keyboardShortcut("-")
                Divider()
                Button("Afficher les couleurs") { NSApp.orderFrontColorPanel(nil) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .disabled(editor == nil)
            Menu("Texte") {
                Button("Aligner à gauche") { NSApp.sendAction(#selector(NSText.alignLeft(_:)), to: nil, from: nil) }
                    .keyboardShortcut("{")
                Button("Centrer") { NSApp.sendAction(#selector(NSText.alignCenter(_:)), to: nil, from: nil) }
                    .keyboardShortcut("|")
                Button("Justifier") { NSApp.sendAction(#selector(NSTextView.alignJustified(_:)), to: nil, from: nil) }
                Button("Aligner à droite") { NSApp.sendAction(#selector(NSText.alignRight(_:)), to: nil, from: nil) }
                    .keyboardShortcut("}")
            }
            .disabled(editor == nil)
            Menu("Style du paragraphe") {
                ForEach(LessonStyle.Block.allCases, id: \.self) { block in
                    Button(block.label) { editor?.setBlock(block) }
                }
                Divider()
                Button("Liste à puces") { editor?.toggleList(.disc) }
                Button("Liste numérotée") { editor?.toggleList(LessonStyle.numbered) }
            }
            .disabled(editor == nil)
        }

        CommandMenu("Claude") {
            Group {
                Button(editor?.isWorking == true ? "Arrêter" : "EZifier") { editor?.ezify() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Fiches et quiz…") { editor?.openTool(.revision) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Fiche de synthèse…") { editor?.openTool(.summary) }
                Button("Poser une question sur la sélection…") { editor?.askAboutSelection() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Divider()
                Button(editor?.isRecording == true ? "Arrêter l'enregistrement" : "Enregistrer le cours") { editor?.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
            .disabled(editor == nil)
        }

        CommandMenu("Insertion") {
            Group {
                Button("Image…") { editor?.insertImage() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Button("Marquer comme important") { editor?.insertMark(.important) }
                    .keyboardShortcut("i", modifiers: [.command, .control])
                Button("Marquer « pas compris »") { editor?.insertMark(.unclear) }
                    .keyboardShortcut("u", modifiers: [.command, .control])
            }
            .disabled(editor == nil)
            Divider()
            Text("Formule : tape-la entre $…$ en LaTeX simple, ex. $x^2 + \\sqrt{y}$")
        }

        CommandGroup(after: .saveItem) {
            Menu("Exporter") {
                Button("PDF…") { editor?.export(.pdf) }
                Button("Word (.docx)…") { editor?.export(.word) }
            }
            .disabled(editor == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Imprimer…") { editor?.printDocument() }
                .keyboardShortcut("p")
                .disabled(editor == nil)
        }

        CommandGroup(before: .windowList) {
            Button("Bibliothèque") { openWindow(id: "library") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
        }
    }
}
