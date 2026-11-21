import Foundation

/// Owns the voice that reads text aloud and switches voices between reads.
@MainActor
final class ReadAloud {
    private var engine: SpeechEngine
    /// A voice that became ready mid-sentence; it takes over once speech ends.
    private var nextEngine: SpeechEngine?
    private let logger: Logger

    /// Speech ended, on its own or through `stop()`.
    var onIdle: (() -> Void)?

    init(engine: SpeechEngine? = nil, logger: Logger = Logger(componentName: "ReadAloud")) {
        self.logger = logger
        let engine = engine ?? SystemSpeechEngine()
        self.engine = engine
        engine.onFinished = { [weak self] in self?.speechEnded() }
    }

    /// Switches voices without cutting off speech in progress.
    func useEngine(_ newEngine: SpeechEngine) {
        newEngine.onFinished = { [weak self] in self?.speechEnded() }
        if engine.isSpeaking {
            nextEngine = newEngine
        } else {
            replaceEngine(with: newEngine)
        }
    }

    var isSpeaking: Bool { engine.isSpeaking }

    func speak(_ text: String) {
        engine.speak(text)
    }

    /// Stops speech without reporting it as finished, for example when recording starts.
    func stop() {
        guard engine.isSpeaking else { return }
        engine.stop()
        speechEnded()
    }

    func teardown() async {
        engine.stop()
        await engine.teardown()
        await nextEngine?.teardown()
        nextEngine = nil
    }

    private func speechEnded() {
        onIdle?()
        if let next = nextEngine {
            nextEngine = nil
            replaceEngine(with: next)
        }
    }

    private func replaceEngine(with newEngine: SpeechEngine) {
        let old = engine
        engine = newEngine
        logger.log("Read-aloud voice switched to \(type(of: newEngine))", level: .info)
        Task { await old.teardown() }
    }
}
