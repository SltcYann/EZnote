import AppKit
import Foundation

/// Une demande à l'IA, quel que soit le moteur (abonnement Claude, clé API, modèle local).
struct AIRequest {
    var system: String
    var user: String
    /// Photos du tableau, diapos… (JPEG), placées avant le texte.
    var images: [Data] = []
    var webSearch = AI.webSearchAllowed
    /// Réponse longue (leçon) ou courte (question, quiz).
    var maxTokens = 32000
}

enum AIEvent {
    case searching
    case text(String)
    /// Un modèle de secours reprend la réponse depuis le début : le texte reçu jusque-là est à jeter.
    case restart
}

enum AIError: LocalizedError {
    case needsAPIKey
    case empty

    var errorDescription: String? {
        switch self {
        case .needsAPIKey: return "Ajoute ta clé API Anthropic dans les Réglages (⌘,)."
        case .empty: return "L'IA n'a renvoyé aucun texte. Réessaie."
        }
    }
}

/// Point d'entrée unique vers l'IA choisie dans les Réglages.
enum AI {
    static var connection: ClaudeConnection { .current }

    static var webSearchAllowed: Bool { UserDefaults.standard.object(forKey: "webSearch") as? Bool ?? true }

    /// Nom affiché sur les ajouts et dans la capsule d'état.
    static var authorName: String { connection == .local ? LocalModelClient.displayName : "Claude" }

    static func stream(_ request: AIRequest) throws -> AsyncThrowingStream<AIEvent, Error> {
        switch connection {
        case .subscription:
            return ClaudeCodeClient().stream(request)
        case .apiKey:
            guard let key = Keychain.apiKey, !key.isEmpty else { throw AIError.needsAPIKey }
            return ClaudeClient(apiKey: key).stream(request)
        case .local:
            return LocalModelClient().stream(request)
        }
    }

    /// Réponse complète d'un coup (quiz, fiches, réponses courtes).
    static func text(_ request: AIRequest) async throws -> String {
        var output = ""
        for try await event in try stream(request) {
            switch event {
            case .text(let delta): output += delta
            case .restart: output = ""
            case .searching: break
            }
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.empty }
        return output
    }

    /// Extrait le premier objet ou tableau JSON d'une réponse (les modèles l'entourent parfois de ```json).
    static func json<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let starts = [text.firstIndex(of: "{"), text.firstIndex(of: "[")].compactMap { $0 }
        let ends = [text.lastIndex(of: "}"), text.lastIndex(of: "]")].compactMap { $0 }
        guard let start = starts.min(), let end = ends.max(), start < end else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try JSONDecoder().decode(T.self, from: Data(text[start...end].utf8))
    }

    /// Image prête à envoyer : JPEG de 1568 px au plus (taille conseillée pour Claude).
    static func jpeg(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 1568 / CGFloat(max(cg.width, cg.height)))
        let width = Int(CGFloat(cg.width) * scale), height = Int(CGFloat(cg.height) * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
