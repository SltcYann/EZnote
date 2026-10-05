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
            EZifierCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

/// Menu « Claude » : EZifier (⇧⌘E) dans la fenêtre active.
struct EZifierCommands: Commands {
    @FocusedObject private var editor: EditorController?

    var body: some Commands {
        CommandMenu("Claude") {
            Button(editor?.isWorking == true ? "Arrêter" : "EZifier") { editor?.ezify() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor == nil)
        }
    }
}
