import AudioToolbox
import AVFoundation
import Foundation

enum AudioRecorderError: Error, LocalizedError {
    case audioSessionFailed
    case recordingFailed
    case fileCreationFailed

    var errorDescription: String? {
        switch self {
        case .audioSessionFailed:
            return "Failed to configure audio session"
        case .recordingFailed:
            return "Failed to start recording"
        case .fileCreationFailed:
            return "Failed to create audio file"
        }
    }
}

/// Emitted when the engine dies mid-recording (e.g. some Bluetooth headsets
/// drop out of a pinned format after a couple of seconds).
enum AudioRecorderInterruption: Error, LocalizedError {
    case engineStopped

    var errorDescription: String? {
        "Recording device stopped unexpectedly"
    }
}

class AudioRecorder {

    // MARK: - Properties

    /// Core Audio UID of the device to capture from. `nil` follows whatever the
    /// system default input is at the time of each recording.
    var preferredInputDeviceUID: String?

    /// Fires on the main thread after a mid-recording interruption is torn down.
    var onInterrupted: (() -> Void)?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var logger: Logger?
    private var framesWritten: AVAudioFramePosition = 0
    private var currentSampleRate: Double = 0
    private var recordingStartedAt: Date?
    private var configurationChangeObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    init() {
        logger = Logger(componentName: "AudioRecorder")
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Methods
    
    /// Start recording - macOS will automatically request microphone permission if needed
    func startRecording() throws {
        
        // Create temporary audio file
        recordingURL = createTemporaryAudioFile()
        guard let url = recordingURL else {
            logger?.log("Failed to create temporary audio file", level: .error)
            throw AudioRecorderError.fileCreationFailed
        }
        
        // Lazily create audio engine and input node only when recording starts
        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        inputNode = input

        // Pin the capture device before anything reads a format off the node —
        // switching devices reconfigures the I/O unit's busses.
        let pinnedDeviceID = applyPreferredInputDevice(to: input)

        // Get the native format from the input node
        let format = input.inputFormat(forBus: 0)
        currentSampleRate = format.sampleRate
        framesWritten = 0

        // Skip the mixer connection only for capture-only pinned devices — the
        // shared I/O unit's output bus has no valid format for them and `connect`
        // rejects it.
        let devicePublishesOutput = pinnedDeviceID.map(AudioDeviceManager.hasOutputChannels) ?? true
        if devicePublishesOutput {
            let mainMixer = engine.mainMixerNode
            mainMixer.outputVolume = 0.0
            engine.connect(input, to: mainMixer, format: format)
        }

        // Create audio file
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            logger?.log("Failed to create audio file: \(error.localizedDescription)", level: .error)
            throw AudioRecorderError.fileCreationFailed
        }
        
        // Install tap on input node
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }
        
        // Start audio engine - this will trigger permission request if needed
        do {
            engine.prepare()
            try engine.start()
            recordingStartedAt = Date()
            logger?.log("Audio recording started successfully", level: .info)
        } catch {
            input.removeTap(onBus: 0)
            logger?.log("Audio engine start failed: \(error.localizedDescription)", level: .error)
            throw AudioRecorderError.recordingFailed
        }

        // Some pinned devices drop the engine after a couple of seconds — end
        // the recording instead of silently starving the tap.
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange(for: engine)
        }
    }

    private func handleConfigurationChange(for engine: AVAudioEngine) {
        guard audioEngine === engine, !engine.isRunning else { return }

        logger?.logError(AudioRecorderInterruption.engineStopped, context: "Ending recording")
        discardInterruptedRecording()
        onInterrupted?()
    }

    private func discardInterruptedRecording() {
        removeConfigurationChangeObserver()

        inputNode?.removeTap(onBus: 0)
        audioFile = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        inputNode = nil
        audioEngine?.reset()
        audioEngine = nil

        framesWritten = 0
        recordingStartedAt = nil
        currentSampleRate = 0
    }

    private func removeConfigurationChangeObserver() {
        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }
    }
    
    func stopRecording() -> URL? {
        guard let engine = audioEngine else { return nil }

        logger?.log("Stopping audio recording", level: .info)
        removeConfigurationChangeObserver()

        // Stop audio engine
        engine.stop()
        inputNode?.removeTap(onBus: 0)
        
        // Close audio file
        audioFile = nil
        
        // Return the recorded file URL
        let url = recordingURL
        recordingURL = nil
        
        // Fully release engine and input to avoid keeping mic path open
        inputNode = nil
        engine.reset()
        audioEngine = nil
        
        // Diagnostics — the elapsed/frames gap flags a stalled tap.
        let seconds = currentSampleRate > 0 ? Double(framesWritten) / currentSampleRate : 0
        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        logger?.log("Recorded \(framesWritten) frames (~\(String(format: "%.2f", seconds))s of ~\(String(format: "%.2f", elapsed))s elapsed)", level: .debug)
        if let url = url,
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? NSNumber {
            logger?.log("Recorded file size: \(fileSize.intValue) bytes", level: .debug)
        }
        framesWritten = 0
        recordingStartedAt = nil
        currentSampleRate = 0
        
        return url
    }
    
    // MARK: - Private Methods

    /// Points the engine's I/O unit at `preferredInputDeviceUID`.
    ///
    /// `AVAudioEngine` has no device-selection API — its input node follows the
    /// system default. `AUAudioUnit.setDeviceID(_:)` reaches the HAL unit behind
    /// the node and is the supported override on macOS.
    ///
    /// Returns the resolved device ID only when the override actually took
    /// effect; every failure falls back to the system default rather than
    /// blocking the recording.
    private func applyPreferredInputDevice(to input: AVAudioInputNode) -> AudioDeviceID? {
        guard let uid = preferredInputDeviceUID else { return nil }

        guard let deviceID = AudioDeviceManager.deviceID(forUID: uid) else {
            logger?.log("Input device \(uid) is not connected — using the system default", level: .warning)
            return nil
        }

        do {
            try input.auAudioUnit.setDeviceID(deviceID)
            logger?.log("Capturing from input device \(uid)", level: .debug)
            return deviceID
        } catch {
            logger?.logError(error, context: "Failed to select input device \(uid), using the system default")
            return nil
        }
    }

    private func createTemporaryAudioFile() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "recording_\(timestamp).wav"
        return tempDir.appendingPathComponent(filename)
    }
    
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile = audioFile else { return }
        
        do {
            try audioFile.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            logger?.log("Failed to write audio buffer: \(error.localizedDescription)", level: .error)
        }
    }
    
    private func cleanup() {
        removeConfigurationChangeObserver()
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            inputNode?.removeTap(onBus: 0)
        }
        audioFile = nil
        recordingURL = nil
        inputNode = nil
        audioEngine = nil
    }
} 