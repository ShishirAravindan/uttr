import AudioToolbox
import CoreAudio
import Foundation

/// A Core Audio device that can capture audio.
struct AudioInputDevice: Identifiable, Hashable {
    /// Core Audio device UID — stable across relaunches and replugs, so this is
    /// what settings persist.
    let uid: String
    let name: String

    var id: String { uid }
}

/// Enumerates Core Audio input devices and translates a persisted device UID
/// back into the runtime `AudioDeviceID` that `AudioRecorder` needs.
///
/// `AVAudioEngine` exposes no device picker — its input node always follows the
/// system default input. Overriding it means reaching the HAL unit underneath
/// (see `AudioRecorder.applyPreferredInputDevice`), which identifies devices by
/// `AudioDeviceID`. Those IDs are handed out at runtime and change across
/// reboots and replugs, hence storing the UID and resolving it per recording.
final class AudioDeviceManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var inputDevices: [AudioInputDevice] = []

    /// Name of the device the system is currently routing input from, shown
    /// alongside the "System default" option so the choice isn't opaque.
    @Published private(set) var systemDefaultInputName: String?

    // MARK: - Properties

    private let logger = Logger(componentName: "AudioDeviceManager")
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private static let deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // MARK: - Initialization

    init() {
        refresh()
        startListening()
    }

    deinit {
        stopListening()
    }

    // MARK: - Public Methods

    func refresh() {
        inputDevices = Self.inputDeviceIDs().compactMap { Self.describe($0) }
        systemDefaultInputName = Self.defaultInputDeviceID().flatMap { Self.describe($0)?.name }
        logger.log("Found \(inputDevices.count) input device(s)", level: .debug)
    }

    /// Resolves a persisted device UID to the ID Core Audio is using for it right
    /// now, or `nil` when the device isn't connected.
    static func deviceID(forUID target: String) -> AudioDeviceID? {
        inputDeviceIDs().first { uid(of: $0) == target }
    }

    /// Whether a device publishes at least one output channel.
    static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        hasChannels(deviceID, scope: kAudioObjectPropertyScopeOutput)
    }

    // MARK: - Core Audio Queries

    private static func inputDeviceIDs() -> [AudioDeviceID] {
        var address = deviceListAddress
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.filter { hasInputChannels($0) && !isPrivateAggregate($0) }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = defaultInputAddress
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceID) == noErr,
              deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    private static func describe(_ deviceID: AudioDeviceID) -> AudioInputDevice? {
        guard let uid = uid(of: deviceID) else { return nil }
        let name = string(kAudioObjectPropertyName, of: deviceID) ?? uid
        return AudioInputDevice(uid: uid, name: name)
    }

    private static func uid(of deviceID: AudioDeviceID) -> String? {
        string(kAudioDevicePropertyDeviceUID, of: deviceID)
    }

    /// A device qualifies as an input if it publishes at least one channel on
    /// its input scope — this is what filters out speakers and virtual outputs.
    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        hasChannels(deviceID, scope: kAudioObjectPropertyScopeInput)
    }

    private static func hasChannels(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return false }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, storage) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)
        )
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    /// Filters out `CADefaultDeviceAggregate-*` — the private aggregate device
    /// `AVAudioEngine` creates behind its own input node, visible here only
    /// because "private" hides it from other processes, not its own creator.
    private static func isPrivateAggregate(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyComposition,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        var composition: CFDictionary?
        let status = withUnsafeMutablePointer(to: &composition) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, $0)
        }
        guard status == noErr, let composition = composition as? [String: Any] else { return false }

        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }

    private static func string(_ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, $0)
        }

        guard status == noErr, let value else { return nil }
        return value as String
    }

    // MARK: - Hardware Change Notifications

    /// Keeps the published list honest while a picker is on screen — devices get
    /// plugged in, and the system default changes out from under us.
    private func startListening() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh()
        }
        listenerBlock = block

        var deviceList = Self.deviceListAddress
        var defaultInput = Self.defaultInputAddress
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &deviceList, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &defaultInput, DispatchQueue.main, block)
    }

    private func stopListening() {
        guard let block = listenerBlock else { return }
        var deviceList = Self.deviceListAddress
        var defaultInput = Self.defaultInputAddress
        AudioObjectRemovePropertyListenerBlock(Self.systemObject, &deviceList, DispatchQueue.main, block)
        AudioObjectRemovePropertyListenerBlock(Self.systemObject, &defaultInput, DispatchQueue.main, block)
        listenerBlock = nil
    }
}
