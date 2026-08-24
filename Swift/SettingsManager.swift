import Foundation
import SwiftUI
import Yams

// MARK: - New settings structs

struct AudioSettings: Codable {
    /// Core Audio device UID. `nil` follows the system default input.
    var inputDeviceUID: String?

    enum CodingKeys: String, CodingKey {
        case inputDeviceUID = "input_device_uid"
    }
}

// MARK: - Serialization schema (written to disk)

private struct SerializedAppConfig: Codable {
    var provider: String
    var hotkey: HotkeyConfig
    /// Optional so configs written before input-device selection still decode —
    /// a decode failure here would reset every other setting.
    var audio: AudioSettings?

    enum CodingKeys: String, CodingKey {
        case provider
        case hotkey
        case audio
    }
}

// MARK: - Hotkey config (shared schema)

struct HotkeyConfig: Codable {
    var keyCode: Int
    var modifiers: [String]

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
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {

    // MARK: - Published Properties

    @Published var transcriptionProviderID: String = "fluidaudio.parakeet.v3"

    /// `nil` = follow the system default input device.
    @Published var inputDeviceUID: String?

    @Published var hotkeyKeyCode: Int = 37  // L key
    @Published var hotkeyModifiers: [String] = ["option"]
    @Published var providerStatus: String = "Loading…"

    // MARK: - Properties

    let configFileURL: URL
    private let logger = Logger()

    // MARK: - Initialization

    init() {
        configFileURL = AppPaths.applicationSupportDirectory.appendingPathComponent("settings.yaml")
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
                hotkey: HotkeyConfig(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers),
                audio: AudioSettings(inputDeviceUID: inputDeviceUID)
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

    func updateHotkey(keyCode: Int, modifiers: [String]) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        NotificationCenter.default.post(name: .hotkeyChanged, object: self)
        logger.log("Hotkey changed", level: .info)
        saveSettings()
    }

    // MARK: - Utility

    func getHotkeyDisplayString() -> String {
        HotkeyModifier.from(hotkeyModifiers).symbols + KeyCodeFormatter.displayString(for: hotkeyKeyCode)
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
        hotkeyKeyCode = config.hotkey.keyCode
        hotkeyModifiers = config.hotkey.modifiers
        inputDeviceUID = config.audio?.inputDeviceUID
    }

    private func setDefaultSettings() {
        transcriptionProviderID = "fluidaudio.parakeet.v3"
        hotkeyKeyCode = 37
        hotkeyModifiers = ["option"]
        inputDeviceUID = nil
        logger.log("Default settings applied", level: .info)
    }
}

