import Foundation

/// Experimental selection actions. Each one composes the same primitives:
///
///     source (selection, dictation) → transform (optional) → sink (paste, speak)
///
/// | Action   | Source                | Transform              | Sink  |
/// |----------|-----------------------|------------------------|-------|
/// | tidy     | selection             | tidy preset            | paste |
/// | speak    | selection             | none                   | speak |
/// | instruct | selection + dictation | dictated instruction   | paste |
///
/// Pasting over a still-active selection replaces it.
enum SelectionAction: UInt32, CaseIterable {
    // Carbon hotkey IDs; 1 is the dictation hotkey.
    case tidy = 2
    case speak = 3
    case instruct = 4

    var displayName: String {
        switch self {
        case .tidy: return "Tidy selection"
        case .speak: return "Speak selection"
        case .instruct: return "Instruct selection"
        }
    }
}

struct SelectionActionSettings: Codable {
    var enabled: Bool = SelectionActionSettings.enabledByDefault
    var speechEngine: SpeechEngineChoice = .kokoroAne
    var tidyHotkey = HotkeyConfig(keyCode: 40, modifiers: ["option"])                // ⌥K
    var speakHotkey = HotkeyConfig(keyCode: 38, modifiers: ["option"])               // ⌥J
    var instructHotkey = HotkeyConfig(keyCode: 37, modifiers: ["option", "shift"])   // ⌥⇧L

    /// Debug builds try the experiment by default; Release needs an explicit opt-in.
    static var enabledByDefault: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func hotkey(for action: SelectionAction) -> HotkeyConfig {
        switch action {
        case .tidy: return tidyHotkey
        case .speak: return speakHotkey
        case .instruct: return instructHotkey
        }
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case speechEngine = "speech_engine"
        case tidyHotkey = "tidy_hotkey"
        case speakHotkey = "speak_hotkey"
        case instructHotkey = "instruct_hotkey"
    }

    init() {}

    /// Missing keys keep their defaults so a partial YAML block still decodes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        speechEngine = try container.decodeIfPresent(SpeechEngineChoice.self, forKey: .speechEngine) ?? speechEngine
        tidyHotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .tidyHotkey) ?? tidyHotkey
        speakHotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .speakHotkey) ?? speakHotkey
        instructHotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .instructHotkey) ?? instructHotkey
    }
}

/// Runs selection actions and reports each stage's latency in the log.
/// AppDelegate owns recording, so `instruct` is split: it captures the selection
/// before recording starts and applies the transcript when dictation finishes.
@MainActor
final class SelectionActionRunner {
    private let reader = SelectionReader()
    private let transformer: TextTransforming = TextTransformerFactory.make()
    private let speech: SpeechPlayer
    private let paste: PasteManager
    private let logger = Logger(componentName: "SelectionActions")

    /// Delivery feedback, reusing the dictation icon and sounds.
    var onWorking: (() -> Void)?
    var onDelivered: (() -> Void)?
    var onFailed: ((String) -> Void)?
    /// Speech finished or was stopped; no success sound over the end of playback.
    var onIdle: (() -> Void)?

    private(set) var isBusy = false

    init(settings: SelectionActionSettings, paste: PasteManager) {
        self.speech = SpeechPlayer(choice: settings.speechEngine)
        self.paste = paste
        speech.onFinished = { [weak self] in self?.onIdle?() }
    }

    func prepare() async {
        logger.log("On-device language model available: \(transformer.isAvailable)", level: .info)
        await speech.prepare()
    }

    func teardown() async {
        await speech.teardown()
    }

    // MARK: - Actions

    func tidy() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            guard let selection = await readOrFail() else { return }
            await transformAndPaste(selection.text, instruction: TextTransformPreset.tidy)
        }
    }

    /// Pressing the hotkey while speaking stops playback.
    func toggleSpeak() {
        if speech.isSpeaking {
            speech.stop()
            logger.log("Speech stopped", level: .info)
            onIdle?()
            return
        }
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            guard let selection = await readOrFail() else { return }
            onWorking?()
            speech.speak(selection.text)
        }
    }

    /// First half of `instruct`: read the selection before focus can change.
    func captureSelectionForInstruction() async -> Selection? {
        await readOrFail()
    }

    /// Second half of `instruct`: the transcript is the instruction.
    func applyInstruction(_ spokenInstruction: String, to selection: Selection) {
        let spoken = spokenInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else {
            onFailed?("No instruction heard")
            return
        }
        logger.log("Instruction: \(spoken)", level: .info)
        isBusy = true
        Task {
            defer { isBusy = false }
            await transformAndPaste(selection.text, instruction: TextTransformPreset.instruction(spoken))
        }
    }

    // MARK: - Stages

    private func readOrFail() async -> Selection? {
        guard let selection = await reader.readSelection() else {
            onFailed?("No text selected")
            return nil
        }
        return selection
    }

    private func transformAndPaste(_ text: String, instruction: String) async {
        guard transformer.isAvailable else {
            onFailed?("Apple Intelligence model unavailable")
            return
        }
        onWorking?()
        let started = Date()
        do {
            let output = try await transformer.transform(text, instruction: instruction)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            logger.log("Transformed \(text.count) → \(output.count) characters in \(elapsed) ms", level: .info)
            HistoryManager.shared.addTranscription(output)
            paste.pasteText(output) { [weak self] success in
                DispatchQueue.main.async {
                    if success { self?.onDelivered?() } else { self?.onFailed?("Failed to paste text at cursor") }
                }
            }
        } catch {
            logger.logError(error, context: "Transform failed")
            onFailed?("Transform failed: \(error.localizedDescription)")
        }
    }
}
