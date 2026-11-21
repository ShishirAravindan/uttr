import AVFoundation
import CoreML
import FluidAudio

/// FluidAudio's Kokoro 82M voice. Kokoro synthesizes a whole buffer per call, so text
/// is split into sentences and the shared pipeline plays each as soon as it is ready:
/// the first sentence plays while the next is synthesized.
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
    private let player: SpeechAudioPlayer
    private let pipeline: SpeechPipeline

    var onFinished: (() -> Void)? {
        get { pipeline.onFinished }
        set { pipeline.onFinished = newValue }
    }
    var onFailed: ((String) -> Void)? {
        get { pipeline.onFailed }
        set { pipeline.onFailed = newValue }
    }
    var onProgress: ((SpeechProgress) -> Void)? {
        get { pipeline.onProgress }
        set { pipeline.onProgress = newValue }
    }
    var isSpeaking: Bool { pipeline.isActive }
    var isPaused: Bool { pipeline.isPaused }
    var isReady: Bool { manager != nil }

    init(player: SpeechAudioPlayer) {
        self.player = player
        pipeline = SpeechPipeline(player: player, logger: Logger(componentName: "KokoroSpeech"))
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
            logger.log("Kokoro ready in \(Int(Date().timeIntervalSince(started) * 1000)) ms", level: .info)
            return true
        } catch {
            logger.logError(error, context: "Kokoro failed to load")
            return false
        }
    }

    func speak(_ text: String) {
        guard let manager else { return }
        let chunks = SpeechChunks.split(text)
        logger.log("Speaking \(text.count) characters with Kokoro in \(chunks.count) chunks", level: .info)
        pipeline.speak(chunks) { chunk in
            let result = try await manager.synthesizeDetailed(text: chunk)
            return SpeechClip(samples: result.samples, sampleRate: 24_000)
        }
    }

    func pause() { pipeline.pause() }
    func resume() { pipeline.resume() }
    func skip() { pipeline.skip() }
    func stop() { pipeline.stop() }

    func teardown() async {
        stop()
        await manager?.cleanup()
        manager = nil
    }
}
