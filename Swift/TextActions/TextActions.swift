import Foundation

/// Actions on the text selected in the frontmost app (read it aloud, clean it up)
/// plus the optional cleanup of dictation. Each finished action is recorded in
/// history: read-alouds with the text read, cleanups with the cleaned text.
@MainActor
final class TextActions {
    private let reader = SelectionReader()
    private let cleaner = TextCleaner()
    private let speech = SpeechPlayer()
    private let paste: PasteManager
    private let settings: SettingsManager
    private let logger = Logger(componentName: "TextActions")

    // Status feedback, wired to the menu-bar icon and sounds by AppDelegate.
    var onSpeaking: (() -> Void)?
    var onCleaning: (() -> Void)?
    var onDelivered: (() -> Void)?
    var onFailed: ((String) -> Void)?
    /// Speech finished or was stopped; no success sound over the end of playback.
    var onIdle: (() -> Void)?

    private var isReadingSelection = false
    private var isCleaning = false

    init(settings: SettingsManager, paste: PasteManager) {
        self.settings = settings
        self.paste = paste
        speech.onFinished = { [weak self] in self?.onIdle?() }
    }

    func prepare() async {
        logger.log("On-device cleanup model available: \(cleaner.isAvailable)", level: .info)
        await speech.prepare()
    }

    func teardown() async {
        await speech.teardown()
    }

    // MARK: - Read aloud

    /// Pressing the shortcut again while speaking stops playback.
    func toggleSpeakSelection() {
        if speech.isSpeaking {
            speech.stop()
            logger.log("Read-aloud stopped", level: .info)
            onIdle?()
            return
        }
        guard !isReadingSelection else { return }
        isReadingSelection = true
        Task {
            defer { isReadingSelection = false }
            guard let selection = await readSelectionOrFail() else { return }
            HistoryManager.shared.add(selection.text, kind: .speech)
            onSpeaking?()
            speech.speak(selection.text)
        }
    }

    // MARK: - Cleanup

    /// Cleans the selection and pastes the result over it.
    func cleanSelection() {
        guard !isCleaning, !isReadingSelection else { return }
        isCleaning = true
        isReadingSelection = true
        Task {
            defer { isCleaning = false }
            let selection = await readSelectionOrFail()
            isReadingSelection = false
            guard let selection else { return }
            guard cleaner.isAvailable else {
                onFailed?(TextCleanerError.unavailable.localizedDescription)
                return
            }
            onCleaning?()
            do {
                let cleaned = try await cleaner.clean(selection.text, prompt: settings.cleanupPrompt)
                HistoryManager.shared.add(cleaned, kind: .cleanup)
                // PasteManager calls back synchronously on the main thread.
                paste.pasteText(cleaned) { [weak self] success in
                    if success { self?.onDelivered?() } else { self?.onFailed?("Failed to paste text at cursor") }
                }
            } catch {
                logger.logError(error, context: "Selection cleanup failed")
                onFailed?("Cleanup failed: \(error.localizedDescription)")
            }
        }
    }

    /// Cleans a dictation transcript. Returns `nil` when cleanup is unavailable or
    /// fails, so the caller pastes the transcript as it is rather than losing it.
    func cleanDictation(_ text: String) async -> String? {
        guard cleaner.isAvailable else {
            logger.log("Dictation cleanup skipped: on-device model unavailable", level: .warning)
            return nil
        }
        do {
            let cleaned = try await cleaner.clean(text, prompt: settings.cleanupPrompt)
            HistoryManager.shared.add(cleaned, kind: .cleanup)
            return cleaned
        } catch {
            logger.logError(error, context: "Dictation cleanup failed; pasting the transcript")
            return nil
        }
    }

    // MARK: - Selection

    private func readSelectionOrFail() async -> Selection? {
        guard let selection = await reader.readSelection() else {
            onFailed?("No text selected")
            return nil
        }
        return selection
    }
}
