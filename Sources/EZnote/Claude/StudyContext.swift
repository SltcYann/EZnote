import Foundation

/// Tout ce que l'IA (et la dictée) sait de l'élève et du cours : réglages « Mes études » + contexte du document.
struct StudyContext {
    var title: String?
    var subject = ""
    var course = ""
    var level = UserDefaults.standard.string(forKey: "studyLevel") ?? ""
    var studies = UserDefaults.standard.string(forKey: "studyField") ?? ""
    var aboutMe = UserDefaults.standard.string(forKey: "studyContext") ?? ""

    init(title: String?, info: DocumentInfo) {
        // Un nom de fichier par défaut (date, « Sans titre ») n'apprend rien sur la matière.
        let generic = title.map { $0.hasPrefix("Sans titre") || $0.hasPrefix("Untitled") || $0.first?.isNumber == true } ?? true
        self.title = generic ? nil : title
        subject = info.subject
        course = info.context
    }

    /// Bloc à placer en tête du message à l'IA (vide s'il n'y a rien à dire).
    var promptBlock: String {
        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            lines.append("\(label) : \(value)")
        }
        add("Titre du document", title)
        add("Matière", subject)
        add("Contexte du cours", course)
        add("Niveau d'études de l'élève", level)
        add("Études de l'élève", studies)
        add("Ce que l'élève dit de lui", aboutMe)
        return lines.isEmpty ? "" : "<contexte>\n" + lines.joined(separator: "\n") + "\n</contexte>\n\n"
    }

    /// Mots du contexte qui aident la dictée à reconnaître le vocabulaire du cours (noms propres, termes techniques).
    var vocabulary: [String] {
        let text = [subject, course, aboutMe, studies, title ?? ""].joined(separator: " ")
        let words = text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-'")).inverted)
        let useful = words.filter { $0.count >= 4 || ($0.count >= 2 && $0.first?.isUppercase == true) }
        var seen = Set<String>()
        return useful.filter { seen.insert($0.lowercased()).inserted }.prefix(100).map { $0 }
    }
}

/// Consignes communes à toutes les demandes faites à l'IA.
enum SharedPrompt {
    static let context = """
    Le bloc <contexte> décrit l'élève et le cours : sers-t'en pour comprendre les abréviations, le vocabulaire \
    et le niveau attendu, et pour choisir des exemples adaptés. Si tu disposes de la recherche web et que le \
    contexte cite une école, une formation, un programme, un cours, un professeur ou un livre, tu peux chercher \
    sur le web pour mieux comprendre ce contexte (programme, niveau, vocabulaire du domaine) avant de répondre.

    Formules : écris-les en Unicode lisible (x², H₂O, √, ∑, ∫, α, ≤, →) ; pour une formule complexe, utilise \
    du LaTeX simple entre $…$, que l'application convertit.
    """
}
