import AppKit
import SwiftUI

/// Un cours du dossier de sauvegarde.
struct LibraryItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let title: String
    let subject: String
    let modified: Date
    let text: String
    let dueCards: Int
}

/// Bibliothèque (⇧⌘L) : les cours du dossier, rangés par matière, avec une recherche dans tous les textes.
struct LibraryView: View {
    @AppStorage(SaveFolder.defaultsKey) private var folder = ""
    @State private var items: [LibraryItem] = []
    @State private var subject = LibraryView.all
    @State private var search = ""
    @State private var loading = false

    private static let all = "\u{0}tous"
    private static let none = "Sans matière"

    private var subjects: [String] {
        Set(items.map { $0.subject.isEmpty ? Self.none : $0.subject }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var shown: [LibraryItem] {
        items.filter { item in
            (subject == Self.all || (item.subject.isEmpty ? Self.none : item.subject) == subject)
                && (search.isEmpty || [item.title, item.subject, item.text].contains { $0.localizedStandardContains(search) })
        }
        .sorted { $0.modified > $1.modified }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $subject) {
                Label("Tous les cours", systemImage: "books.vertical").tag(Self.all)
                Section("Matières") {
                    ForEach(subjects, id: \.self) { name in
                        Label(name, systemImage: "book.closed")
                            .badge(items.filter { ($0.subject.isEmpty ? Self.none : $0.subject) == name }.count)
                            .tag(name)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            Group {
                if folder.isEmpty {
                    placeholder(symbol: "folder.badge.questionmark", title: "Choisis le dossier de tes cours",
                                text: "La bibliothèque montre les documents EZnote de ton dossier de sauvegarde (Réglages › Général).",
                                action: ("Choisir un dossier…", { if SaveFolder.choose() != nil { reload() } }))
                } else if shown.isEmpty && !loading {
                    placeholder(symbol: search.isEmpty ? "tray" : "magnifyingglass", title: search.isEmpty ? "Aucun cours ici" : "Aucun résultat",
                                text: search.isEmpty ? "Les documents enregistrés dans \((folder as NSString).abbreviatingWithTildeInPath) apparaîtront ici." : "Essaie un autre mot.",
                                action: nil)
                } else {
                    List(shown) { item in
                        LibraryRow(item: item, search: search)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { open(item) }
                            .contextMenu {
                                Button("Ouvrir") { open(item) }
                                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MeshBackground(mood: .calm).opacity(0.5))
            .searchable(text: $search, placement: .toolbar, prompt: "Chercher dans tous les cours")
            .toolbar {
                ToolbarItem {
                    Button { reload() } label: { UYSymbol(name: "arrow.clockwise", size: 13) }
                        .help("Actualiser")
                }
            }
        }
        .navigationTitle("Bibliothèque")
        .frame(minWidth: 760, minHeight: 480)
        .task(id: folder) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
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

    private func open(_ item: LibraryItem) {
        NSDocumentController.shared.openDocument(withContentsOf: item.url, display: true) { _, _, _ in }
    }

    private func reload() {
        guard let root = SaveFolder.url else { items = []; return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var found: [LibraryItem] = []
            let keys: [URLResourceKey] = [.contentModificationDateKey]
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "eznote", let summary = NoteFile.summary(of: url) else { continue }
                let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                found.append(LibraryItem(url: url, title: url.deletingPathExtension().lastPathComponent,
                                         subject: summary.info.subject, modified: modified, text: summary.text,
                                         dueCards: summary.info.cards.filter(\.isDue).count))
            }
            let result = found
            await MainActor.run {
                items = result
                loading = false
            }
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let search: String

    /// Extrait du texte autour du mot cherché (ou le début du cours).
    private var snippet: String {
        let text = item.text.replacingOccurrences(of: "\n", with: " ")
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
                        Text(item.subject).font(UY.caption).foregroundStyle(UY.claude)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(UY.claude.opacity(0.14)))
                    }
                    Spacer()
                    Text(item.modified.formatted(date: .abbreviated, time: .omitted)).font(UY.caption).foregroundStyle(UY.inkTertiary)
                }
                Text(snippet).font(UY.footnote).foregroundStyle(UY.inkSecondary).lineLimit(2)
                if item.dueCards > 0 {
                    Label("\(item.dueCards) fiche\(item.dueCards > 1 ? "s" : "") à réviser", systemImage: "rectangle.on.rectangle.angled")
                        .font(UY.caption).foregroundStyle(UY.claude)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
