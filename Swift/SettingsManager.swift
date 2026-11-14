import Foundation
import SwiftUI
import Yams
import Carbon

// MARK: - New settings structs

struct FluidAudioSettings: Codable {
    var modelVersion: String = "v3"

    enum CodingKeys: String, CodingKey {
        case modelVersion = "model_version"
    }
}

struct AudioSettings: Codable {
    /// Core Audio device UID. `nil` follows the system default input.
    var inputDeviceUID: String?

    enum CodingKeys: String, CodingKey {
        case inputDeviceUID = "input_device_uid"
    }
}

struct HistorySettings: Codable {
    var maxEntries: Int = HistoryManager.defaultMaxEntries

    enum CodingKeys: String, CodingKey {
        case maxEntries = "max_entries"
    }

    init(maxEntries: Int = HistoryManager.defaultMaxEntries) {
        self.maxEntries = maxEntries
    }

    /// A missing key keeps its default, so a partial block doesn't reset every setting.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxEntries = try container.decodeIfPresent(Int.self, forKey: .maxEntries) ?? maxEntries
    }
}

// MARK: - Serialization schema (written to disk)

private struct SerializedAppConfig: Codable {
    var provider: String
    var fluidAudio: FluidAudioSettings
    var hotkey: HotkeyConfig
    /// Optional so configs written before input-device selection still decode —
    /// a decode failure here would reset every other setting.
    var audio: AudioSettings?
    // Optional for the same reason as `audio`.
    var history: HistorySettings?
    var readAloudHotkey: HotkeyConfig?
    var cleanupHotkey: HotkeyConfig?

    enum CodingKeys: String, CodingKey {
        case provider
        case fluidAudio = "fluid_audio"
        case hotkey
        case audio
        case history
        case readAloudHotkey = "read_aloud_hotkey"
        case cleanupHotkey = "cleanup_hotkey"
    }
}

// MARK: - Hotkey config (shared schema)

struct HotkeyConfig: Codable, Equatable {
    var keyCode: Int
    var modifiers: [String]

    static let defaultReadAloud = HotkeyConfig(keyCode: 15, modifiers: ["option"])  // ⌥R
    static let defaultCleanSelection = HotkeyConfig(keyCode: 8, modifiers: ["option"])  // ⌥C

    enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case modifiers
    }
}

// MARK: - Settings Change Notifications

extension Notification.Name {
    static let transcriptionProviderChanged = Notification.Name("transcriptionProviderChanged")
    static let inputDeviceChanged = Notification.Name("inputDeviceChanged")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
    static let hotkeyCaptureBegan = Notification.Name("hotkeyCaptureBegan")
    static let hotkeyCaptureEnded = Notification.Name("hotkeyCaptureEnded")
    static let historyMaxEntriesChanged = Notification.Name("historyMaxEntriesChanged")
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {

    // MARK: - Published Properties

    @Published var transcriptionProviderID: String = "fluidaudio.parakeet.v3"
    @Published var fluidAudio: FluidAudioSettings = .init()

    /// `nil` = follow the system default input device.
    @Published var inputDeviceUID: String?

    @Published var hotkeyKeyCode: Int = 37  // L key
    @Published var hotkeyModifiers: [String] = ["option"]
    @Published var providerStatus: String = "Loading…"
    @Published var historyMaxEntries: Int = HistoryManager.defaultMaxEntries
    @Published var readAloudHotkey: HotkeyConfig = .defaultReadAloud
    @Published var cleanupHotkey: HotkeyConfig = .defaultCleanSelection

    // MARK: - Properties

    let configFileURL: URL
    private let logger = Logger()

    // MARK: - Initialization

    init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("uttr")
        configFileURL = appSupportURL.appendingPathComponent("settings.yaml")
        logger.log("Using config file at: \(configFileURL.path)", level: .debug)
        loadSettings()
    }

    // MARK: - Load / Save

    func loadSettings() {
        logger.log("Loading settings from: \(configFileURL.path)", level: .debug)

        if FileManager.default.fileExists(atPath: configFileURL.path) {
            do {
                let data = try Data(contentsOf: configFileURL)
                if let yamlString = String(data: data, encoding: .utf8) {
                    try parseYAMLSettings(yamlString)
                    logger.log("Settings loaded successfully", level: .debug)
                }
            } catch {
                logger.logError(error, context: "Failed to load settings")
                setDefaultSettings()
            }
        } else {
            logger.log("No settings file found, creating defaults", level: .debug)
            setDefaultSettings()
            saveSettings()
        }
    }

    func saveSettings() {
        logger.log("Saving settings to: \(configFileURL.path)", level: .debug)

        do {
            let config = SerializedAppConfig(
                provider: transcriptionProviderID,
                fluidAudio: fluidAudio,
                hotkey: HotkeyConfig(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers),
                audio: AudioSettings(inputDeviceUID: inputDeviceUID),
                history: HistorySettings(maxEntries: historyMaxEntries),
                readAloudHotkey: readAloudHotkey,
                cleanupHotkey: cleanupHotkey
            )

            let encoder = YAMLEncoder()
            let yamlContent = try encoder.encode(config)

            let configDir = configFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            try yamlContent.write(to: configFileURL, atomically: true, encoding: .utf8)
            logger.log("Settings saved successfully", level: .info)
        } catch {
            logger.logError(error, context: "Failed to save settings")
        }
    }

    // MARK: - Update Methods

    func updateTranscriptionProvider(_ providerID: String) {
        transcriptionProviderID = providerID
        NotificationCenter.default.post(name: .transcriptionProviderChanged, object: self)
        logger.log("Transcription provider changed to: \(providerID)", level: .info)
        saveSettings()
    }

    /// - Parameter uid: Core Audio device UID, or `nil` to follow the system default.
    func updateInputDevice(_ uid: String?) {
        inputDeviceUID = uid
        NotificationCenter.default.post(name: .inputDeviceChanged, object: self)
        logger.log("Input device changed to: \(uid ?? "system default")", level: .info)
        saveSettings()
    }

    func updateHotkey(_ hotkey: HotkeyConfig, for action: HotkeyAction) {
        switch action {
        case .record:
            hotkeyKeyCode = hotkey.keyCode
            hotkeyModifiers = hotkey.modifiers
        case .readAloud:
            readAloudHotkey = hotkey
        case .cleanSelection:
            cleanupHotkey = hotkey
        }
        NotificationCenter.default.post(name: .hotkeyChanged, object: self)
        logger.log("\(action.title) hotkey changed", level: .info)
        saveSettings()
    }

    func updateHistoryMaxEntries(_ count: Int) {
        historyMaxEntries = max(1, count)
        NotificationCenter.default.post(name: .historyMaxEntriesChanged, object: self)
        logger.log("History limit changed to \(historyMaxEntries)", level: .info)
        saveSettings()
    }

    // MARK: - Utility

    var recordingHotkey: HotkeyConfig {
        HotkeyConfig(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    func hotkey(for action: HotkeyAction) -> HotkeyConfig {
        switch action {
        case .record: return recordingHotkey
        case .readAloud: return readAloudHotkey
        case .cleanSelection: return cleanupHotkey
        }
    }

    /// The other action whose shortcut is already `hotkey`, whatever order its
    /// modifiers were stored in.
    func action(using hotkey: HotkeyConfig, otherThan action: HotkeyAction) -> HotkeyAction? {
        HotkeyAction.allCases.first { other in
            let existing = self.hotkey(for: other)
            return other != action && existing.keyCode == hotkey.keyCode
                && Set(existing.modifiers) == Set(hotkey.modifiers)
        }
    }

    func getHotkeyDisplayString() -> String {
        displayString(for: recordingHotkey)
    }

    func displayString(for hotkey: HotkeyConfig) -> String {
        var display = ""
        if hotkey.modifiers.contains("command") { display += "⌘" }
        if hotkey.modifiers.contains("shift")   { display += "⇧" }
        if hotkey.modifiers.contains("option")  { display += "⌥" }
        if hotkey.modifiers.contains("control") { display += "⌃" }
        display += keyCodeToCharacter(hotkey.keyCode)
        return display
    }

    // MARK: - Private

    private func parseYAMLSettings(_ yamlString: String) throws {
        let decoder = YAMLDecoder()
        guard let config = try? decoder.decode(SerializedAppConfig.self, from: yamlString) else {
            logger.log("Unrecognized settings format, applying defaults", level: .info)
            setDefaultSettings()
            return
        }
        transcriptionProviderID = config.provider
        fluidAudio = config.fluidAudio
        hotkeyKeyCode = config.hotkey.keyCode
        hotkeyModifiers = config.hotkey.modifiers
        inputDeviceUID = config.audio?.inputDeviceUID
        historyMaxEntries = max(1, config.history?.maxEntries ?? HistoryManager.defaultMaxEntries)
        readAloudHotkey = config.readAloudHotkey ?? .defaultReadAloud
        cleanupHotkey = config.cleanupHotkey ?? .defaultCleanSelection
        if transcriptionProviderID == "python.whisper" {
            transcriptionProviderID = "fluidaudio.parakeet.v3"
            saveSettings()
        }
    }

    private func setDefaultSettings() {
        transcriptionProviderID = "fluidaudio.parakeet.v3"
        fluidAudio = FluidAudioSettings()
        hotkeyKeyCode = 37
        hotkeyModifiers = ["option"]
        inputDeviceUID = nil
        historyMaxEntries = HistoryManager.defaultMaxEntries
        readAloudHotkey = .defaultReadAloud
        cleanupHotkey = .defaultCleanSelection
        logger.log("Default settings applied", level: .info)
    }

    private func keyCodeToCharacter(_ keyCode: Int) -> String {
        switch keyCode {
        case 0: return "A";  case 1: return "S";  case 2: return "D";  case 3: return "F"
        case 4: return "H";  case 5: return "G";  case 6: return "Z";  case 7: return "X"
        case 8: return "C";  case 9: return "V";  case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
        case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
        case 45: return "N"; case 46: return "M"
        case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
        case 22: return "6"; case 23: return "5"; case 25: return "9"; case 26: return "7"
        case 28: return "8"; case 29: return "0"
        case 24: return "="; case 27: return "-"; case 30: return "]"; case 33: return "["
        case 39: return "'"; case 41: return ";"; case 42: return "\\"
        case 43: return ","; case 44: return "/"; case 47: return "."; case 50: return "`"
        case 49: return "Space"; case 36: return "↵"; case 48: return "⇥"
        case 51: return "⌫";    case 53: return "⎋"; case 117: return "⌦"
        default: return "?"
        }
    }
}

