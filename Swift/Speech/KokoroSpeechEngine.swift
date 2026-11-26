import CoreML
import FluidAudio

/// FluidAudio's Kokoro 82M voice. Kokoro synthesizes a whole buffer per call, so text
/// is split into sentences and each is scheduled as soon as it is ready: the first
/// sentence plays while the next is synthesized.
@MainActor
final class KokoroSpeechEngine: SpeechPlaybackControlling {
    /// FluidAudio defaults Prosody and Noise to `.all`, which lets Core ML place them
    /// on the GPU. There, an MPSGraph tensor allocation fails Metal API validation,
    /// which Xcode enables for Debug runs, and read-aloud aborts. Keep every stage on
    /// the Neural Engine or CPU.
    private static let computeUnits = KokoroAneComputeUnits(
        prosody: .cpuAndNeuralEngine, noise: .cpuAndNeuralEngine, tail: .cpuAndNeuralEngine
    )

    private let logger = Logger(componentName: "KokoroSpeech")
    private var manager: KokoroAneManager?
    private let player: SpeechAudioPlayer
    private let pipeline: SpeechPipeline

    var isSpeaking: Bool { pipeline.isActive }
    var playbackRate: Double {
        get { player.playbackRate }
        set { player.playbackRate = newValue }
    }
    var isBuffering: Bool { pipeline.progress?.isBuffering == true }
    var canSkip: Bool {
        guard let progress = pipeline.progress else { return false }
        return progress.index + 1 < progress.count
    }
    var onPlaybackChanged: (() -> Void)?
    var isReady: Bool { manager != nil }

    init() {
        let player = SpeechAudioPlayer()
        let pipeline = SpeechPipeline(player: player)
        self.player = player
        self.pipeline = pipeline
        player.onInterrupted = { [weak pipeline] in pipeline?.fail("Audio output changed") }
        pipeline.onProgress = { [weak self] _ in self?.onPlaybackChanged?() }
    }

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

    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void) {
        guard let manager else { return completion(.failed("Kokoro is still loading")) }
        pipeline.speak(SpeechChunks.split(text), synthesize: { chunk in
            let result = try await manager.synthesizeDetailed(text: chunk)
            return SpeechClip(samples: result.samples, sampleRate: 24_000)
        }, completion: completion)
    }

    func skip() {
        pipeline.skip()
    }

    func stop() {
        pipeline.stop()
    }

    func teardown() async {
        stop()
        player.shutDown()
        await pipeline.drainSynthesis()
        await manager?.cleanup()
        manager = nil
    }
}

private func milliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
}
