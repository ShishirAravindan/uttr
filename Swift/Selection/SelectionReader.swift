import Cocoa
import ApplicationServices

struct Selection {
    let text: String
    let elapsedMilliseconds: Int
}

/// Reads the frontmost app's selected text by simulating Cmd+C. Selecting text
/// does not copy it, so the copy is briefly placed on the clipboard and every
/// pasteboard item is restored afterward, as PasteManager does around Cmd+V.
/// Posting the key event needs the Accessibility grant uttr already uses for paste.
@MainActor
final class SelectionReader {
    private let pasteboard = NSPasteboard.general
    private let logger = Logger(componentName: "SelectionReader")

    /// How long to wait for the target app to answer the simulated copy.
    private let copyTimeout: TimeInterval = 0.35

    func readSelection() async -> Selection? {
        let started = Date()
        guard AXIsProcessTrusted() else {
            logger.log("Accessibility not granted; cannot read selection", level: .warning)
            return nil
        }

        let saved = snapshotPasteboard()
        let before = pasteboard.changeCount
        postCopy()

        // The target app copies asynchronously; poll until the change count moves.
        let deadline = Date().addingTimeInterval(copyTimeout)
        while pasteboard.changeCount == before, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // An unchanged count means nothing was selected (or the app ignored Cmd+C).
        let text = pasteboard.changeCount == before ? nil : pasteboard.string(forType: .string)
        restorePasteboard(saved)

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !Self.isLineCopy(text) else {
            logger.log("No selection found after \(elapsed) ms", level: .info)
            return nil
        }
        logger.log("Read \(text.count) characters in \(elapsed) ms", level: .info)
        return Selection(text: text, elapsedMilliseconds: elapsed)
    }

    /// VS Code, Cursor, JetBrains, and Sublime copy the whole current line, newline
    /// included, when nothing is selected. A deliberately selected line that ends
    /// in its newline is rejected too; selecting it without the newline works.
    static func isLineCopy(_ text: String) -> Bool {
        text.last?.isNewline == true && !text.dropLast().contains(where: \.isNewline)
    }

    private func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
    }

    private func restorePasteboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
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
