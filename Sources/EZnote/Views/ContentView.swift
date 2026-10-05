import SwiftUI

/// Fenêtre d'un document : fond UY animé, feuille de papier, barre d'outils et bouton EZifier.
struct ContentView: View {
    @ObservedObject var document: EZDocument
    var fileURL: URL?
    @StateObject private var editor = EditorController()
    @State private var showsContext = false
    @State private var showsStyles = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MeshBackground(mood: editor.isWorking ? .claude : .calm)
            EditorView(document: document, controller: editor)
                .uyEdgeFade(28)
            Group {
                if editor.isWorking {
                    StatusPill(phase: editor.phase, author: editor.author)
                } else if editor.isRecording {
                    RecordingPill(recording: editor.recording,
                                  mark: { editor.insertMark($0) },
                                  stop: { editor.toggleRecording() })
                } else if editor.isPlaying {
                    PlayingPill { editor.stopAudio() }
                }
            }
            .padding(.bottom, UY.space24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(UY.ease(0.35), value: editor.isWorking)
        .animation(UY.ease(0.35), value: editor.isRecording)
        .animation(UY.ease(0.35), value: editor.isPlaying)
        .onAppear {
            SaveFolder.apply()
            AppAppearance.apply()
            editor.documentTitle = fileURL?.deletingPathExtension().lastPathComponent
        }
        .onChange(of: fileURL) { _, url in editor.documentTitle = url?.deletingPathExtension().lastPathComponent }
        .onChange(of: document.info) { _, _ in editor.markDirty() }
        .focusedSceneObject(editor)
        .frame(minWidth: 680, minHeight: 480)
        .toolbar { toolbar }
        .sheet(isPresented: $editor.needsAPIKey) {
            APIKeySheet { editor.ezify() }
        }
        .sheet(item: $editor.tool) { tool in
            switch tool {
            case .revision: RevisionView(document: document, editor: editor)
            case .summary: SummaryView(editor: editor)
            case .question: QuestionView(editor: editor)
            }
        }
        .alert("EZnote", isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showsContext.toggle() } label: {
                UYSymbol(name: document.info.context.isEmpty && document.info.subject.isEmpty ? "text.book.closed" : "text.book.closed.fill",
                         size: 14)
            }
            .help("Contexte du cours : matière, professeur, chapitre… (utilisé par l'IA et la dictée)")
            .accessibilityLabel("Contexte du cours")
            .popover(isPresented: $showsContext, arrowEdge: .bottom) {
                ContextPopover(document: document)
            }
        }

        ToolbarItemGroup(placement: .principal) {
            // Bouton texte (la barre d'outils masque le texte des menus) qui ouvre la liste des styles.
            Button { showsStyles.toggle() } label: {
                HStack(spacing: 5) {
                    Text(editor.block.label).font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(UY.ink)
                .frame(minWidth: 92)
            }
            .help("Style du paragraphe")
            .disabled(editor.isWorking)
            .popover(isPresented: $showsStyles, arrowEdge: .bottom) {
                VStack(spacing: 4) {
                    ForEach(LessonStyle.Block.allCases, id: \.self) { block in
                        Button { editor.setBlock(block); showsStyles = false } label: {
                            Text(block.label)
                                .font(.system(size: block.previewSize, weight: block == .body ? .regular : .bold))
                                .foregroundStyle(block == editor.block ? UY.claudeStrong : UY.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .contentShape(RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous))
                        }
                        .buttonStyle(UYPressStyle(radius: UY.radiusField))
                        .background {
                            if block == editor.block {
                                RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous).fill(UY.claude.opacity(0.14))
                            }
                        }
                    }
                }
                .padding(UY.space12)
                .frame(width: 210)
            }

            toolButton("Gras", icon: "bold", active: editor.formats.contains(.bold)) { editor.toggleBold() }
            toolButton("Italique", icon: "italic", active: editor.formats.contains(.italic)) { editor.toggleItalic() }
            toolButton("Souligné", icon: "underline", active: editor.formats.contains(.underline)) { editor.toggleUnderline() }
            toolButton("Liste à puces", icon: "list.bullet", active: editor.formats.contains(.bullets)) { editor.toggleList(.disc) }
            toolButton("Liste numérotée", icon: "list.number", active: editor.formats.contains(.numbers)) {
                editor.toggleList(LessonStyle.numbered)
            }
            Menu {
                Button("Image…", systemImage: "photo") { editor.insertImage() }
                Button("Marquer comme important", systemImage: "star") { editor.insertMark(.important) }
                Button("Marquer « pas compris »", systemImage: "questionmark.circle") { editor.insertMark(.unclear) }
            } label: {
                UYSymbol(name: "plus", size: 14)
            }
            .fixedSize()
            .help("Insérer une image ou un marque-page")
            .disabled(editor.isWorking)
        }

        ToolbarItem(placement: .primaryAction) {
            Button { editor.toggleRecording() } label: {
                UYSymbol(name: editor.isRecording ? "stop.fill" : "mic.fill", size: 14)
                    .foregroundStyle(editor.isRecording ? UY.danger : UY.ink)
            }
            .help(editor.isRecording ? "Arrêter l'enregistrement du cours" : "Enregistrer le cours : ce que dit le prof s'écrit dans le document")
            .accessibilityLabel(editor.isRecording ? "Arrêter l'enregistrement" : "Enregistrer le cours")
            .disabled(editor.isWorking || editor.recording == .preparing)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Fiches et quiz…", systemImage: "rectangle.on.rectangle.angled") { editor.openTool(.revision) }
                Button("Fiche de synthèse…", systemImage: "doc.text.magnifyingglass") { editor.openTool(.summary) }
                Button("Poser une question sur la sélection…", systemImage: "questionmark.bubble") { editor.askAboutSelection() }
            } label: {
                UYSymbol(name: "graduationcap", size: 14)
            }
            .fixedSize()
            .help("Réviser : fiches, quiz, synthèse, questions")
            .disabled(editor.isWorking || editor.isRecording)
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
            .help("L'IA transforme tes notes en leçon complète (⇧⌘E)")
        }
    }

    /// Bouton de mise en forme : l'icône passe en orange quand le format est actif à l'endroit du curseur
    /// (le bouton garde sa place dans le groupe).
    private func toolButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            UYSymbol(name: icon, size: 14, weight: active ? .heavy : .semibold)
                .foregroundStyle(active ? UY.claudeStrong : UY.ink)
                .animation(UY.ease(0.2), value: active)
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .disabled(editor.isWorking)
    }
}

/// Contexte du cours, propre au document : utilisé par EZifier, les outils de révision et la dictée.
private struct ContextPopover: View {
    @ObservedObject var document: EZDocument

    var body: some View {
        VStack(spacing: UY.space14) {
            Text("Contexte du cours").font(UY.headline)
            Text("L'IA s'en sert pour comprendre tes notes et deviner les mots mal transcrits ; la dictée, pour reconnaître le vocabulaire. Elle peut aussi chercher ce contexte sur le web.")
                .font(UY.footnote)
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GlassField(placeholder: "Matière (ex. Droit constitutionnel)", text: $document.info.subject)
            ContextEditor(text: $document.info.context,
                          placeholder: "Professeur, chapitre, livre, sujet du cours, mots techniques…")
                .frame(height: 130)
        }
        .padding(UY.space22)
        .frame(width: 380)
    }
}

/// Zone de texte arrondie avec indication, pour écrire du contexte.
struct ContextEditor: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(UY.subheadline)
            .multilineTextAlignment(.center)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous).fill(UY.track))
            .overlay(alignment: .top) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(UY.subheadline)
                        .foregroundStyle(UY.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Capsule en bas de la fenêtre pendant l'enregistrement du cours : durée, marque-pages, Arrêter.
private struct RecordingPill: View {
    let recording: EditorController.Recording
    var mark: (LessonStyle.Mark) -> Void
    var stop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: UY.space12) {
            Circle()
                .fill(UY.danger)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            if case .on(let since) = recording {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text("Enregistrement · \(Self.duration(context.date.timeIntervalSince(since)))")
                        .monospacedDigit()
                }
                Button { mark(.important) } label: { Label("Important", systemImage: "star.fill") }
                    .buttonStyle(.glass)
                    .help("Le prof insiste : marquer ce moment (⌃⌘I)")
                Button { mark(.unclear) } label: { Label("Pas compris", systemImage: "questionmark") }
                    .buttonStyle(.glass)
                    .help("Je n'ai pas compris : l'IA l'expliquera (⌃⌘U)")
            } else {
                Text("Préparation du micro…")
            }
            Button("Arrêter", action: stop)
                .buttonStyle(.glassProminent)
                .tint(UY.danger)
        }
        .controlSize(.small)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(UY.ink)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .uyGlass(radius: UY.radiusCapsule)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Capsule pendant la réécoute d'un passage du cours.
private struct PlayingPill: View {
    var stop: () -> Void

    var body: some View {
        HStack(spacing: UY.space12) {
            Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
            Text("Réécoute du cours")
            Button("Arrêter", action: stop).buttonStyle(.glassProminent).tint(UY.claude)
        }
        .controlSize(.small)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(UY.ink)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .uyGlass(radius: UY.radiusCapsule)
    }
}

/// Capsule en bas de la fenêtre pendant que l'IA travaille.
private struct StatusPill: View {
    let phase: EditorController.Phase
    let author: String

    private var text: String {
        switch phase {
        case .idle, .reading: return "\(author) lit tes notes…"
        case .searching: return "\(author) cherche sur le web…"
        case .writing: return "\(author) rédige ta leçon…"
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
