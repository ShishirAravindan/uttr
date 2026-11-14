import AVFoundation

/// Reads text aloud. Read-aloud only talks to this protocol, so the voice can change
/// without touching selection, history, or status feedback.
@MainActor
protocol SpeechEngine: AnyObject {
    var isSpeaking: Bool { get }
    /// Called when speech ends on its own; not after `stop()`.
    var onFinished: (() -> Void)? { get set }
    func speak(_ text: String)
    func stop()
    func teardown() async
}

/// The macOS system voice: always available, nothing to download.
@MainActor
final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(componentName: "SystemSpeech")
    private var current: AVSpeechUtterance?

    var onFinished: (() -> Void)?
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
        logger.log("Speaking \(text.count) characters with the system voice", level: .info)
    }

    func stop() {
        current = nil
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
            self.onFinished?()
        }
    }
}
