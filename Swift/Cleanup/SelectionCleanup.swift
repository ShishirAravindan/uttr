import ApplicationServices
import Foundation

/// Cleans the frontmost app's selection and pastes the result over it. The
/// selection is still selected after the copy, so the paste replaces it.
@MainActor
final class SelectionCleanup {
    private let reader = SelectionReader()
    private let cleanup: TextCleanup
    private let paste: PasteManager
    private let instructions: () -> String
    private var isCleaning = false
    private let logger = Logger(componentName: "SelectionCleanup")

    // Status feedback, wired to the menu-bar icon and notifications by AppDelegate.
    var onCleaning: (() -> Void)?
    var onDelivered: (() -> Void)?
    var onFailed: ((String) -> Void)?

    init(cleanup: TextCleanup, paste: PasteManager, instructions: @escaping () -> String) {
        self.cleanup = cleanup
        self.paste = paste
        self.instructions = instructions
    }

    func clean() {
        guard !isCleaning else { return }
        guard AXIsProcessTrusted() else {
            onFailed?("Cleanup needs Accessibility permission")
            return
        }
        // Checked before copying, so an unsupported Mac never touches the clipboard.
        guard cleanup.isAvailable else {
            onFailed?(CleanupOutcome.unavailable.selectionMessage)
            return
        }
        isCleaning = true
        Task {
            defer { isCleaning = false }
            guard let selection = await reader.readSelection() else {
                onFailed?("No text selected")
                return
            }
            onCleaning?()
            let result: CleanupResult
            do {
                result = try await cleanup.clean(selection.text, instructions: instructions(), profile: .selection)
            } catch {
                return
            }
            logger.log("Selection cleanup: \(result.outcome.rawValue)", level: .info)
            switch result.outcome {
            case .cleaned:
                HistoryManager.shared.add(result.text, kind: .cleanup, originalText: result.original)
                paste.pasteText(result.text) { [weak self] success in
                    if success { self?.onDelivered?() } else { self?.onFailed?("Failed to paste the cleaned text") }
                }
            case .unchanged:
                onDelivered?()
            default:
                onFailed?(result.outcome.selectionMessage)
            }
        }
    }
}

extension CleanupOutcome {
    /// What to tell someone whose selection was left as it was.
    var selectionMessage: String {
        switch self {
        case .cleaned, .unchanged: return "Selection cleaned up"
        case .unavailable: return "Cleanup needs Apple Intelligence on macOS 26 or later"
        case .tooLong: return "Selection is too long to clean up (over \(TextCleanup.maxCharacters) characters)"
        case .unsupportedLanguage: return "Cleanup doesn't support this language"
        case .busy: return "Cleanup is still finishing the last request"
        case .timedOut: return "Cleanup took too long"
        case .failed: return "Cleanup failed"
        case .rejected: return "Cleanup would have lost content, so the selection was left as is"
        }
    }
}
