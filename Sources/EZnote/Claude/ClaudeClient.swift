import Foundation

enum ClaudeError: LocalizedError {
    case http(Int, String)
    case api(String)
    case refusal
    case empty

    var errorDescription: String? {
        switch self {
        case .http(401, _): return "Ta clé API Anthropic est refusée. Vérifie-la dans les Réglages (⌘,)."
        case .http(429, _): return "Trop de demandes d'un coup. Réessaie dans quelques secondes."
        case .http(529, _): return "Claude est très demandé en ce moment. Réessaie dans un instant."
        case .http(let code, let message): return "Erreur \(code) de l'API Claude : \(message)"
        case .api(let message): return "Claude a rencontré une erreur : \(message)"
        case .refusal: return "Claude n'a pas pu transformer ces notes en leçon."
        case .empty: return "Claude n'a renvoyé aucun texte. Réessaie."
        }
    }
}

/// Appel à l'API Messages de Claude en streaming (SSE), avec la recherche web côté serveur.
struct ClaudeClient {
    enum Event {
        case searching
        case text(String)
        /// Un modèle de secours reprend la réponse depuis le début : le texte reçu jusque-là est à jeter.
        case restart
    }

    let apiKey: String
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func lesson(from notes: String, context: LessonPrompt.Context, webSearch: Bool) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let user: [String: Any] = ["role": "user", "content": LessonPrompt.userMessage(notes: notes, context: context)]
                    var assistant: [[String: Any]] = []
                    // Avec la recherche web, le serveur peut mettre le tour en pause (« pause_turn ») :
                    // on renvoie alors la réponse partielle et il reprend là où il s'était arrêté.
                    for _ in 0..<6 {
                        var messages: [[String: Any]] = [user]
                        if !assistant.isEmpty { messages.append(["role": "assistant", "content": assistant]) }
                        let (blocks, stopReason) = try await stream(messages: messages, webSearch: webSearch, continuation: continuation)
                        assistant += blocks
                        switch stopReason {
                        case "pause_turn": continue
                        case "refusal": throw ClaudeError.refusal
                        default: continuation.finish(); return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(messages: [[String: Any]], webSearch: Bool,
                        continuation: AsyncThrowingStream<Event, Error>.Continuation) async throws -> ([[String: Any]], String?) {
        var body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 32000,
            "stream": true,
            "system": LessonPrompt.system,
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "messages": messages,
        ]
        if webSearch {
            body["tools"] = [["type": "web_search_20260209", "name": "web_search", "max_uses": 5]]
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw ClaudeError.http(status, Self.errorMessage(in: data) ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }

        // Les blocs de la réponse sont reconstruits tels quels, pour pouvoir les renvoyer après une pause.
        var blocks: [Int: [String: Any]] = [:]
        var toolInput: [Int: String] = [:]
        var stopReason: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = Data(line.dropFirst(5).utf8)
            guard let event = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            let index = event["index"] as? Int ?? 0

            switch type {
            case "content_block_start":
                guard let block = event["content_block"] as? [String: Any] else { break }
                blocks[index] = block
                switch block["type"] as? String {
                case "server_tool_use": continuation.yield(.searching)
                case "fallback": continuation.yield(.restart)
                default: break
                }
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], var block = blocks[index] else { break }
                switch delta["type"] as? String {
                case "text_delta":
                    let text = delta["text"] as? String ?? ""
                    block["text"] = (block["text"] as? String ?? "") + text
                    continuation.yield(.text(text))
                case "thinking_delta":
                    block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
                case "input_json_delta":
                    toolInput[index, default: ""] += delta["partial_json"] as? String ?? ""
                case "citations_delta":
                    if let citation = delta["citation"] {
                        block["citations"] = (block["citations"] as? [Any] ?? []) + [citation]
                    }
                default: break
                }
                blocks[index] = block
            case "content_block_stop":
                if let json = toolInput.removeValue(forKey: index) {
                    blocks[index]?["input"] = json.isEmpty ? [String: Any]()
                        : (try? JSONSerialization.jsonObject(with: Data(json.utf8))) ?? [String: Any]()
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }
            case "error":
                let error = event["error"] as? [String: Any]
                throw ClaudeError.api(error?["message"] as? String ?? "erreur inconnue")
            default:
                break
            }
        }
        try Task.checkCancellation()
        return (blocks.keys.sorted().compactMap { blocks[$0] }, stopReason)
    }

    private static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}
