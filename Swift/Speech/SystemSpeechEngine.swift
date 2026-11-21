import AVFoundation

/// The macOS system voice: always available, nothing to download.
@MainActor
final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(componentName: "SystemSpeech")
    private var current: AVSpeechUtterance?
    private(set) var isPaused = false

    var onFinished: (() -> Void)?
    var onProgress: ((SpeechProgress) -> Void)?
    var isSpeaking: Bool { current != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        current = utterance
        synthesizer.speak(utterance)
        onProgress?(SpeechProgress(index: 0, count: 1, text: text, isBuffering: false))
        logger.log("Speaking \(text.count) characters with the system voice", level: .info)
    }

    func pause() {
        guard current != nil, !isPaused else { return }
        isPaused = synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        synthesizer.continueSpeaking()
    }

    /// The system voice reads the selection as one utterance, so skipping ends it.
    func skip() {
        guard current != nil else { return }
        stop()
        onFinished?()
    }

    func stop() {
        current = nil
        isPaused = false
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func teardown() async {
        stop()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let current = self.current, ObjectIdentifier(current) == id else { return }
            self.current = nil
            self.isPaused = false
            self.onFinished?()
        }
    }
}
