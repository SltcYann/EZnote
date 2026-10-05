import AVFoundation
import Speech

/// Enregistre le micro, garde l'audio du cours et le transcrit en direct, sur le Mac (SpeechAnalyzer de
/// macOS 26 : pas de limite de durée, rien n'est envoyé sur internet).
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

    /// Texte provisoire (peut encore changer).
    var onVolatile: ((String) -> Void)?
    /// Texte définitif et seconde du cours où il commence (pour le réécouter).
    var onFinal: ((String, Double) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var audioFile: AVAudioFile?

    private(set) var isRecording = false

    /// `vocabulary` : mots du contexte (matière, noms propres…) qui aident à les reconnaître.
    /// `audioURL` : où garder l'audio du cours.
    func start(vocabulary: [String], audioURL: URL?) async throws {
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
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: vocabulary]
            try? await analyzer.setContext(context)
        }

        // Audio du cours en AAC (environ 30 Mo par heure).
        if let audioURL {
            audioFile = try? AVAudioFile(forWriting: audioURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: microphone.sampleRate,
                AVNumberOfChannelsKey: microphone.channelCount,
                AVEncoderBitRateKey: 64_000,
            ], commonFormat: microphone.commonFormat, interleaved: microphone.isInterleaved)
        }
        let file = audioFile

        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal { self?.onFinal?(text, result.range.start.seconds) } else { self?.onVolatile?(text) }
                }
            } catch {}
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone) { buffer, _ in
            try? file?.write(from: buffer)
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
        audioFile = nil   // ferme le fichier audio
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        await results?.value
        results = nil
    }
}

/// Audio des cours, rangé dans ~/Library/Application Support/EZnote/Audio.
enum AudioStore {
    static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EZnote/Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for id: String) -> URL { folder.appendingPathComponent("\(id).m4a") }
}

/// Réécoute d'un passage du cours.
@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var onChange: ((Bool) -> Void)?

    func play(id: String, from seconds: Double) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: AudioStore.url(for: id))
        player.delegate = self
        player.currentTime = max(0, seconds - 1)   // une seconde avant, pour ne pas couper le début
        player.play()
        self.player = player
        onChange?(true)
    }

    func stop() {
        player?.stop()
        player = nil
        onChange?(false)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        MainActor.assumeIsolated { stop() }
    }
}
