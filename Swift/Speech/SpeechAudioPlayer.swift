import AVFoundation

/// Plays speech clips through one AVAudioEngine, with a pitch-preserving speed
/// control that works for every voice.
@MainActor
final class SpeechAudioPlayer: SpeechClipPlayer {
    private let logger = Logger(componentName: "SpeechAudio")
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var format: AVAudioFormat?
    private var isEngineConfigured = false
    private var pendingBuffers = 0
    private var isPaused = false
    /// Bumped by `stop()` so callbacks for dropped buffers are ignored.
    private var generation = 0

    /// Called when the output device changes, which drops every scheduled buffer.
    var onInterrupted: (() -> Void)?

    /// Playback rate, 0.5–2.0, applied without changing pitch.
    var rate: Float = 1.0 {
        didSet { timePitch.rate = min(max(rate, 0.5), 2.0) }
    }

    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void) {
        guard !clip.samples.isEmpty, clip.sampleRate > 0,
              let format = prepareFormat(sampleRate: clip.sampleRate),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            Task { @MainActor in completion() }
            return
        }
        buffer.frameLength = buffer.frameCapacity
        clip.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: clip.samples.count) }

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                logger.logError(error, context: "Failed to start audio output")
                Task { @MainActor in completion() }
                return
            }
        }
        pendingBuffers += 1
        let scheduledGeneration = generation
        // The player calls this on its own audio thread. An unannotated closure formed
        // in this main-actor class would be inferred main-actor isolated and trap when
        // it runs off the main thread, so it stays @Sendable and hops explicitly.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == scheduledGeneration else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                completion()
            }
        }
        if !isPaused, !playerNode.isPlaying { playerNode.play() }
    }

    func pause() {
        isPaused = true
        if playerNode.isPlaying { playerNode.pause() }
    }

    func resume() {
        isPaused = false
        if pendingBuffers > 0, !playerNode.isPlaying { playerNode.play() }
    }

    func stop() {
        generation += 1
        isPaused = false
        if pendingBuffers > 0 || playerNode.isPlaying {
            playerNode.stop()
        }
        pendingBuffers = 0
    }

    /// Releases the output device.
    func shutDown() {
        stop()
        if isEngineConfigured { audioEngine.stop() }
    }

    /// Wired on first use, so uttr doesn't touch the output device until it speaks.
    /// Voices differ in sample rate, so the player is reconnected when it changes.
    private func prepareFormat(sampleRate: Double) -> AVAudioFormat? {
        if let format, format.sampleRate == sampleRate { return format }
        guard let newFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        if !isEngineConfigured {
            audioEngine.attach(playerNode)
            audioEngine.attach(timePitch)
            timePitch.rate = min(max(rate, 0.5), 2.0)
            // Changing the output device stops the engine and drops scheduled buffers.
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleConfigurationChange() }
            }
            isEngineConfigured = true
        } else {
            if pendingBuffers > 0 { stop() }
            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.disconnectNodeOutput(timePitch)
        }
        audioEngine.connect(playerNode, to: timePitch, format: newFormat)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: newFormat)
        format = newFormat
        return newFormat
    }

    private func handleConfigurationChange() {
        logger.log("Audio output changed; stopping read-aloud", level: .warning)
        let hadAudio = pendingBuffers > 0
        stop()
        if hadAudio { onInterrupted?() }
    }
}
