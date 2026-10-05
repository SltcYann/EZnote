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
        .commands {
            TextFormattingCommands()
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
