import AppKit
import SwiftUI

/// Bibliothèque (⇧⌘L) : les cours du dossier, rangés par matière, avec une recherche dans tous les textes,
/// une question en langage naturel à l'IA, et la fusion de plusieurs cours en un chapitre.
struct LibraryView: View {
    @AppStorage(SaveFolder.defaultsKey) private var folder = ""
    @State private var items: [LibraryItem] = []
    @State private var filter = LibraryView.all
    @State private var search = ""
    @State private var loading = false
    @State private var selection = Set<URL>()
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable { case ask, merge; var id: String { rawValue } }

    private static let all = "\u{0}tous"
    private static let due = "\u{0}réviser"
    private static let none = "Sans matière"

    private var subjects: [String] {
        Set(items.map { $0.subject.isEmpty ? Self.none : $0.subject }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var shown: [LibraryItem] {
        items.filter { item in
            let inFilter: Bool
            switch filter {
            case Self.all: inFilter = true
            case Self.due: inFilter = item.dueCards > 0
            default: inFilter = (item.subject.isEmpty ? Self.none : item.subject) == filter
            }
            return inFilter && (search.isEmpty || [item.title, item.subject, item.text].contains { $0.localizedStandardContains(search) })
        }
        .sorted { $0.modified > $1.modified }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Label("Tous les cours", systemImage: "books.vertical").tag(Self.all)
                Label("À réviser aujourd'hui", systemImage: "rectangle.on.rectangle.angled")
                    .badge(items.reduce(0) { $0 + $1.dueCards })
                    .tag(Self.due)
                Section("Matières") {
                    ForEach(subjects, id: \.self) { name in
                        Label(name, systemImage: "book.closed")
                            .badge(items.filter { ($0.subject.isEmpty ? Self.none : $0.subject) == name }.count)
                            .tag(name)
                    }
                }
            }
            .tint(UY.claude)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            Group {
                if folder.isEmpty {
                    placeholder(symbol: "folder.badge.questionmark", title: "Choisis le dossier de tes cours",
                                text: "La bibliothèque montre les documents EZnote de ton dossier de sauvegarde (Réglages › Général).",
                                action: ("Choisir un dossier…", { if SaveFolder.choose() != nil { reload() } }))
                } else if shown.isEmpty && !loading {
                    placeholder(symbol: search.isEmpty ? "tray" : "magnifyingglass", title: search.isEmpty ? "Aucun cours ici" : "Aucun résultat",
                                text: search.isEmpty ? "Les documents enregistrés dans \((folder as NSString).abbreviatingWithTildeInPath) apparaîtront ici."
                                    : "Essaie un autre mot, ou pose ta question à l'IA (bouton ✦).",
                                action: nil)
                } else {
                    List(shown, selection: $selection) { item in
                        LibraryRow(item: item, search: search).tag(item.url)
                    }
                    .scrollContentBackground(.hidden)
                    .contextMenu(forSelectionType: URL.self) { urls in
                        Button("Ouvrir") { urls.forEach(open) }
                        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
                        if urls.count >= 2 {
                            Button("Fusionner en un chapitre…") { selection = urls; sheet = .merge }
                        }
                    } primaryAction: { urls in
                        urls.forEach(open)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MeshBackground(mood: .calm).opacity(0.5))
            .searchable(text: $search, placement: .toolbar, prompt: "Chercher dans tous les cours")
            .toolbar {
                ToolbarItem {
                    Button { sheet = .ask } label: { UYSymbol(name: "sparkles", size: 13) }
                        .help("Poser une question sur tous tes cours (« où le prof a parlé de… ? »)")
                        .disabled(items.isEmpty)
                }
                ToolbarItem {
                    Button { sheet = .merge } label: { UYSymbol(name: "square.stack.3d.up", size: 13) }
                        .help("Fusionner plusieurs cours en un chapitre")
                        .disabled(items.count < 2)
                }
                ToolbarItem {
                    Button { reload() } label: { UYSymbol(name: "arrow.clockwise", size: 13) }
                        .help("Actualiser")
                }
            }
        }
        .navigationTitle("Bibliothèque")
        .frame(minWidth: 820, minHeight: 600)
        .task(id: folder) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .ask: AskLibraryView(items: items, open: open)
            case .merge: MergeView(items: items, initial: Set(selection.count >= 2 ? selection : Set(shown.map(\.url))),
                                   open: open, done: reload)
            }
        }
    }

    private func placeholder(symbol: String, title: String, text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: UY.space14) {
            UYSymbol(name: symbol, size: 30).foregroundStyle(UY.claude)
            Text(title).font(UY.title3)
            Text(text).font(UY.subheadline).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.glassProminent).tint(UY.claude).controlSize(.large)
            }
        }
        .frame(maxWidth: 420)
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func reload() {
        loading = true
        Task.detached(priority: .userInitiated) {
            let found = LibraryIndex.scan()
            await MainActor.run {
                items = found
                selection = selection.filter { url in found.contains { $0.url == url } }
                loading = false
            }
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let search: String

    /// Extrait du texte autour du mot cherché (ou le début du cours), sur une ligne.
    private var snippet: String {
        let text = item.text
            .replacingOccurrences(of: #"[\t\n\u{FFFC}]+|[•◦▪]\s"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty, let range = text.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(140))
        }
        let start = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }

    var body: some View {
        HStack(spacing: UY.space14) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 22))
                .foregroundStyle(UY.claude)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title).font(UY.headline)
                    if !item.subject.isEmpty {
                        Text(item.subject).font(UY.caption).foregroundStyle(UY.claudeStrong)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(UY.claude.opacity(0.14)))
                    }
                    Spacer()
                    Text(item.modified.formatted(date: .abbreviated, time: .omitted)).font(UY.caption).foregroundStyle(UY.inkTertiary)
                }
                Text(snippet).font(UY.footnote).foregroundStyle(UY.inkSecondary).lineLimit(2)
                HStack(spacing: UY.space12) {
                    if item.dueCards > 0 {
                        Label("\(item.dueCards) fiche\(item.dueCards > 1 ? "s" : "") à réviser", systemImage: "rectangle.on.rectangle.angled")
                    }
                    if let exam = item.info.examDate, exam > .now {
                        Label("Examen \(exam.formatted(.relative(presentation: .named)))", systemImage: "calendar")
                    }
                }
                .font(UY.caption)
                .foregroundStyle(UY.claudeStrong)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Question sur tous les cours

/// « Où le prof a parlé de la souveraineté ? » : l'IA lit tous les cours et renvoie les passages concernés.
private struct AskLibraryView: View {
    struct Answer: Decodable, Identifiable {
        var id: String { cours + passage }
        let cours: String
        let passage: String
        let explication: String
    }

    let items: [LibraryItem]
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answers: [Answer]?
    @StateObject private var task = RevisionTask()

    var body: some View {
        VStack(spacing: UY.space14) {
            Text("Demander à \(AI.authorName)").font(UY.headline)
            Text("Pose une question sur l'ensemble de tes cours : l'IA retrouve les passages qui en parlent.")
                .font(UY.footnote).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
            GlassField(placeholder: "Ex. Où le prof a parlé de la souveraineté ?", text: $question)
                .onSubmit(ask)
            Group {
                if task.loading {
                    RevisionLoading(text: "\(AI.authorName) parcourt tes \(items.count) cours…")
                } else if let answers, answers.isEmpty {
                    Text("Aucun cours n'en parle.").font(UY.subheadline).foregroundStyle(UY.inkSecondary)
                } else if let answers {
                    ScrollView {
                        VStack(spacing: UY.space8) {
                            ForEach(answers) { answer in
                                VStack(spacing: 6) {
                                    Text(answer.cours).font(UY.headline).foregroundStyle(UY.claudeStrong)
                                    Text("« \(answer.passage) »").font(UY.footnote).italic().multilineTextAlignment(.center)
                                    Text(answer.explication).font(UY.footnote).foregroundStyle(UY.inkSecondary)
                                        .multilineTextAlignment(.center)
                                    if let item = items.first(where: { $0.title == answer.cours }) {
                                        Button("Ouvrir le cours") { open(item.url); dismiss() }
                                            .buttonStyle(.glass).controlSize(.small)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(UY.space14)
                                .background(RoundedRectangle(cornerRadius: UY.radiusTile, style: .continuous).fill(UY.track.opacity(0.6)))
                            }
                        }
                    }
                    .uyEdgeFade(14)
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let failure = task.failure { Text(failure).font(UY.footnote).foregroundStyle(UY.danger) }
            HStack(spacing: UY.space12) {
                Button("Fermer") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Demander", action: ask).buttonStyle(.glassProminent).tint(UY.claude)
                    .keyboardShortcut(.defaultAction)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || task.loading)
            }
            .controlSize(.large)
        }
        .padding(UY.space24)
        .frame(width: 600, height: 560)
        .uyMakeKeyOnAppear()
        .onExitCommand { dismiss() }
    }

    private func ask() {
        let question = question
        task.run {
            // Les cours les plus récents d'abord, 12 000 caractères au plus chacun, 150 000 en tout.
            var corpus = "", budget = 150_000
            for item in items.sorted(by: { $0.modified > $1.modified }) where budget > 0 {
                let text = String(item.text.prefix(min(12_000, budget)))
                budget -= text.count
                corpus += "<cours titre=\"\(item.title)\" matiere=\"\(item.subject)\">\n\(text)\n</cours>\n\n"
            }
            let reply = try await AI.text(AIRequest(system: AssistPrompt.librarySearch,
                                                    user: corpus + "Ma question : \(question)", webSearch: false, maxTokens: 4000))
            answers = try AI.json([Answer].self, from: reply)
        }
    }
}

// MARK: - Fusion de cours

/// Plusieurs cours d'une même matière deviennent un chapitre unique, sans doublons, enregistré à côté.
private struct MergeView: View {
    let all: [LibraryItem]
    let open: (URL) -> Void
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var markdown = ""
    @State private var writing = false
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var chosen: Set<URL>

    init(items: [LibraryItem], initial: Set<URL>, open: @escaping (URL) -> Void, done: @escaping () -> Void) {
        all = items.sorted { $0.modified > $1.modified }
        self.open = open
        self.done = done
        _chosen = State(initialValue: initial)
    }

    private var items: [LibraryItem] { all.filter { chosen.contains($0.url) } }

    var body: some View {
        VStack(spacing: UY.space14) {
            Text("Fusionner en un chapitre").font(UY.headline)
            if markdown.isEmpty && !writing {
                Text("Coche les cours à réunir : \(AI.authorName) en fait une seule leçon structurée, sans répétitions ; les ajouts de l'IA restent dans leurs contours.")
                    .font(UY.subheadline).foregroundStyle(UY.inkSecondary).multilineTextAlignment(.center)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(all) { item in
                            Toggle(isOn: Binding(get: { chosen.contains(item.url) },
                                                 set: { on in if on { chosen.insert(item.url) } else { chosen.remove(item.url) } })) {
                                HStack {
                                    Text(item.title).font(UY.subheadline)
                                    if !item.subject.isEmpty {
                                        Text(item.subject).font(UY.caption).foregroundStyle(UY.claudeStrong)
                                    }
                                    Spacer()
                                    Text(item.modified.formatted(date: .abbreviated, time: .omitted))
                                        .font(UY.caption).foregroundStyle(UY.inkTertiary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .tint(UY.claude)
                            .padding(.horizontal, UY.space14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous).fill(UY.track.opacity(0.6)))
                        }
                    }
                }
                .uyEdgeFade(12)
            } else {
                RenderedText(markdown: LessonRenderer.extractSubject(markdown).lesson)
                    .uyGlass(radius: UY.radiusTile)
                    .overlay { if markdown.isEmpty { RevisionLoading(text: "\(AI.authorName) lit tes cours…") } }
            }
            if let failure { Text(failure).font(UY.footnote).foregroundStyle(UY.danger) }
            HStack(spacing: UY.space12) {
                Button("Annuler") { task?.cancel(); dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                if !markdown.isEmpty && !writing {
                    Button("Créer le chapitre", action: save).buttonStyle(.glassProminent).tint(UY.claude)
                } else {
                    Button("Fusionner", action: merge).buttonStyle(.glassProminent).tint(UY.claude)
                        .disabled(writing || items.count < 2)
                }
            }
            .controlSize(.large)
        }
        .padding(UY.space24)
        .frame(width: 680, height: 640)
        .uyMakeKeyOnAppear()
        .onExitCommand { task?.cancel(); dismiss() }
        .onDisappear { task?.cancel() }
    }

    private var subject: String {
        let subjects = Set(items.map(\.subject).filter { !$0.isEmpty })
        return subjects.count == 1 ? subjects.first! : ""
    }

    private func merge() {
        writing = true
        failure = nil
        markdown = ""
        let lessons = items.sorted { $0.modified < $1.modified }.compactMap { item -> String? in
            guard let data = try? Data(contentsOf: item.url), let (text, _) = try? NoteFile.read(data, type: .ezNote) else { return nil }
            // Les images ne sont pas envoyées : on retire leurs marqueurs.
            let notes = NotesExporter.markdown(from: text)
                .replacingOccurrences(of: #"\[(Image|Diapos) [^\]]*\]"#, with: "", options: .regularExpression)
            return "<cours titre=\"\(item.title)\">\n\(notes)\n</cours>"
        }
        var context = StudyContext(title: nil, info: DocumentInfo(subject: subject))
        context.title = subject.isEmpty ? nil : "Chapitre de \(subject)"
        let request = AIRequest(system: AssistPrompt.merge, user: context.promptBlock + lessons.joined(separator: "\n\n"))
        task = Task { @MainActor in
            do {
                for try await event in try AI.stream(request) {
                    if case .text(let delta) = event { markdown += delta }
                    if case .restart = event { markdown = "" }
                }
            } catch {
                if !(error is CancellationError) { failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
            writing = false
        }
    }

    private func save() {
        guard let folder = SaveFolder.url else { return }
        let (detected, lesson) = LessonRenderer.extractSubject(markdown)
        let text = LessonRenderer.render(lesson, author: AI.authorName)
        let info = DocumentInfo(subject: subject.isEmpty ? (detected ?? "") : subject)
        let date = Date.now.formatted(.dateTime.day().month(.wide).year())
        var url = folder.appendingPathComponent("Chapitre – \(info.subject.isEmpty ? "cours" : info.subject) – \(date).eznote")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Chapitre – \(info.subject.isEmpty ? "cours" : info.subject) – \(date) (\(n)).eznote")
            n += 1
        }
        do {
            try NoteFile.write(NoteSnapshot(text: text, info: info), type: .ezNote).write(to: url)
            done()
            open(url)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
