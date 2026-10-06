import Foundation

/// Un cours enregistré dans le dossier de sauvegarde.
struct LibraryItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let title: String
    let info: DocumentInfo
    let modified: Date
    let text: String

    var subject: String { info.subject }
    var dueCards: Int { info.dueCards().count }

    static func == (a: LibraryItem, b: LibraryItem) -> Bool { a.url == b.url && a.modified == b.modified }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

/// Lecture des cours du dossier de sauvegarde (bibliothèque, liens entre cours, rappels).
enum LibraryIndex {
    static func scan() -> [LibraryItem] {
        guard let root = SaveFolder.url else { return [] }
        var found: [LibraryItem] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "eznote", let summary = NoteFile.summary(of: url) else { continue }
            let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            found.append(LibraryItem(url: url, title: url.deletingPathExtension().lastPathComponent,
                                     info: summary.info, modified: modified, text: summary.text))
        }
        return found
    }

    /// Les autres cours qui parlent de `term` (sans tenir compte des accents ni des majuscules).
    static func courses(mentioning term: String, excluding url: URL?) -> [LibraryItem] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 3 else { return [] }
        return scan().filter { $0.url != url && $0.text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.modified > $1.modified }
    }
}
