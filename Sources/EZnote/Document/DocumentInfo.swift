import Foundation

/// Ce que le document sait de son cours, en plus du texte. Les champs ajoutés au fil des versions sont
/// lus avec une valeur par défaut, pour ouvrir les anciens fichiers.
struct DocumentInfo: Codable, Equatable {
    /// Niveau d'explication voulu pour la leçon.
    enum Depth: String, Codable, CaseIterable {
        case simple, normal, deep

        var label: String {
            switch self {
            case .simple: return "Simple"
            case .normal: return "Normal"
            case .deep: return "Approfondi"
            }
        }
    }

    /// Matière (« Droit constitutionnel »), saisie ou déduite par l'IA. Sert aussi à ranger la bibliothèque.
    var subject = ""
    /// Contexte du cours écrit par l'élève (« Cours de M. Durand, chapitre 3… »).
    var context = ""
    /// Fiches de révision, avec leur calendrier de révision espacée.
    var cards: [Flashcard] = []
    var depth = Depth.normal
    /// Date de l'examen : les révisions sont réparties pour que tout soit vu avant.
    var examDate: Date?
    /// Questions de quiz ratées (pour les points faibles).
    var quizMisses: [String] = []

    init(subject: String = "", context: String = "") {
        self.subject = subject
        self.context = context
    }

    private enum Keys: String, CodingKey { case subject, context, cards, depth, examDate, quizMisses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        cards = try c.decodeIfPresent([Flashcard].self, forKey: .cards) ?? []
        depth = try c.decodeIfPresent(Depth.self, forKey: .depth) ?? .normal
        examDate = try c.decodeIfPresent(Date.self, forKey: .examDate)
        quizMisses = try c.decodeIfPresent([String].self, forKey: .quizMisses) ?? []
    }

    /// Fiches à réviser à une date donnée (aujourd'hui par défaut).
    func dueCards(on day: Date = .now) -> [Flashcard] {
        let end = Calendar.current.startOfDay(for: day).addingTimeInterval(86_400)
        return cards.filter { $0.due < end }
    }
}

/// Une fiche question / réponse, révisée selon le système de Leitner (boîtes 0 à 5).
struct Flashcard: Codable, Equatable, Identifiable {
    var id = UUID()
    var question: String
    var answer: String
    var box = 0
    var due = Date.now
    /// Nombre de fois où la fiche a été ratée : sert aux points faibles.
    var lapses = 0

    /// Intervalle avant la prochaine révision pour chaque boîte, en jours.
    static let intervals: [Double] = [0, 1, 3, 7, 16, 35]

    init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }

    private enum Keys: String, CodingKey { case id, question, answer, box, due, lapses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        question = try c.decode(String.self, forKey: .question)
        answer = try c.decode(String.self, forKey: .answer)
        box = try c.decodeIfPresent(Int.self, forKey: .box) ?? 0
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? .now
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
    }

    /// Une fiche sue revient de plus en plus tard, une fiche ratée revient tout de suite. Avec une date
    /// d'examen, la prochaine révision tombe au plus tard la veille de l'examen.
    mutating func review(knew: Bool, examDate: Date? = nil) {
        box = knew ? min(box + 1, Self.intervals.count - 1) : 0
        if !knew { lapses += 1 }
        var next = Date.now.addingTimeInterval(Self.intervals[box] * 86_400)
        if let examDate {
            let eve = Calendar.current.startOfDay(for: examDate).addingTimeInterval(-86_400 + 8 * 3600)
            if eve > .now { next = min(next, eve) }
        }
        due = next
    }
}
