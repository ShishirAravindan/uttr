import ApplicationServices
import Foundation

/// Reads the frontmost app's selection aloud. Pressing the shortcut again stops it.
@MainActor
final class ReadAloud {
    private let reader = SelectionReader()
    private var engine: SpeechEngine
    private var isReadingSelection = false
    private let logger = Logger(componentName: "ReadAloud")

    // Status feedback, wired to the menu-bar icon and notifications by AppDelegate.
    var onSpeaking: (() -> Void)?
    var onIdle: (() -> Void)?
    var onFailed: ((String) -> Void)?

    init(engine: SpeechEngine? = nil) {
        let engine = engine ?? SystemSpeechEngine()
        self.engine = engine
        engine.onFinished = { [weak self] in self?.onIdle?() }
    }

    var isSpeaking: Bool { engine.isSpeaking }

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
        Task {
            defer { isReadingSelection = false }
            guard let selection = await reader.readSelection() else {
                onFailed?("No text selected")
                return
            }
            HistoryManager.shared.add(selection.text, kind: .readAloud)
            onSpeaking?()
            engine.speak(selection.text)
        }
    }

    /// Stops speech without reporting it as finished, for example when recording starts.
    func stop() {
        guard engine.isSpeaking else { return }
        engine.stop()
        onIdle?()
    }

    func teardown() async {
        engine.stop()
        await engine.teardown()
    }
}
