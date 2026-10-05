import Foundation

/// EZifier avec l'abonnement Claude : EZnote lance Claude Code (`claude -p`), déjà connecté au compte
/// claude.ai sur ce Mac, et lit sa réponse en streaming. Aucune clé API.
struct ClaudeCodeClient {
    enum Failure: LocalizedError {
        case notInstalled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Claude Code est introuvable sur ce Mac. Installe-le (claude.com/code), connecte-toi avec ton abonnement, ou choisis une clé API dans les Réglages."
            case .failed(let message):
                return "Claude Code a rencontré une erreur : \(message)"
            }
        }
    }

    /// Emplacements habituels de la commande `claude` (une app lancée depuis le Dock n'a pas le PATH du terminal).
    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    static var isAvailable: Bool { executable != nil }

    func lesson(from notes: String, context: LessonPrompt.Context, webSearch: Bool) -> AsyncThrowingStream<ClaudeClient.Event, Error> {
        AsyncThrowingStream { continuation in
            guard let executable = Self.executable else {
                continuation.finish(throwing: Failure.notInstalled)
                return
            }
            let process = Process()
            process.executableURL = executable
            let tools = webSearch ? "WebSearch" : ""
            process.arguments = [
                "-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose",
                "--model", "opus", "--effort", "medium",
                "--system-prompt", LessonPrompt.system,
                "--tools", tools, "--allowedTools", tools,
                "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
            ]
            // Une clé API dans l'environnement passerait avant l'abonnement : on la retire.
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "ANTHROPIC_API_KEY")
            environment.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
            process.environment = environment
            process.currentDirectoryURL = FileManager.default.temporaryDirectory

            let input = Pipe(), output = Pipe(), errors = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            let task = Task {
                do {
                    try process.run()
                    input.fileHandleForWriting.write(Data(LessonPrompt.userMessage(notes: notes, context: context).utf8))
                    try input.fileHandleForWriting.close()

                    var failure: String?
                    for try await line in output.fileHandleForReading.bytes.lines {
                        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                              let type = json["type"] as? String else { continue }
                        switch type {
                        case "stream_event":
                            // Seule la réponse principale compte (pas celle d'un éventuel sous-agent).
                            guard json["parent_tool_use_id"] is NSNull || json["parent_tool_use_id"] == nil,
                                  let event = json["event"] as? [String: Any] else { break }
                            if event["type"] as? String == "content_block_start",
                               let block = event["content_block"] as? [String: Any],
                               ["tool_use", "server_tool_use"].contains(block["type"] as? String ?? "") {
                                continuation.yield(.searching)
                            }
                            if event["type"] as? String == "content_block_delta",
                               let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(.text(text))
                            }
                        case "result":
                            if json["is_error"] as? Bool == true {
                                failure = json["result"] as? String ?? (json["subtype"] as? String) ?? "erreur inconnue"
                            }
                        default:
                            break
                        }
                    }
                    process.waitUntilExit()
                    if let failure { throw Failure.failed(failure) }
                    if process.terminationStatus != 0 {
                        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        throw Failure.failed(message.isEmpty ? "code \(process.terminationStatus)" : message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Qui rédige la leçon : Claude avec l'abonnement (via Claude Code), Claude avec une clé API,
/// ou un modèle local (Ollama, LM Studio).
enum ClaudeConnection: String {
    case subscription, apiKey, local

    static let defaultsKey = "connection"

    static var current: ClaudeConnection {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ClaudeConnection.init) ?? .subscription
    }
}
