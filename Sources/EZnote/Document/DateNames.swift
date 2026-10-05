import AppKit
import ObjectiveC

/// Un document pas encore enregistré s'appelle comme la date du jour (« 5 octobre 2026 ») au lieu de
/// « Sans titre » : c'est le titre de la fenêtre et le nom proposé à l'enregistrement. Un deuxième
/// document le même jour devient « 5 octobre 2026 (2) ».
///
/// SwiftUI ne permet pas de choisir ce nom et macOS recalcule « Sans titre » pour un document neuf :
/// on remplace donc `displayName` de NSDocument pour les documents sans fichier.
enum DateNames {
    static func install() { _ = swap }

    private static let swap: Void = {
        guard let original = class_getInstanceMethod(NSDocument.self, #selector(getter: NSDocument.displayName)),
              let replacement = class_getInstanceMethod(NSDocument.self, #selector(NSDocument.ez_displayName))
        else { return }
        method_exchangeImplementations(original, replacement)
    }()

    fileprivate static var key: UInt8 = 0
}

extension NSDocument {
    @objc fileprivate func ez_displayName() -> String {
        let systemName = ez_displayName()   // implémentation d'origine (méthodes échangées)
        guard fileURL == nil else { return systemName }
        if let name = objc_getAssociatedObject(self, &DateNames.key) as? String { return name }

        let today = Date.now.formatted(.dateTime.day().month(.wide).year())
        let taken = Set(NSDocumentController.shared.documents.compactMap {
            $0 === self ? nil : objc_getAssociatedObject($0, &DateNames.key) as? String
        })
        var name = today, n = 2
        while taken.contains(name) { name = "\(today) (\(n))"; n += 1 }
        objc_setAssociatedObject(self, &DateNames.key, name, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        return name
    }
}
