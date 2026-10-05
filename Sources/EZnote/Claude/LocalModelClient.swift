import AppKit
import Foundation

/// EZifier avec un modèle local (Qwen, Llama, Mistral…) servi par Ollama ou LM Studio, sans internet.
/// Les deux exposent la même API de chat en streaming sur le Mac.
struct LocalModelClient {
    enum Failure: LocalizedError {
        case unreachable(String)
        case noModel
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let url):
                return "Aucun modèle local ne répond à \(url). Lance Ollama ou LM Studio, ou vérifie l'adresse dans les Réglages."
            case .noModel:
                return "Choisis un modèle local dans Réglages › Claude › Modèle local."
            case .http(let code, let message):
                return "Le modèle local a renvoyé une erreur \(code) : \(message)"
            }
        }
    }

    static let defaultServer = "http://localhost:11434/v1"
    static var server: String {
        let value = UserDefaults.standard.string(forKey: "localServer") ?? ""
        return value.isEmpty ? defaultServer : value
    }
    static var model: String { UserDefaults.standard.string(forKey: "localModel") ?? "" }

    /// Nom court du modèle pour l'étiquette des ajouts : « qwen3.5:2b » → « Qwen3.5 ».
    static var displayName: String {
        let base = model.split(separator: "/").last.map(String.init) ?? model
        let name = base.split(separator: ":").first.map(String.init) ?? base
        return name.isEmpty ? "IA locale" : name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Modèles installés (pour le menu des Réglages).
    static func installedModels() async -> [String] {
        guard let url = URL(string: server + "/models"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = Self.model
                    guard !model.isEmpty else { throw Failure.noModel }
                    try await Self.ensureRunning()
                    var urlRequest = URLRequest(url: URL(string: Self.server + "/chat/completions")!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = 900
                    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
                    // Images (modèles qui voient, comme Qwen-VL ou Gemma 3) au format data URI.
                    var user: Any = request.user
                    if !request.images.isEmpty {
                        user = request.images.map {
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + $0.base64EncodedString()]] as [String: Any]
                        } + [["type": "text", "text": request.user]]
                    }
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "stream": true,
                        // Pas de longue réflexion préalable (Qwen 3…) : la leçon commence tout de suite.
                        "reasoning_effort": "none",
                        "messages": [
                            ["role": "system", "content": request.system],
                            ["role": "user", "content": user],
                        ],
                    ] as [String: Any])

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Failure.http(status, String(decoding: data, as: UTF8.self))
                    }

                    // Certains modèles (Qwen…) réfléchissent d'abord entre <think> et </think> : on ne garde que la leçon.
                    var thinking = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let choice = (json["choices"] as? [[String: Any]])?.first,
                              let delta = choice["delta"] as? [String: Any] else { continue }
                        guard var text = delta["content"] as? String, !text.isEmpty else { continue }
                        if text.contains("<think>") { thinking = true; text = text.components(separatedBy: "<think>")[0] }
                        if thinking {
                            guard let end = text.range(of: "</think>") else { continue }
                            thinking = false
                            text = String(text[end.upperBound...])
                        }
                        if !text.isEmpty { continuation.yield(.text(text)) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Si Ollama est installé mais fermé, on le lance et on attend qu'il réponde (10 s au plus).
    private static func ensureRunning() async throws {
        guard let url = URL(string: server + "/models") else { throw Failure.unreachable(server) }
        func reachable() async -> Bool { (try? await URLSession.shared.data(from: url)) != nil }
        if await reachable() { return }
        let ollama = URL(fileURLWithPath: "/Applications/Ollama.app")
        guard server.contains(":11434"), FileManager.default.fileExists(atPath: ollama.path) else {
            throw Failure.unreachable(server)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: ollama, configuration: configuration)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(500))
            if await reachable() { return }
        }
        throw Failure.unreachable(server)
    }
}
