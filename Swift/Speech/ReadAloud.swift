import ApplicationServices
import Foundation

/// What read-aloud is doing, for the menu bar and popover.
enum ReadAloudState: Equatable {
    case idle
    /// Copying the selection from the frontmost app.
    case readingSelection
    /// Speaking, or waiting for the voice to synthesize the next chunk.
    case speaking(SpeechProgress?, isPaused: Bool)

    var isActive: Bool { self != .idle }
}

/// Reads the frontmost app's selection aloud. Pressing the shortcut again stops it.
@MainActor
final class ReadAloud {
    private let reader = SelectionReader()
    private var engine: SpeechEngine
    /// A voice that became ready mid-sentence; it takes over once speech ends.
    private var nextEngine: SpeechEngine?
    private var isReadingSelection = false
    private let logger: Logger

    private(set) var state: ReadAloudState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    // Status feedback, wired to the menu-bar icon and notifications by AppDelegate.
    var onSpeaking: (() -> Void)?
    var onIdle: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onStateChange: ((ReadAloudState) -> Void)?

    init(engine: SpeechEngine? = nil, logger: Logger = Logger(componentName: "ReadAloud")) {
        self.logger = logger
        let engine = engine ?? SystemSpeechEngine()
        self.engine = engine
        attach(engine)
    }

    /// Switches voices without cutting off speech in progress.
    func useEngine(_ newEngine: SpeechEngine) {
        guard newEngine !== engine else { return }
        attach(newEngine)
        if engine.isSpeaking {
            if let pending = nextEngine, pending !== newEngine { Task { await pending.teardown() } }
            nextEngine = newEngine
        } else {
            replaceEngine(with: newEngine)
        }
    }

    var isSpeaking: Bool { engine.isSpeaking }
    var isPaused: Bool { engine.isPaused }

    func toggle() {
        if engine.isSpeaking {
            stop()
            logger.log("Read-aloud stopped", level: .info)
            return
        }
        guard !isReadingSelection else { return }
        guard AXIsProcessTrusted() else {
            onFailed?("Read aloud needs Accessibility permission")
            return
        }
        isReadingSelection = true
        state = .readingSelection
        Task {
            defer { isReadingSelection = false }
            guard let selection = await reader.readSelection() else {
                state = .idle
                onFailed?("No text selected")
                return
            }
            HistoryManager.shared.add(selection.text, kind: .readAloud)
            speak(selection.text)
        }
    }

    /// Reads `text` with the current voice, replacing anything being read.
    func speak(_ text: String) {
        if engine.isSpeaking { engine.stop() }
        state = .speaking(nil, isPaused: false)
        onSpeaking?()
        engine.speak(text)
        // A voice that can't start (for example, Kokoro before it has loaded) says so
        // by not speaking.
        if !engine.isSpeaking { speechEnded() }
    }

    func togglePause() {
        guard engine.isSpeaking else { return }
        if engine.isPaused { engine.resume() } else { engine.pause() }
        if case .speaking(let progress, _) = state {
            state = .speaking(progress, isPaused: engine.isPaused)
        }
    }

    func skip() {
        guard engine.isSpeaking else { return }
        engine.skip()
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

    private func attach(_ engine: SpeechEngine) {
        engine.onFinished = { [weak self, weak engine] in
            guard let self, engine === self.engine else { return }
            self.speechEnded()
        }
        engine.onFailed = { [weak self, weak engine] message in
            guard let self, engine === self.engine else { return }
            self.logger.log("Read-aloud failed: \(message)", level: .error)
            self.speechEnded()
            self.onFailed?(message)
        }
        engine.onProgress = { [weak self, weak engine] progress in
            guard let self, engine === self.engine, engine?.isSpeaking == true else { return }
            self.state = .speaking(progress, isPaused: engine?.isPaused ?? false)
        }
    }

    private func speechEnded() {
        state = .idle
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
