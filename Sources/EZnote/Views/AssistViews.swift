import AppKit
import SwiftUI

// MARK: - Fiches et quiz

/// Réviser la leçon : fiches à révision espacée (gardées dans le document) et quiz à choix multiples.
struct RevisionView: View {
    @ObservedObject var document: EZDocument
    let editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var loading = false
    @State private var failure: String?

    // Fiches
    @State private var queue: [UUID] = []
    @State private var showsAnswer = false

    // Quiz
    @State private var quiz: [QuizQuestion] = []
    @State private var step = 0
    @State private var picked: Int?
    @State private var score = 0

    var body: some View {
        VStack(spacing: UY.space18) {
            HStack {
                Spacer()
                Picker("", selection: $mode) {
                    Text("Fiches").tag(0)
                    Text("Quiz").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button { dismiss() } label: { UYSymbol(name: "xmark", size: 12) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                if loading {
                    VStack(spacing: UY.space12) {
                        ProgressView()
                        Text(mode == 0 ? "\(AI.authorName) prépare tes fiches…" : "\(AI.authorName) prépare ton quiz…")
                            .font(UY.subheadline).foregroundStyle(UY.inkSecondary)
                    }
                } else if mode == 0 {
                    cards
                } else {
                    quizView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let failure {
                Text(failure).font(UY.footnote).foregroundStyle(UY.danger).multilineTextAlignment(.center)
            }
        }
        .padding(UY.space24)
        .frame(width: 600, height: 560)
        .onAppear(perform: startSession)
    }

    // MARK: Fiches

    private var dueCount: Int { document.info.cards.filter(\.isDue).count }

    @ViewBuilder
    private var cards: some View {
        if document.info.cards.isEmpty {
            emptyState(symbol: "rectangle.on.rectangle.angled", title: "Pas encore de fiches",
                       text: "\(AI.authorName) écrit des fiches question / réponse à partir de ta leçon. Tu les révises ensuite au bon moment : une fiche sue revient de plus en plus tard, une fiche ratée revient tout de suite.",
                       action: "Créer les fiches", run: generateCards)
        } else if let id = queue.first, let index = document.info.cards.firstIndex(where: { $0.id == id }) {
            let card = document.info.cards[index]
            VStack(spacing: UY.space18) {
                Text("\(queue.count) fiche\(queue.count > 1 ? "s" : "") à réviser")
                    .font(UY.caption).foregroundStyle(UY.inkSecondary)
                VStack(spacing: UY.space14) {
                    Text(card.question).font(UY.title3).multilineTextAlignment(.center)
                    if showsAnswer {
                        Divider()
                        Text(card.answer).font(UY.body).foregroundStyle(UY.ink).multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(UY.space24)
                .frame(maxWidth: .infinity, minHeight: 220)
                .uyGlass(radius: UY.radiusPanel)
                .onTapGesture { withAnimation(UY.ease(0.3)) { showsAnswer = true } }

                if showsAnswer {
                    HStack(spacing: UY.space12) {
                        Button { answer(index, knew: false) } label: { Label("À revoir", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.glass)
                            .keyboardShortcut("1", modifiers: [])
                        Button { answer(index, knew: true) } label: { Label("Je savais", systemImage: "checkmark") }
                            .buttonStyle(.glassProminent).tint(UY.green)
                            .keyboardShortcut("2", modifiers: [])
                    }
                    .controlSize(.large)
                } else {
                    Button("Voir la réponse") { withAnimation(UY.ease(0.3)) { showsAnswer = true } }
                        .buttonStyle(.glassProminent).tint(UY.claude)
                        .controlSize(.large)
                        .keyboardShortcut(.space, modifiers: [])
                }
            }
            .animation(UY.ease(0.3), value: showsAnswer)
        } else {
            let next = document.info.cards.map(\.due).min()
            emptyState(symbol: "checkmark.seal.fill", title: "Tout est révisé",
                       text: next.map { "Prochaine révision \($0.formatted(.relative(presentation: .named)))." } ?? "",
                       action: "Réviser toutes les fiches", run: { queue = document.info.cards.map(\.id).shuffled() },
                       secondary: ("Recréer les fiches", generateCards))
        }
    }

    private func startSession() {
        queue = document.info.cards.filter(\.isDue).map(\.id).shuffled()
        showsAnswer = false
    }

    private func answer(_ index: Int, knew: Bool) {
        document.info.cards[index].review(knew: knew)
        withAnimation(UY.ease(0.3)) {
            let id = queue.removeFirst()
            if !knew { queue.append(id) }   // une fiche ratée revient dans la même séance
            showsAnswer = false
        }
    }

    private func generateCards() {
        run {
            struct Item: Decodable { let question: String; let answer: String }
            let text = try await AI.text(AIRequest(system: AssistPrompt.flashcards,
                                                   user: AssistPrompt.lesson(editor.lessonMarkdown, context: editor.context),
                                                   maxTokens: 8000))
            let items = try AI.json([Item].self, from: text)
            document.info.cards = items.map { Flashcard(question: $0.question, answer: $0.answer) }
            startSession()
        }
    }

    // MARK: Quiz

    @ViewBuilder
    private var quizView: some View {
        if quiz.isEmpty {
            emptyState(symbol: "checklist", title: "Quiz", text: "10 questions à choix multiples sur ta leçon, avec la correction expliquée.",
                       action: "Commencer le quiz", run: generateQuiz)
        } else if step < quiz.count {
            let question = quiz[step]
            VStack(spacing: UY.space14) {
                Text("Question \(step + 1) sur \(quiz.count)").font(UY.caption).foregroundStyle(UY.inkSecondary)
                Text(question.question).font(UY.title3).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(question.choices.indices, id: \.self) { i in
                    Button { pick(i) } label: {
                        Text(question.choices[i])
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .tint(color(for: i, in: question))
                    .controlSize(.large)
                    .disabled(picked != nil)
                }
                if let picked {
                    Text((picked == question.answer ? "Bonne réponse. " : "Ce n'est pas ça. ") + question.explanation)
                        .font(UY.footnote).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(step + 1 < quiz.count ? "Question suivante" : "Voir le résultat") {
                        withAnimation(UY.ease(0.3)) { step += 1; self.picked = nil }
                    }
                    .buttonStyle(.glassProminent).tint(UY.claude)
                    .keyboardShortcut(.defaultAction)
                }
            }
        } else {
            emptyState(symbol: score * 2 >= quiz.count ? "star.fill" : "arrow.clockwise",
                       title: "\(score) / \(quiz.count)",
                       text: score == quiz.count ? "Parfait !" : "Relis les passages ratés, puis réessaie.",
                       action: "Nouveau quiz", run: generateQuiz)
        }
    }

    private func color(for choice: Int, in question: QuizQuestion) -> Color? {
        guard let picked else { return nil }
        if choice == question.answer { return UY.green }
        return choice == picked ? UY.danger : nil
    }

    private func pick(_ choice: Int) {
        withAnimation(UY.ease(0.25)) {
            picked = choice
            if choice == quiz[step].answer { score += 1 }
        }
    }

    private func generateQuiz() {
        run {
            let text = try await AI.text(AIRequest(system: AssistPrompt.quiz,
                                                   user: AssistPrompt.lesson(editor.lessonMarkdown, context: editor.context),
                                                   maxTokens: 8000))
            let questions = try AI.json([QuizQuestion].self, from: text)
                .filter { $0.choices.indices.contains($0.answer) }
            guard !questions.isEmpty else { throw AIError.empty }
            quiz = questions
            step = 0; score = 0; picked = nil
        }
    }

    // MARK: Commun

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        loading = true
        failure = nil
        Task { @MainActor in
            do { try await work() } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? "La réponse de l'IA n'a pas pu être lue. Réessaie."
            }
            loading = false
        }
    }

    private func emptyState(symbol: String, title: String, text: String, action: String, run: @escaping () -> Void,
                            secondary: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: UY.space14) {
            UYSymbol(name: symbol, size: 30).foregroundStyle(UY.claude)
            Text(title).font(UY.title3)
            Text(text).font(UY.subheadline).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: UY.space12) {
                if let secondary { Button(secondary.0, action: secondary.1).buttonStyle(.glass) }
                Button(action, action: run).buttonStyle(.glassProminent).tint(UY.claude)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 440)
    }
}

struct QuizQuestion: Decodable {
    let question: String
    let choices: [String]
    let answer: Int
    let explanation: String
}

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

/// Markdown de l'IA affiché avec la typographie d'EZnote (lecture seule).
struct RenderedText: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 18, height: 16)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(LessonRenderer.render(markdown, author: AI.authorName))
    }
}
