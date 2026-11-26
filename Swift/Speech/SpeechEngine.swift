import AVFoundation

/// Reads text aloud. Read-aloud only talks to this protocol, so the voice can change
/// without touching selection, history, or status feedback.
@MainActor
protocol SpeechEngine: AnyObject {
    var isSpeaking: Bool { get }
    /// Completes the current utterance. Stopping it invalidates completion.
    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void)
    func stop()
    func teardown() async
}

/// The macOS system voice: always available, nothing to download.
@MainActor
final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(componentName: "SystemSpeech")
    private var current: AVSpeechUtterance?

    private var completion: ((SpeechCompletion) -> Void)?
    var isSpeaking: Bool { current != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        self.completion = completion
        current = utterance
        synthesizer.speak(utterance)
        logger.log("Speaking \(text.count) characters with the system voice", level: .info)
    }

    func stop() {
        let hadUtterance = current != nil
        current = nil
        completion = nil
        if hadUtterance || synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func teardown() async {
        stop()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        complete(utterance, with: .finished)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        complete(utterance, with: .failed("System speech was interrupted"))
    }

    private nonisolated func complete(_ utterance: AVSpeechUtterance, with outcome: SpeechCompletion) {
        // Keep the utterance alive across the hop so its identity cannot be reused.
        Task { @MainActor [weak self, utterance] in
            guard let self, self.current === utterance else { return }
            let completion = self.completion
            self.current = nil
            self.completion = nil
            completion?(outcome)
        }
    }
}
