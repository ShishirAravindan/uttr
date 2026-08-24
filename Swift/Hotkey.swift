import AppKit
import Carbon

/// A hotkey modifier, in the four representations the app needs it: the string
/// persisted in settings.yaml, the symbol shown in the UI, the Carbon flag for
/// global registration, and the AppKit flag for the local monitor.
///
/// `allCases` order is the order modifiers are rendered in, matching the macOS
/// convention (⌘⇧⌥⌃).
enum HotkeyModifier: String, CaseIterable {
    case command, shift, option, control

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .shift:   return "⇧"
        case .option:  return "⌥"
        case .control: return "⌃"
        }
    }

    var carbonFlag: UInt32 {
        switch self {
        case .command: return UInt32(cmdKey)
        case .shift:   return UInt32(shiftKey)
        case .option:  return UInt32(optionKey)
        case .control: return UInt32(controlKey)
        }
    }

    var appKitFlag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .shift:   return .shift
        case .option:  return .option
        case .control: return .control
        }
    }

    /// Decodes the persisted string list, dropping anything unrecognized.
    static func from(_ names: [String]) -> [HotkeyModifier] {
        allCases.filter { names.contains($0.rawValue) }
    }

    static func from(_ flags: NSEvent.ModifierFlags) -> [HotkeyModifier] {
        allCases.filter { flags.contains($0.appKitFlag) }
    }
}

extension Array where Element == HotkeyModifier {
    var symbols: String { map(\.symbol).joined() }
    var names: [String] { map(\.rawValue) }
    var carbonFlags: UInt32 { reduce(0) { $0 | $1.carbonFlag } }
    var appKitFlags: NSEvent.ModifierFlags { reduce(into: []) { $0.insert($1.appKitFlag) } }
}

/// Renders a virtual key code as the character printed on that key.
enum KeyCodeFormatter {

    /// Keys with no character representation. These are positional on every
    /// layout, so unlike letters and punctuation they're safe to hardcode.
    private static let specialKeys: [Int: String] = [
        36: "↵", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Asks the active keyboard layout what this key produces, so the hotkey
    /// reads correctly on AZERTY/Dvorak/QWERTZ rather than assuming US QWERTY.
    static func displayString(for keyCode: Int) -> String {
        if let special = specialKeys[keyCode] { return special }
        return translate(keyCode)?.uppercased() ?? "?"
    }

    private static func translate(_ keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,                                  // no modifiers — we want the bare keycap
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
