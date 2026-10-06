import Foundation
import UserNotifications

/// Rappel chaque matin à 8 h : fiches à revoir dans les cours du dossier de sauvegarde, examens qui approchent.
enum ReviewReminders {
    static let defaultsKey = "reviewReminders"
    private static let prefix = "eznote-revision-"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static func enable() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                UserDefaults.standard.set(granted, forKey: defaultsKey)
                reschedule()
            }
        }
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        clear()
    }

    private static func clear() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    /// Recalcule les rappels des 14 prochains jours d'après les cours enregistrés.
    static func reschedule() {
        guard enabled else { return }
        let courses = LibraryIndex.scan()
        clear()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day), fire > .now else { continue }
            let due = courses.reduce(0) { $0 + $1.info.dueCards(on: day).count }
            let exams = courses.compactMap { course -> (String, Int)? in
                guard let exam = course.info.examDate else { return nil }
                let left = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: exam)).day ?? -1
                return (0...7).contains(left) ? (course.subject.isEmpty ? course.title : course.subject, left) : nil
            }
            guard due > 0 || !exams.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = due > 0 ? "\(due) fiche\(due > 1 ? "s" : "") à réviser aujourd'hui" : "Révisions"
            content.body = exams.map { name, left in
                left == 0 ? "Examen de \(name) aujourd'hui, bon courage !" : "Examen de \(name) dans \(left) jour\(left > 1 ? "s" : "")."
            }.joined(separator: " ")
            if content.body.isEmpty { content.body = "Ouvre EZnote pour réviser tes fiches." }
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                                                        repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + "\(offset)", content: content, trigger: trigger))
        }
    }
}
