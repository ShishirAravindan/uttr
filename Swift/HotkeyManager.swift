
import Carbon
import Cocoa

// MARK: - Error Handling
enum HotkeyManagerError: Error, LocalizedError {
    case settingsManagerNotAvailable
    case permissionDenied
    case hotkeyRegistrationFailed(status: OSStatus)
    case eventHandlerInstallationFailed(status: OSStatus)
    case bundleIdentifierNotFound

    var errorDescription: String? {
        switch self {
        case .settingsManagerNotAvailable:
            return "Settings manager is not available."
        case .permissionDenied:
            return "Accessibility permission is required for global hotkeys."
        case .hotkeyRegistrationFailed(let status):
            return "Failed to register global hotkey with status: \(status)"
        case .eventHandlerInstallationFailed(let status):
            return "Failed to install global hotkey event handler with status: \(status)"
        case .bundleIdentifierNotFound:
            return "Could not determine the application's bundle identifier."
        }
    }
}

// MARK: - Actions
/// A global shortcut's action. The raw value is its Carbon hotkey ID.
enum HotkeyAction: UInt32, CaseIterable {
    case record = 1
}

// MARK: - HotkeyManager Class
class HotkeyManager {
    
    // MARK: - Properties
    private var hotkeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?
    private var isCapturing = false
    
    private let logger = Logger()
    private let settingsManager: SettingsManager
    
    var onHotkeyPressed: ((HotkeyAction) -> Void)?
    
    // MARK: - Initialization
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        logger.log("[HotkeyManager] Initializing", level: .info)
        setupHotkeys()
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeySettingsChanged),
            name: .hotkeySettingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyCaptureBegan),
            name: .hotkeyCaptureBegan,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyCaptureEnded),
            name: .hotkeyCaptureEnded,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanup()
    }
    
    // MARK: - Public Methods
    func refreshHotkeyConfiguration() {
        logger.log("[HotkeyManager] Refreshing hotkey configuration", level: .info)
        cleanup()
        guard !isCapturing else {
            logger.log("[HotkeyManager] Shortcut capture in progress, hotkeys stay paused", level: .debug)
            return
        }
        setupHotkeys()
    }
    
    // MARK: - Settings Change Handling
    @objc private func handleHotkeySettingsChanged() {
        logger.log("[HotkeyManager] Hotkey settings changed, refreshing configuration", level: .info)
        refreshHotkeyConfiguration()
    }

    @objc private func handleHotkeyCaptureBegan() {
        logger.log("[HotkeyManager] Pausing hotkeys while a shortcut is captured", level: .debug)
        isCapturing = true
        cleanup()
    }

    @objc private func handleHotkeyCaptureEnded() {
        isCapturing = false
        refreshHotkeyConfiguration()
    }
    
    // MARK: - Setup
    private func setupHotkeys() {
        // First, set up the local hotkey which always works
        setupLocalHotkey()
        
        // Then, attempt to set up the global hotkey. Accessibility may not be granted
        // yet — that's fine: PermissionManager owns prompting and, once the user grants
        // it, the app calls `refreshHotkeyConfiguration()` to register the global hotkey
        // live. The local monitor keeps the hotkey working in the meantime whenever
        // the app is frontmost.
        do {
            try setupGlobalHotkey()
        } catch {
            logger.logError(error, context: "Failed to register global hotkey")
            if let error = error as? HotkeyManagerError, case .permissionDenied = error {
                logAccessibilityInstructions()
            }
        }
    }

    // MARK: - Global Hotkey (Carbon)
    private func setupGlobalHotkey() throws {
        guard checkAccessibilityPermissions() else {
            throw HotkeyManagerError.permissionDenied
        }
        
        try installGlobalHotkeyEventHandler()

        // A shortcut another app already holds fails alone; the others still register.
        for action in HotkeyAction.allCases {
            let hotkey = settingsManager.hotkey(for: action)
            let display = settingsManager.displayString(for: hotkey)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotkey.keyCode), hotkey.carbonModifiers,
                                             try getUniqueHotkeyID(id: action.rawValue),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotkeyRefs[action] = ref
                logger.log("[HotkeyManager] \(action) hotkey registered: \(display)", level: .info)
            } else {
                logger.logError(HotkeyManagerError.hotkeyRegistrationFailed(status: status),
                                context: "Failed to register \(action) hotkey \(display)")
            }
        }
    }
    
    private func installGlobalHotkeyEventHandler() throws {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let hotkeyManager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            hotkeyManager.handleGlobalHotkeyEvent(event: event)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        
        guard status == noErr else {
            throw HotkeyManagerError.eventHandlerInstallationFailed(status: status)
        }
        logger.log("[HotkeyManager] Global hotkey event handler installed", level: .debug)
    }
    
    private func handleGlobalHotkeyEvent(event: EventRef?) {
        guard let event = event else { return }
        
        // Get the hotkey ID from the event to determine which hotkey was pressed
        var hotkeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        
        guard result == noErr else {
            logger.log("[HotkeyManager] Failed to get hotkey ID from event", level: .error)
            return
        }
        
        guard let action = HotkeyAction(rawValue: hotkeyID.id) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let display = self.settingsManager.displayString(for: self.settingsManager.hotkey(for: action))
            self.logger.log("[HotkeyManager] \(action) hotkey pressed: \(display)", level: .info)
            self.onHotkeyPressed?(action)
        }
    }
    
    // MARK: - Local Hotkey (Cocoa)
    private func setupLocalHotkey() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            let actualModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for action in HotkeyAction.allCases {
                let hotkey = self.settingsManager.hotkey(for: action)
                if actualModifiers == hotkey.cocoaModifiers && Int(event.keyCode) == hotkey.keyCode {
                    self.logger.log("[HotkeyManager] Local \(action) hotkey pressed: \(self.settingsManager.displayString(for: hotkey))", level: .info)
                    self.onHotkeyPressed?(action)
                    return nil // Swallow the event
                }
            }
            return event
        }
        logger.log("[HotkeyManager] Local hotkey monitor installed", level: .debug)
    }
    
    // MARK: - Configuration & Permissions
    private func getUniqueHotkeyID(id: UInt32) throws -> EventHotKeyID {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw HotkeyManagerError.bundleIdentifierNotFound
        }
        
        let signature = fourCharString(from: bundleId)
        return EventHotKeyID(signature: signature, id: id)
    }
    
    private func fourCharString(from string: String) -> FourCharCode {
        // A simple hashing algorithm to generate a FourCharCode from a string.
        var hash: UInt32 = 0
        for char in string.unicodeScalars {
            hash = (hash &* 31) &+ char.value
        }
        return hash
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        // Check without prompting — PermissionManager owns prompting and re-triggers
        // registration via refreshHotkeyConfiguration() once the grant lands.
        let checkOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): kCFBooleanFalse]
        return AXIsProcessTrustedWithOptions(checkOptions as CFDictionary)
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        logger.log("[HotkeyManager] Cleaning up hotkey resources", level: .debug)

        // Clean up global hotkeys
        for (action, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
            logger.log("[HotkeyManager] \(action) hotkey unregistered", level: .debug)
        }
        hotkeyRefs.removeAll()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
            logger.log("[HotkeyManager] Global event handler removed", level: .debug)
        }
        
        // Clean up local monitor
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
            logger.log("[HotkeyManager] Local hotkey monitor removed", level: .debug)
        }
    }
    
    // MARK: - Helper
    private func logAccessibilityInstructions() {
        logger.log("[HotkeyManager] To enable global hotkeys, please grant Accessibility permissions:", level: .warning)
        logger.log("[HotkeyManager] 1. Open System Settings > Privacy & Security", level: .warning)
        logger.log("[HotkeyManager] 2. Select 'Accessibility'", level: .warning)
        logger.log("[HotkeyManager] 3. Find 'uttr' and enable it.", level: .warning)
        logger.log("[HotkeyManager] 4. A restart of the app may be required.", level: .warning)
    }
}

// MARK: - Modifier conversion
extension HotkeyConfig {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        for modifier in modifiers {
            switch modifier {
            case "command": flags |= UInt32(cmdKey)
            case "shift":   flags |= UInt32(shiftKey)
            case "option":  flags |= UInt32(optionKey)
            case "control": flags |= UInt32(controlKey)
            default: break
            }
        }
        return flags
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case "command": flags.insert(.command)
            case "shift":   flags.insert(.shift)
            case "option":  flags.insert(.option)
            case "control": flags.insert(.control)
            default: break
            }
        }
        return flags
    }
}
