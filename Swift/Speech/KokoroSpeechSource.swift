import CoreML
import FluidAudio

/// Prepares FluidAudio's Kokoro 82M Core ML model and supplies PCM chunks.
@MainActor
enum KokoroSpeechSource {
    /// FluidAudio defaults Prosody and Noise to `.all`, which lets Core ML place them
    /// on the GPU. There, an MPSGraph tensor allocation fails Metal API validation,
    /// which Xcode enables for Debug runs, and read-aloud aborts. Keep every stage on
    /// the Neural Engine or CPU.
    private static let computeUnits = KokoroAneComputeUnits(
        prosody: .cpuAndNeuralEngine, noise: .cpuAndNeuralEngine, tail: .cpuAndNeuralEngine
    )

    static func makeEngine() async -> BufferedSpeechEngine? {
        let logger = Logger(componentName: "KokoroSpeech")
        let started = Date()
        let manager = KokoroAneManager(computeUnits: Self.computeUnits)
        do {
            try await manager.initialize()
            try Task.checkCancellation()
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            logger.log("Kokoro ready in \(elapsed) ms", level: .info)
            return BufferedSpeechEngine(chunks: { SpeechChunks.split($0) }, synthesize: { chunk in
                let result = try await manager.synthesizeDetailed(text: chunk)
                return SpeechClip(samples: result.samples, sampleRate: 24_000)
            }, release: {
                await manager.cleanup()
            })
        } catch {
            if !Task.isCancelled { logger.logError(error, context: "Kokoro failed to load") }
            await manager.cleanup()
            return nil
        }
    }
}
