import SwiftUI

/// Fenêtre d'un document : fond UY animé, feuille de papier, barre d'outils et bouton EZifier.
struct ContentView: View {
    @ObservedObject var document: EZDocument
    @StateObject private var editor = EditorController()

    var body: some View {
        ZStack(alignment: .bottom) {
            MeshBackground(mood: editor.isWorking ? .claude : .calm)
            EditorView(document: document, controller: editor)
            if editor.isWorking {
                StatusPill(phase: editor.phase)
                    .padding(.bottom, UY.space24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(UY.ease(0.35), value: editor.isWorking)
        .focusedSceneObject(editor)
        .frame(minWidth: 640, minHeight: 480)
        .toolbar { toolbar }
        .sheet(isPresented: $editor.needsAPIKey) {
            APIKeySheet { editor.ezify() }
        }
        .alert("EZifier", isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Menu {
                ForEach(LessonStyle.Block.allCases, id: \.self) { block in
                    Button(block.label) { editor.setBlock(block) }
                }
            } label: {
                Label("Style", systemImage: "textformat.size")
            }
            .help("Style du paragraphe")

            ControlGroup {
                toolButton("Gras", icon: "bold") { editor.toggleBold() }
                toolButton("Italique", icon: "italic") { editor.toggleItalic() }
                toolButton("Souligné", icon: "underline") { editor.toggleUnderline() }
            }
            ControlGroup {
                toolButton("Liste à puces", icon: "list.bullet") { editor.toggleList(.disc) }
                toolButton("Liste numérotée", icon: "list.number") { editor.toggleList(LessonStyle.numbered) }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button { editor.ezify() } label: {
                HStack(spacing: 6) {
                    UYSymbol(name: editor.isWorking ? "stop.fill" : "sparkles", size: 14, verticalOnly: true)
                    Text(editor.isWorking ? "Arrêter" : "EZifier")
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(UY.claude)
            .help("Claude transforme tes notes en leçon complète (⇧⌘E)")
        }
    }

    private func toolButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { UYSymbol(name: icon, size: 14) }
            .help(title)
            .accessibilityLabel(title)
            .disabled(editor.isWorking)
    }
}

/// Capsule en bas de la fenêtre pendant que Claude travaille.
private struct StatusPill: View {
    let phase: EditorController.Phase

    private var text: String {
        switch phase {
        case .idle, .reading: return "Claude lit tes notes…"
        case .searching: return "Claude cherche sur le web…"
        case .writing: return "Claude rédige ta leçon…"
        }
    }

    var body: some View {
        GlassCapsuleLabel(text: text, tint: UY.claude.opacity(0.35)) {
            ProgressView().controlSize(.small)
        }
        .contentTransition(.opacity)
        .animation(UY.ease(0.25), value: phase)
    }
}
