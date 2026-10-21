import Cocoa
import ApplicationServices

/// Where a selection came from. Accessibility leaves the clipboard alone; the
/// copy fallback briefly replaces it and restores every item afterward.
enum SelectionSource: String {
    case accessibility
    case copyFallback
}

struct Selection {
    let text: String
    let source: SelectionSource
    let elapsedMilliseconds: Int
}

/// Reads the frontmost app's selected text. Selecting text does not copy it, so
/// this asks Accessibility first (native Cocoa text views answer) and falls back
/// to a simulated Cmd+C (browsers and Electron apps often expose no selection).
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

        if let text = readViaAccessibility(), !text.isEmpty {
            return finish(text, source: .accessibility, started: started)
        }
        if let text = await readViaCopy(), !text.isEmpty {
            return finish(text, source: .copyFallback, started: started)
        }
        logger.log("No selection found", level: .info)
        return nil
    }

    private func finish(_ text: String, source: SelectionSource, started: Date) -> Selection {
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        logger.log("Read \(text.count) characters via \(source.rawValue) in \(elapsed) ms", level: .info)
        return Selection(text: text, source: source, elapsedMilliseconds: elapsed)
    }

    // MARK: - Accessibility

    private func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        // A hung target app would otherwise block the main thread for the default ~6 s.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else {
            return nil
        }
        return selected as? String
    }

    // MARK: - Copy fallback

    private func readViaCopy() async -> String? {
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
        return text
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
