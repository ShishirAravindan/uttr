import AVFoundation
import CoreML
import FluidAudio
import NaturalLanguage

/// Reads text aloud with FluidAudio's Kokoro 82M model, whose seven Core ML
/// stages run on the Neural Engine and CPU. Kokoro synthesizes a whole buffer per
/// call, so text is split into sentences and each one is scheduled as soon as it
/// is ready: the first sentence plays while the next is synthesized. Until Kokoro
/// has loaded, or if it fails to, the macOS system voice reads instead.
@MainActor
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let logger = Logger(componentName: "SpeechPlayer")

    /// FluidAudio runs Prosody, Noise, and Tail with `.all`, which lets Core ML
    /// schedule them on the GPU. There, MPSGraph allocates a tensor that fails
    /// Metal API validation (`MTLReportFailure` in `allocateTensorDataForValue`),
    /// which Xcode enables for Debug runs, so read-aloud aborted. Keeping every
    /// stage on the Neural Engine or CPU avoids the GPU path.
    private static let kokoroComputeUnits = KokoroAneComputeUnits(
        prosody: .cpuAndNeuralEngine, noise: .cpuAndNeuralEngine, tail: .cpuAndNeuralEngine
    )

    private var kokoro: KokoroAneManager?
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let kokoroFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var speakTask: Task<Void, Never>?
    private var pendingBuffers = 0
    /// Bumped by `stop()` so callbacks from stopped playback are ignored.
    private var generation = 0

    private let synthesizer = AVSpeechSynthesizer()

    var onFinished: (() -> Void)?

    var isSpeaking: Bool {
        speakTask != nil || pendingBuffers > 0 || synthesizer.isSpeaking
    }

    private var isEngineConfigured = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Wired on first use rather than at launch, so uttr does not touch the
    /// output device until something is read aloud.
    private func configureEngineIfNeeded() {
        guard !isEngineConfigured else { return }
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: kokoroFormat)
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

    /// Loads Kokoro ahead of the first request. The first run downloads the
    /// models and compiles them for the Neural Engine, which can take a while.
    func prepare() async {
        guard kokoro == nil else { return }
        let started = Date()
        let manager = KokoroAneManager(computeUnits: Self.kokoroComputeUnits)
        do {
            try await manager.initialize()
            kokoro = manager
            logger.log("Kokoro ANE ready in \(milliseconds(since: started)) ms", level: .info)
        } catch {
            logger.logError(error, context: "Kokoro ANE failed to load; using system speech")
        }
    }

    func speak(_ text: String) {
        stop()
        if let kokoro {
            speakWithKokoro(text, manager: kokoro)
        } else {
            let utterance = AVSpeechUtterance(string: text)
            synthesizer.speak(utterance)
            logger.log("Speaking \(text.count) characters with system speech", level: .info)
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
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func teardown() async {
        stop()
        if isEngineConfigured { audioEngine.stop() }
        await kokoro?.cleanup()
        kokoro = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.onFinished?() }
    }

    // MARK: - Kokoro

    private func speakWithKokoro(_ text: String, manager: KokoroAneManager) {
        let chunks = Self.chunks(of: text)
        let started = Date()
        logger.log("Speaking \(text.count) characters with Kokoro in \(chunks.count) chunks", level: .info)
        speakTask = Task { [weak self] in
            var synthesisSeconds = 0.0
            var audioSeconds = 0.0
            for (index, chunk) in chunks.enumerated() {
                let chunkStarted = Date()
                guard let result = try? await manager.synthesizeDetailed(text: chunk) else {
                    self?.logger.log("Kokoro failed on chunk \(index + 1)/\(chunks.count)", level: .error)
                    continue
                }
                guard let self, !Task.isCancelled else { return }
                synthesisSeconds += Date().timeIntervalSince(chunkStarted)
                audioSeconds += result.durationSeconds
                self.schedule(result.samples)
                if index == 0 {
                    self.logger.log("First audio after \(milliseconds(since: started)) ms", level: .info)
                }
            }
            guard let self, !Task.isCancelled else { return }
            let rtf = synthesisSeconds > 0 ? audioSeconds / synthesisSeconds : 0
            self.logger.log(String(format: "Synthesized %.1f s of audio in %.2f s (%.1fx real time, %d chunks)",
                                   audioSeconds, synthesisSeconds, rtf, chunks.count), level: .info)
            self.speakTask = nil
            if self.pendingBuffers == 0 { self.onFinished?() }
        }
    }

    private func schedule(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: kokoroFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        configureEngineIfNeeded()
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                logger.log("Audio output started", level: .debug)
            } catch {
                logger.logError(error, context: "Failed to start audio output")
                return
            }
        }
        pendingBuffers += 1
        let scheduledGeneration = generation
        // AVAudioPlayerNode calls this on its own audio thread. Formed inside this
        // main-actor class, an unannotated closure would be inferred main-actor
        // isolated, and the Swift runtime traps when it runs off the main thread.
        // @Sendable keeps it nonisolated; it hops to the main actor explicitly.
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

    /// Sentences, with long ones split at word boundaries to stay under
    /// KokoroAne's 510-phoneme input limit.
    static func chunks(of text: String, maxCharacters: Int = 300) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }

        var chunks: [String] = []
        for sentence in sentences {
            var current = ""
            for word in sentence.split(separator: " ") {
                if !current.isEmpty, current.count + word.count + 1 > maxCharacters {
                    chunks.append(current)
                    current = ""
                }
                current += current.isEmpty ? String(word) : " " + String(word)
            }
            if !current.isEmpty { chunks.append(current) }
        }
        return chunks
    }
}

private func milliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}
