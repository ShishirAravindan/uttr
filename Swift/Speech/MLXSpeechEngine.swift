import Foundation

/// A speech-LLM voice run by the shared mlx-audio runtime. Text is read one to
/// three sentences at a time, so the model hears enough context to choose its
/// tone while the next chunk is synthesized during playback.
@MainActor
final class MLXSpeechEngine: SpeechEngine {
    let model: MLXSpeechModel
    private let options: () -> MLXModelOptions
    private let runtime: MLXAudioRuntime
    private let pipeline: SpeechPipeline
    private let logger = Logger(componentName: "MLXSpeech")

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

    /// - Parameter options: read for every chunk, so voice and style edits apply
    ///   from the next chunk without rebuilding the engine.
    init(model: MLXSpeechModel, runtime: MLXAudioRuntime, player: SpeechClipPlayer,
         options: @escaping () -> MLXModelOptions) {
        self.model = model
        self.runtime = runtime
        self.options = options
        pipeline = SpeechPipeline(player: player, logger: Logger(componentName: "MLXSpeech"))
    }

    func speak(_ text: String) {
        let chunks = SpeechChunks.groups(text)
        logger.log("Speaking \(text.count) characters with \(model.name) in \(chunks.count) chunks", level: .info)
        let model = self.model
        let options = self.options
        let runtime = self.runtime
        pipeline.speak(chunks) { chunk in
            try await runtime.synthesize(options().request(for: model, text: chunk))
        }
    }

    func pause() { pipeline.pause() }
    func resume() { pipeline.resume() }
    func skip() { pipeline.skip() }
    func stop() { pipeline.stop() }

    /// The runtime is shared and shuts itself down when idle, so it keeps running.
    func teardown() async {
        stop()
    }
}
