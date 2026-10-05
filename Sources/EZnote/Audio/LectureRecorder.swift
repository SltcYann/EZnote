import AVFoundation
import Speech

/// Enregistre le micro et transcrit le cours en direct, sur le Mac (SpeechAnalyzer de macOS 26 :
/// pas de limite de durée, rien n'est envoyé sur internet).
@MainActor
final class LectureRecorder {
    enum Failure: LocalizedError {
        case microphoneDenied, unsupportedLanguage, noAudioFormat

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "EZnote n'a pas accès au micro. Autorise-le dans Réglages Système › Confidentialité et sécurité › Micro."
            case .unsupportedLanguage:
                return "La transcription n'est pas disponible dans la langue de ce Mac."
            case .noAudioFormat:
                return "Impossible de préparer le micro pour la transcription."
            }
        }
    }

    /// Texte provisoire (peut encore changer) et texte définitif.
    var onVolatile: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?

    private(set) var isRecording = false

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.microphoneDenied }
        let preferred = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        let fallback = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-FR"))
        guard let locale = preferred ?? fallback else { throw Failure.unsupportedLanguage }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // Le modèle de langue se télécharge une seule fois.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.noAudioFormat
        }

        let microphone = engine.inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: microphone, to: format) else { throw Failure.noAudioFormat }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal { self?.onFinal?(text) } else { self?.onVolatile?(text) }
                }
            } catch {}
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / microphone.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var delivered = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if delivered { status.pointee = .noDataNow; return nil }
                delivered = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
        engine.prepare()
        try engine.start()
        try await analyzer.start(inputSequence: stream)

        self.analyzer = analyzer
        self.input = continuation
        isRecording = true
    }

    /// Arrête le micro et attend les derniers mots transcrits.
    func stop() async {
        guard isRecording else { return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        await results?.value
        results = nil
    }
}
