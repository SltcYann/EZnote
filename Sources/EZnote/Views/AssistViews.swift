import AppKit
import SwiftUI

// MARK: - Fiche de synthèse

/// La leçon résumée sur une page : à imprimer, exporter ou ajouter au document.
struct SummaryView: View {
    let editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var markdown = ""
    @State private var loading = true
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: UY.space14) {
            Text("Fiche de synthèse").font(UY.headline)
            RenderedText(markdown: markdown)
                .uyGlass(radius: UY.radiusTile)
                .overlay {
                    if markdown.isEmpty && loading {
                        VStack(spacing: UY.space12) {
                            ProgressView()
                            Text("\(AI.authorName) résume ta leçon…").font(UY.subheadline).foregroundStyle(UY.inkSecondary)
                        }
                    }
                }
            if let failure { Text(failure).font(UY.footnote).foregroundStyle(UY.danger) }
            HStack(spacing: UY.space12) {
                Button("Fermer") { task?.cancel(); dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Imprimer…") { Exporter.printDocument(rendered, from: NSApp.keyWindow) }.buttonStyle(.glass)
                Button("Exporter en PDF…") {
                    Exporter.export(rendered, as: .pdf, name: "Synthèse – " + (editor.textView?.window?.title ?? "EZnote"), from: nil)
                }
                .buttonStyle(.glass)
                Button("Ajouter au document") { editor.appendToDocument(markdown); dismiss() }
                    .buttonStyle(.glassProminent).tint(UY.claude)
            }
            .controlSize(.large)
            .disabled(loading)
        }
        .padding(UY.space24)
        .frame(width: 640, height: 640)
        .uyMakeKeyOnAppear()
        .onExitCommand { task?.cancel(); dismiss() }
        .onAppear(perform: generate)
        .onDisappear { task?.cancel() }
    }

    private var rendered: NSAttributedString { LessonRenderer.render(markdown, author: AI.authorName) }

    private func generate() {
        let request = AIRequest(system: AssistPrompt.summary,
                                user: AssistPrompt.lesson(editor.lessonMarkdown, context: editor.context), maxTokens: 6000)
        task = Task { @MainActor in
            do {
                for try await event in try AI.stream(request) {
                    if case .text(let delta) = event { markdown += delta }
                    if case .restart = event { markdown = "" }
                }
            } catch {
                if !(error is CancellationError) { failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
            loading = false
        }
    }
}

// MARK: - Question sur un passage

struct QuestionView: View {
    let editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var loading = false
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: UY.space14) {
            Text("Poser une question à \(AI.authorName)").font(UY.headline)
            Text("« \(editor.questionPassage) »")
                .font(UY.footnote).italic()
                .foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            GlassField(placeholder: "Ex. Explique-moi ce passage avec un exemple", text: $question)
                .onSubmit(ask)
            if !answer.isEmpty || loading {
                RenderedText(markdown: answer)
                    .uyGlass(radius: UY.radiusTile)
                    .overlay { if answer.isEmpty { ProgressView() } }
            } else {
                Spacer()
            }
            if let failure { Text(failure).font(UY.footnote).foregroundStyle(UY.danger) }
            HStack(spacing: UY.space12) {
                Button("Fermer") { task?.cancel(); dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                if !answer.isEmpty && !loading {
                    Button("Ajouter au document") { editor.insertAnswer(answer); dismiss() }
                        .buttonStyle(.glassProminent).tint(UY.claude)
                } else {
                    Button("Demander", action: ask)
                        .buttonStyle(.glassProminent).tint(UY.claude)
                        .keyboardShortcut(.defaultAction)
                        .disabled(loading)
                }
            }
            .controlSize(.large)
        }
        .padding(UY.space24)
        .frame(width: 560, height: 520)
        .uyMakeKeyOnAppear()
        .onExitCommand { task?.cancel(); dismiss() }
        .onDisappear { task?.cancel() }
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespaces).isEmpty ? "Explique-moi ce passage." : question
        let request = AIRequest(system: AssistPrompt.question,
                                user: AssistPrompt.questionMessage(passage: editor.questionPassage, question: text,
                                                                   lesson: editor.lessonMarkdown, context: editor.context),
                                maxTokens: 4000)
        answer = ""
        failure = nil
        loading = true
        task = Task { @MainActor in
            do {
                for try await event in try AI.stream(request) {
                    if case .text(let delta) = event { answer += delta }
                    if case .restart = event { answer = "" }
                }
            } catch {
                if !(error is CancellationError) { failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
            loading = false
        }
    }
}

// MARK: - Texte rendu

/// Markdown de l'IA affiché avec la typographie d'EZnote (lecture seule). TextKit 1, comme l'éditeur :
/// le moteur récent n'affiche pas le texte des listes « \t•\t ».
struct RenderedText: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = ClaudeLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = RenderedTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        textView.keptStorage = storage
        textView.isEditable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: LessonStyle.Box.side + 4, height: 16)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, let storage = textView.textStorage else { return }
        storage.setAttributedString(LessonRenderer.render(markdown, author: AI.authorName))
        LessonStyle.normalizeSpacing(storage, around: NSRange(location: 0, length: storage.length))
    }
}

/// Texte en lecture seule qui dessine aussi les encadrés de l'IA.
final class RenderedTextView: NSTextView {
    var keptStorage: NSTextStorage?

    override func drawBackground(in rect: NSRect) {
        (layoutManager as? ClaudeLayoutManager)?.drawClaudeBoxes(in: rect, origin: textContainerOrigin)
    }
}
