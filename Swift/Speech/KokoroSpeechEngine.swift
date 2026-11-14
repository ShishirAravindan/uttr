import AVFoundation
import CoreML
import FluidAudio

/// FluidAudio's Kokoro 82M voice. Kokoro synthesizes a whole buffer per call, so text
/// is split into sentences and each is scheduled as soon as it is ready: the first
/// sentence plays while the next is synthesized.
@MainActor
final class KokoroSpeechEngine: SpeechEngine {
    /// FluidAudio defaults Prosody and Noise to `.all`, which lets Core ML place them
    /// on the GPU. There, an MPSGraph tensor allocation fails Metal API validation,
    /// which Xcode enables for Debug runs, and read-aloud aborts. Keep every stage on
    /// the Neural Engine or CPU.
    private static let computeUnits = KokoroAneComputeUnits(
        prosody: .cpuAndNeuralEngine, noise: .cpuAndNeuralEngine, tail: .cpuAndNeuralEngine
    )

    private let logger = Logger(componentName: "KokoroSpeech")
    private var manager: KokoroAneManager?
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var isEngineConfigured = false
    private var speakTask: Task<Void, Never>?
    private var pendingBuffers = 0
    /// Bumped by `stop()` so callbacks from stopped playback are ignored.
    private var generation = 0

    var onFinished: (() -> Void)?
    var isSpeaking: Bool { speakTask != nil || pendingBuffers > 0 }
    var isReady: Bool { manager != nil }

    /// Downloads the models on first use, then compiles and loads them. Returns
    /// whether Kokoro is ready.
    func prepare() async -> Bool {
        if manager != nil { return true }
        let started = Date()
        let manager = KokoroAneManager(computeUnits: Self.computeUnits)
        do {
            try await manager.initialize()
            self.manager = manager
            logger.log("Kokoro ready in \(milliseconds(since: started)) ms", level: .info)
            return true
        } catch {
            logger.logError(error, context: "Kokoro failed to load")
            return false
        }
    }

    func speak(_ text: String) {
        stop()
        guard let manager else { return }
        let chunks = SpeechChunks.split(text)
        let started = Date()
        let generation = self.generation
        logger.log("Speaking \(text.count) characters with Kokoro in \(chunks.count) chunks", level: .info)
        speakTask = Task { [weak self] in
            var synthesisSeconds = 0.0
            var audioSeconds = 0.0
            for (index, chunk) in chunks.enumerated() {
                let chunkStarted = Date()
                let result: KokoroAneSynthesisResult
                do {
                    result = try await manager.synthesizeDetailed(text: chunk)
                } catch {
                    self?.logger.logError(error, context: "Kokoro failed on chunk \(index + 1)/\(chunks.count)")
                    continue
                }
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                synthesisSeconds += Date().timeIntervalSince(chunkStarted)
                audioSeconds += result.durationSeconds
                self.schedule(result.samples)
                if index == 0 { self.logger.log("First audio after \(milliseconds(since: started)) ms", level: .info) }
            }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            let speed = synthesisSeconds > 0 ? audioSeconds / synthesisSeconds : 0
            self.logger.log(String(format: "Synthesized %.1f s of audio in %.2f s (%.1fx real time)",
                                   audioSeconds, synthesisSeconds, speed), level: .info)
            self.speakTask = nil
            if self.pendingBuffers == 0 { self.onFinished?() }
        }
    }

    func stop() {
        generation += 1
        speakTask?.cancel()
        speakTask = nil
        if pendingBuffers > 0 {
            playerNode.stop()
            pendingBuffers = 0
        }
    }

    func teardown() async {
        stop()
        if isEngineConfigured { audioEngine.stop() }
        await manager?.cleanup()
        manager = nil
    }

    /// Wired on first use, so uttr doesn't touch the output device until it speaks.
    private func configureEngineIfNeeded() {
        guard !isEngineConfigured else { return }
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        // Changing the output device stops the engine and drops scheduled buffers.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        isEngineConfigured = true
    }

    private func handleConfigurationChange() {
        logger.log("Audio output changed; stopping read-aloud", level: .warning)
        let wasSpeaking = isSpeaking
        stop()
        if wasSpeaking { onFinished?() }
    }

    private func schedule(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        configureEngineIfNeeded()
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                logger.logError(error, context: "Failed to start audio output")
                return
            }
        }
        pendingBuffers += 1
        let scheduledGeneration = generation
        // The player calls this on its own audio thread. An unannotated closure formed
        // in this main-actor class would be inferred main-actor isolated and trap when
        // it runs off the main thread, so it stays @Sendable and hops explicitly.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.bufferPlayed(generation: scheduledGeneration) }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    private func bufferPlayed(generation scheduledGeneration: Int) {
        guard generation == scheduledGeneration, pendingBuffers > 0 else { return }
        pendingBuffers -= 1
        if pendingBuffers == 0, speakTask == nil { onFinished?() }
    }
}

private func milliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}
