import SwiftUI

class HotkeyRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var isRecordingComplete = false
    @Published var displayString: String = "Press any key..."

    private var eventMonitor: Any?
    private var recordedKeyCode: Int = 0
    private var recordedModifiers: [HotkeyModifier] = []

    func startRecording() {
        isRecording = true
        isRecordingComplete = false
        displayString = "Press any key..."
        recordedKeyCode = 0
        recordedModifiers = []

        // Monitor key down events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDownEvent(event)
            return nil // Consume the event
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func getHotkeyConfiguration() -> (keyCode: Int, modifiers: [String]) {
        (recordedKeyCode, recordedModifiers.names)
    }

    private func handleKeyDownEvent(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let modifiers = HotkeyModifier.from(event.modifierFlags)

        // Only record if we have a valid key combination
        guard keyCode > 0, !modifiers.isEmpty else { return }

        recordedKeyCode = keyCode
        recordedModifiers = modifiers
        displayString = modifiers.symbols + character(for: event)
        isRecordingComplete = true
    }

    /// The event already carries the layout-correct character, so prefer it and
    /// fall back to translating the key code only for keys that produce none.
    private func character(for event: NSEvent) -> String {
        if let baseChar = event.charactersIgnoringModifiers, !baseChar.isEmpty {
            return String(baseChar.uppercased().prefix(1))
        }
        return KeyCodeFormatter.displayString(for: Int(event.keyCode))
    }

    deinit {
        stopRecording()
    }
}
