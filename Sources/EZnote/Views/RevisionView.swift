import AppKit
import AVFoundation
import SwiftUI

/// Réviser la leçon : fiches à révision espacée, quiz, oral blanc, points faibles et planning jusqu'à l'examen.
struct RevisionView: View {
    enum Tab: String, CaseIterable {
        case cards = "Fiches", quiz = "Quiz", oral = "Oral", weak = "Points faibles", plan = "Planning"
    }

    @ObservedObject var document: EZDocument
    let editor: EditorController
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.cards

    var body: some View {
        VStack(spacing: UY.space18) {
            HStack {
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(UY.claude)
                .frame(width: 440)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button { dismiss() } label: { UYSymbol(name: "xmark", size: 12) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                switch tab {
                case .cards: CardsTab(document: document, editor: editor)
                case .quiz: QuizTab(document: document, editor: editor)
                case .oral: OralTab(document: document, editor: editor)
                case .weak: WeakPointsTab(document: document, editor: editor, close: { dismiss() })
                case .plan: PlanTab(document: document)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(UY.space24)
        .frame(width: 640, height: 600)
        .uyMakeKeyOnAppear()
        .onExitCommand { dismiss() }
        .onDisappear { ReviewReminders.reschedule() }
    }
}

// MARK: - Éléments communs

/// État vide ou de fin, centré, avec une action.
struct RevisionEmptyState: View {
    let symbol: String
    let title: String
    let text: String
    let action: String
    let run: () -> Void
    var secondary: (String, () -> Void)?

    var body: some View {
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
        .frame(maxWidth: 460)
    }
}

/// Indicateur pendant que l'IA prépare quelque chose.
struct RevisionLoading: View {
    let text: String

    var body: some View {
        VStack(spacing: UY.space12) {
            ProgressView()
            Text(text).font(UY.subheadline).foregroundStyle(UY.inkSecondary)
        }
    }
}

/// Travail d'IA avec chargement et message d'erreur.
@MainActor
final class RevisionTask: ObservableObject {
    @Published var loading = false
    @Published var failure: String?

    func run(_ work: @escaping @MainActor () async throws -> Void) {
        loading = true
        failure = nil
        Task { @MainActor in
            do { try await work() } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? "La réponse de l'IA n'a pas pu être lue. Réessaie."
            }
            loading = false
        }
    }
}

private extension EditorController {
    /// Crée les fiches de la leçon (utilisé par les onglets Fiches et Oral).
    func generateCards(into document: EZDocument) async throws {
        struct Item: Decodable { let question: String; let answer: String }
        let text = try await AI.text(AIRequest(system: AssistPrompt.flashcards,
                                               user: AssistPrompt.lesson(lessonMarkdown, context: context), maxTokens: 8000))
        let items = try AI.json([Item].self, from: text)
        guard !items.isEmpty else { throw AIError.empty }
        document.info.cards = items.map { Flashcard(question: $0.question, answer: $0.answer) }
    }
}

// MARK: - Fiches

private struct CardsTab: View {
    @ObservedObject var document: EZDocument
    let editor: EditorController
    @StateObject private var task = RevisionTask()
    @State private var queue: [UUID] = []
    @State private var showsAnswer = false

    var body: some View {
        VStack {
            if task.loading {
                RevisionLoading(text: "\(AI.authorName) prépare tes fiches…")
            } else if document.info.cards.isEmpty {
                RevisionEmptyState(symbol: "rectangle.on.rectangle.angled", title: "Pas encore de fiches",
                                   text: "\(AI.authorName) écrit des fiches question / réponse à partir de ta leçon. Tu les révises ensuite au bon moment : une fiche sue revient de plus en plus tard, une fiche ratée revient tout de suite.",
                                   action: "Créer les fiches", run: generate)
            } else if let id = queue.first, let index = document.info.cards.firstIndex(where: { $0.id == id }) {
                card(at: index)
            } else {
                let next = document.info.cards.map(\.due).min()
                RevisionEmptyState(symbol: "checkmark.seal.fill", title: "Tout est révisé",
                                   text: next.map { "Prochaine révision \($0.formatted(.relative(presentation: .named)))." } ?? "",
                                   action: "Réviser toutes les fiches", run: { queue = document.info.cards.map(\.id).shuffled() },
                                   secondary: ("Recréer les fiches", generate))
            }
            if let failure = task.failure {
                Text(failure).font(UY.footnote).foregroundStyle(UY.danger).multilineTextAlignment(.center)
            }
        }
        .onAppear(perform: startSession)
    }

    private func card(at index: Int) -> some View {
        let card = document.info.cards[index]
        return VStack(spacing: UY.space18) {
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
    }

    private func startSession() {
        queue = document.info.dueCards().map(\.id).shuffled()
        showsAnswer = false
    }

    private func answer(_ index: Int, knew: Bool) {
        document.info.cards[index].review(knew: knew, examDate: document.info.examDate)
        withAnimation(UY.ease(0.3)) {
            let id = queue.removeFirst()
            if !knew { queue.append(id) }   // une fiche ratée revient dans la même séance
            showsAnswer = false
        }
    }

    private func generate() {
        task.run {
            try await editor.generateCards(into: document)
            startSession()
        }
    }
}

// MARK: - Quiz

struct QuizQuestion: Decodable {
    let question: String
    let choices: [String]
    let answer: Int
    let explanation: String
}

private struct QuizTab: View {
    @ObservedObject var document: EZDocument
    let editor: EditorController
    @StateObject private var task = RevisionTask()
    @State private var quiz: [QuizQuestion] = []
    @State private var step = 0
    @State private var picked: Int?
    @State private var score = 0

    var body: some View {
        VStack {
            if task.loading {
                RevisionLoading(text: "\(AI.authorName) prépare ton quiz…")
            } else if quiz.isEmpty {
                RevisionEmptyState(symbol: "checklist", title: "Quiz",
                                   text: "10 questions à choix multiples sur ta leçon, avec la correction expliquée.",
                                   action: "Commencer le quiz", run: generate)
            } else if step < quiz.count {
                question(quiz[step])
            } else {
                RevisionEmptyState(symbol: score * 2 >= quiz.count ? "star.fill" : "arrow.clockwise",
                                   title: "\(score) / \(quiz.count)",
                                   text: score == quiz.count ? "Parfait !" : "Les questions ratées sont dans « Points faibles ».",
                                   action: "Nouveau quiz", run: generate)
            }
            if let failure = task.failure {
                Text(failure).font(UY.footnote).foregroundStyle(UY.danger).multilineTextAlignment(.center)
            }
        }
    }

    private func question(_ question: QuizQuestion) -> some View {
        VStack(spacing: UY.space14) {
            Text("Question \(step + 1) sur \(quiz.count)").font(UY.caption).foregroundStyle(UY.inkSecondary)
            Text(question.question).font(UY.title3).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(question.choices.indices, id: \.self) { i in
                let tint = color(for: i, in: question)
                Button { pick(i) } label: {
                    HStack(spacing: 8) {
                        if let tint {
                            Image(systemName: tint == UY.green ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(tint)
                        }
                        Text(question.choices[i]).multilineTextAlignment(.center)
                    }
                    .font(UY.subheadline)
                    .foregroundStyle(UY.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous)
                        .fill((tint ?? UY.ink).opacity(tint == nil ? 0.07 : 0.2)))
                    .overlay(RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous)
                        .strokeBorder(tint ?? .clear, lineWidth: 1.5))
                    .opacity(picked != nil && tint == nil ? 0.55 : 1)
                }
                .buttonStyle(UYPressStyle(radius: UY.radiusField))
                .allowsHitTesting(picked == nil)
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
    }

    private func color(for choice: Int, in question: QuizQuestion) -> Color? {
        guard let picked else { return nil }
        if choice == question.answer { return UY.green }
        return choice == picked ? UY.danger : nil
    }

    private func pick(_ choice: Int) {
        let question = quiz[step]
        withAnimation(UY.ease(0.25)) {
            picked = choice
            if choice == question.answer {
                score += 1
            } else if !document.info.quizMisses.contains(question.question) {
                // Gardée pour les points faibles (30 au plus).
                document.info.quizMisses = Array((document.info.quizMisses + [question.question]).suffix(30))
            }
        }
    }

    private func generate() {
        task.run {
            let text = try await AI.text(AIRequest(system: AssistPrompt.quiz,
                                                   user: AssistPrompt.lesson(editor.lessonMarkdown, context: editor.context),
                                                   maxTokens: 8000))
            let questions = try AI.json([QuizQuestion].self, from: text).filter { $0.choices.indices.contains($0.answer) }
            guard !questions.isEmpty else { throw AIError.empty }
            quiz = questions
            step = 0; score = 0; picked = nil
        }
    }
}

// MARK: - Oral blanc

/// L'IA pose une question à voix haute, l'élève répond au micro, l'IA note et commente la réponse.
private struct OralTab: View {
    enum Stage: Equatable { case idle, asking, preparing, answering, grading, graded(note: Int, feedback: String) }

    @ObservedObject var document: EZDocument
    let editor: EditorController
    @StateObject private var task = RevisionTask()
    @State private var stage = Stage.idle
    @State private var cardID: UUID?
    @State private var answer = ""
    @State private var partial = ""
    @State private var recorder: LectureRecorder?
    @State private var voice = AVSpeechSynthesizer()

    private var card: Flashcard? { document.info.cards.first { $0.id == cardID } }

    var body: some View {
        VStack(spacing: UY.space18) {
            if task.loading && document.info.cards.isEmpty {
                RevisionLoading(text: "\(AI.authorName) prépare les questions…")
            } else if stage == .idle || card == nil {
                RevisionEmptyState(symbol: "person.wave.2.fill", title: "Oral blanc",
                                   text: "\(AI.authorName) te pose une question à voix haute. Tu réponds au micro comme à un oral, puis tu reçois une note sur 10 et un retour sur ta réponse.",
                                   action: "Commencer", run: next)
            } else if let card {
                VStack(spacing: UY.space14) {
                    Text(card.question).font(UY.title3).multilineTextAlignment(.center)
                        .padding(UY.space22)
                        .frame(maxWidth: .infinity)
                        .uyGlass(radius: UY.radiusPanel)
                    Button { speak(card.question) } label: { Label("Réécouter la question", systemImage: "speaker.wave.2") }
                        .buttonStyle(.glass)
                    stageView(card)
                }
            }
            if let failure = task.failure {
                Text(failure).font(UY.footnote).foregroundStyle(UY.danger).multilineTextAlignment(.center)
            }
        }
        .onDisappear {
            voice.stopSpeaking(at: .immediate)
            if let recorder { Task { await recorder.stop() } }
        }
    }

    @ViewBuilder
    private func stageView(_ card: Flashcard) -> some View {
        switch stage {
        case .asking:
            Button { startAnswer() } label: { Label("Répondre au micro", systemImage: "mic.fill") }
                .buttonStyle(.glassProminent).tint(UY.claude).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        case .preparing:
            RevisionLoading(text: "Préparation du micro…")
        case .answering:
            Text(answer + (partial.isEmpty ? "" : " " + partial))
                .font(UY.body).foregroundStyle(UY.ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 60)
                .overlay { if answer.isEmpty && partial.isEmpty { Text("Parle, je t'écoute…").foregroundStyle(UY.inkSecondary) } }
            Button { finishAnswer(card) } label: { Label("J'ai fini", systemImage: "stop.fill") }
                .buttonStyle(.glassProminent).tint(UY.danger).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        case .grading:
            RevisionLoading(text: "\(AI.authorName) corrige ta réponse…")
        case .graded(let note, let feedback):
            Text("\(note) / 10").font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(note >= 6 ? UY.green : UY.danger)
            Text(feedback).font(UY.subheadline).foregroundStyle(UY.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Réponse attendue : \(card.answer)").font(UY.footnote).foregroundStyle(UY.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Question suivante", action: next)
                .buttonStyle(.glassProminent).tint(UY.claude).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        case .idle:
            EmptyView()
        }
    }

    private func next() {
        task.run {
            if document.info.cards.isEmpty { try await editor.generateCards(into: document) }
            // D'abord les fiches à revoir, sinon une au hasard.
            let pool = document.info.dueCards().isEmpty ? document.info.cards : document.info.dueCards()
            cardID = pool.filter { $0.id != cardID }.randomElement()?.id ?? pool.first?.id
            answer = ""; partial = ""
            stage = .asking
            if let card { speak(card.question) }
        }
    }

    private func speak(_ text: String) {
        voice.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.hasPrefix("en") ? "en-US" : "fr-FR")
        voice.speak(utterance)
    }

    private func startAnswer() {
        voice.stopSpeaking(at: .immediate)
        let recorder = LectureRecorder()
        recorder.onVolatile = { partial = $0 }
        recorder.onFinal = { text, _, _ in answer += (answer.isEmpty ? "" : " ") + text; partial = "" }
        self.recorder = recorder
        stage = .preparing
        Task { @MainActor in
            do {
                try await recorder.start(vocabulary: editor.context.vocabulary, audioURL: nil)
                stage = .answering
            } catch {
                task.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stage = .asking
            }
        }
    }

    private func finishAnswer(_ card: Flashcard) {
        stage = .grading
        Task { @MainActor in
            await recorder?.stop()
            recorder = nil
            let said = (answer + " " + partial).trimmingCharacters(in: .whitespaces)
            struct Grade: Decodable { let note: Int; let retour: String }
            do {
                let text = try await AI.text(AIRequest(system: AssistPrompt.oralGrade,
                                                       user: AssistPrompt.oralMessage(question: card.question, expected: card.answer,
                                                                                      answer: said, context: editor.context),
                                                       webSearch: false, maxTokens: 1500))
                let grade = try AI.json(Grade.self, from: text)
                let note = max(0, min(10, grade.note))
                if let index = document.info.cards.firstIndex(where: { $0.id == card.id }) {
                    document.info.cards[index].review(knew: note >= 6, examDate: document.info.examDate)
                }
                stage = .graded(note: note, feedback: grade.retour)
                speak(grade.retour)
            } catch {
                task.failure = (error as? LocalizedError)?.errorDescription ?? "La correction n'a pas pu être lue. Réessaie."
                stage = .asking
            }
        }
    }
}

// MARK: - Points faibles

/// Fiches souvent ratées et questions de quiz manquées, avec un accès direct au passage du cours.
private struct WeakPointsTab: View {
    @ObservedObject var document: EZDocument
    let editor: EditorController
    let close: () -> Void

    private var weakCards: [Flashcard] {
        document.info.cards.filter { $0.lapses > 0 }.sorted { $0.lapses > $1.lapses }.prefix(12).map { $0 }
    }

    var body: some View {
        if weakCards.isEmpty && document.info.quizMisses.isEmpty {
            RevisionEmptyState(symbol: "checkmark.seal", title: "Aucun point faible pour l'instant",
                               text: "Les fiches que tu rates et les questions de quiz manquées apparaîtront ici, avec le passage du cours à relire.",
                               action: "D'accord", run: {})
        } else {
            ScrollView {
                VStack(spacing: UY.space8) {
                    ForEach(weakCards) { card in
                        row(title: card.question, detail: card.answer,
                            badge: "ratée \(card.lapses) fois", query: card.question + " " + card.answer)
                    }
                    ForEach(document.info.quizMisses.reversed(), id: \.self) { question in
                        row(title: question, detail: nil, badge: "quiz", query: question)
                    }
                    if !document.info.quizMisses.isEmpty {
                        Button("Effacer les questions de quiz ratées") { document.info.quizMisses = [] }
                            .buttonStyle(.glass)
                            .padding(.top, UY.space8)
                    }
                }
                .padding(.horizontal, 2)
            }
            .uyEdgeFade(14)
        }
    }

    private func row(title: String, detail: String?, badge: String, query: String) -> some View {
        VStack(spacing: 6) {
            Text(badge).font(UY.caption).foregroundStyle(UY.claudeStrong)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(UY.claude.opacity(0.14)))
            Text(title).font(UY.headline).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(UY.footnote).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
            }
            HStack(spacing: UY.space8) {
                Button("Voir dans le cours") {
                    close()
                    editor.reveal(matching: query)
                }
                .buttonStyle(.glass)
                Button("M'expliquer") {
                    editor.questionPassage = query
                    editor.tool = .question
                }
                .buttonStyle(.glassProminent).tint(UY.claude)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(UY.space14)
        .background(RoundedRectangle(cornerRadius: UY.radiusTile, style: .continuous).fill(UY.track.opacity(0.6)))
    }
}

// MARK: - Planning

/// Date de l'examen et répartition des fiches à revoir jour par jour.
private struct PlanTab: View {
    @ObservedObject var document: EZDocument
    @AppStorage(ReviewReminders.defaultsKey) private var reminders = false

    private var days: [(day: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let last = document.info.examDate.map { calendar.startOfDay(for: $0) } ?? today.addingTimeInterval(13 * 86_400)
        let span = max(0, min(45, calendar.dateComponents([.day], from: today, to: last).day ?? 0))
        return (0...span).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let count = document.info.cards.filter {
                offset == 0 ? $0.due < day.addingTimeInterval(86_400) : calendar.isDate($0.due, inSameDayAs: day)
            }.count
            return (day, count)
        }
    }

    var body: some View {
        VStack(spacing: UY.space14) {
            HStack(spacing: UY.space12) {
                Toggle("Examen", isOn: Binding(get: { document.info.examDate != nil }, set: { on in
                    setExam(on ? Calendar.current.date(byAdding: .day, value: 14, to: .now) : nil)
                }))
                .toggleStyle(.switch).tint(UY.claude)
                if let exam = document.info.examDate {
                    DatePicker("", selection: Binding(get: { exam }, set: { setExam($0) }), in: Date.now..., displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }
            Toggle("Me rappeler chaque matin les fiches à revoir", isOn: $reminders)
                .toggleStyle(.switch).tint(UY.claude)
                .font(UY.subheadline)
                .onChange(of: reminders) { _, on in if on { ReviewReminders.enable() } else { ReviewReminders.disable() } }

            if document.info.cards.isEmpty {
                Text("Crée d'abord des fiches (onglet Fiches) : le planning les répartit jusqu'à l'examen.")
                    .font(UY.footnote).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
            } else {
                let maxCount = max(1, days.map(\.count).max() ?? 1)
                ScrollView {
                    VStack(spacing: 6) {
                        Color.clear.frame(height: 8)   // hors du fondu du haut
                        ForEach(days, id: \.day) { entry in
                            let isExam = document.info.examDate.map { Calendar.current.isDate($0, inSameDayAs: entry.day) } ?? false
                            HStack(spacing: UY.space12) {
                                Text(entry.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(UY.footnote.weight(.semibold))
                                    .frame(width: 110, alignment: .trailing)
                                GeometryReader { geo in
                                    Capsule().fill(isExam ? UY.danger : UY.claude)
                                        .frame(width: max(entry.count > 0 ? 8 : 0, geo.size.width * CGFloat(entry.count) / CGFloat(maxCount)))
                                }
                                .frame(height: 12)
                                Text(isExam ? "Examen" : (entry.count == 0 ? "—" : "\(entry.count) fiche\(entry.count > 1 ? "s" : "")"))
                                    .font(UY.footnote)
                                    .foregroundStyle(isExam ? UY.danger : UY.inkSecondary)
                                    .frame(width: 80, alignment: .leading)
                            }
                        }
                    }
                }
                .uyEdgeFade(14)
            }
        }
    }

    /// Avec une date d'examen, aucune fiche n'est programmée après la veille.
    private func setExam(_ date: Date?) {
        document.info.examDate = date
        guard let date else { return }
        let eve = Calendar.current.startOfDay(for: date).addingTimeInterval(-86_400 + 8 * 3600)
        guard eve > .now else { return }
        for index in document.info.cards.indices where document.info.cards[index].due > eve {
            document.info.cards[index].due = eve
        }
    }
}
