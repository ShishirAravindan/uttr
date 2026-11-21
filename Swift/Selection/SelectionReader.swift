import Cocoa
import ApplicationServices

struct Selection {
    let text: String
    let elapsedMilliseconds: Int
}

/// Reads the frontmost app's selected text by simulating Cmd+C. Selecting text
/// does not copy it, so the copy is briefly placed on the clipboard and the
/// original items are restored afterward unless a newer copy has landed.
/// Posting the key event needs the Accessibility grant uttr already uses for paste.
@MainActor
final class SelectionReader {
    private let pasteboard = NSPasteboard.general
    private let logger = Logger(componentName: "SelectionReader")

    /// How long to wait for the target app to answer the simulated copy.
    private let copyTimeout: TimeInterval = 0.35
    /// Extra wait for slow apps, so a late copy is still read and restored.
    private let copyGrace: TimeInterval = 0.4

    func readSelection() async -> Selection? {
        let started = Date()
        guard AXIsProcessTrusted() else {
            logger.log("Accessibility not granted; cannot read selection", level: .warning)
            return nil
        }

        let clipboard = ClipboardTransaction(pasteboard: pasteboard)
        let before = pasteboard.changeCount
        postCopy()

        // The target app copies asynchronously; poll until the change count moves.
        await waitForChange(from: before, timeout: copyTimeout + copyGrace)
        // An unchanged count means nothing was selected (or the app ignored Cmd+C),
        // and the clipboard was never touched, so there is nothing to restore.
        let after = pasteboard.changeCount
        let copied = after != before
        let text = copied ? pasteboard.string(forType: .string) : nil
        if copied { clipboard.restore(ifChangeCountIs: after) }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        guard let text, Self.isSelectedText(text) else {
            logger.log("No selection found after \(elapsed) ms", level: .info)
            return nil
        }
        logger.log("Read \(text.count) characters in \(elapsed) ms", level: .info)
        return Selection(text: text, elapsedMilliseconds: elapsed)
    }

    /// Whether copied text is a real selection. Whitespace alone (an empty line)
    /// is not. VS Code, Cursor, JetBrains, and Sublime copy the whole current line,
    /// newline included, when nothing is selected, so a single line ending in its
    /// newline is rejected too; a deliberately selected line without it works.
    nonisolated static func isSelectedText(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let isLineCopy = text.last?.isNewline == true && !text.dropLast().contains(where: \.isNewline)
        return !isLineCopy
    }

    private func waitForChange(from count: Int, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while pasteboard.changeCount == count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func postCopy() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),  // C
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            logger.log("Failed to create Cmd+C events", level: .error)
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
