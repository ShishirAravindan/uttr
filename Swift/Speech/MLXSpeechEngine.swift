import Foundation

/// A speech-LLM voice run in-process by the shared model host. Text is read one
/// to three sentences at a time, so the model hears enough context to choose its
/// tone while the next chunk is synthesized during playback.
@MainActor
final class MLXSpeechEngine: SpeechEngine {
    let model: MLXSpeechModel
    private let values: () -> TTSParameterValues
    private let sentencesPerChunk: () -> Int
    private let host: TTSModelHost
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

    /// - Parameter values: read for every chunk, so voice and style edits apply
    ///   from the next chunk without rebuilding the engine.
    init(model: MLXSpeechModel, host: TTSModelHost, player: SpeechClipPlayer,
         sentencesPerChunk: @escaping () -> Int = { 3 },
         values: @escaping () -> TTSParameterValues) {
        self.model = model
        self.host = host
        self.values = values
        self.sentencesPerChunk = sentencesPerChunk
        pipeline = SpeechPipeline(player: player, logger: Logger(componentName: "MLXSpeech"))
    }

    func speak(_ text: String) {
        let chunks = SpeechChunks.groups(text, maxSentences: max(1, min(3, sentencesPerChunk())))
        logger.log("Speaking \(text.count) characters with \(model.name) in \(chunks.count) chunks", level: .info)
        let model = self.model
        let values = self.values
        let host = self.host
        pipeline.speak(chunks) { chunk in
            try await host.synthesize(model.request(text: chunk, values: values()))
        }
    }

    func pause() { pipeline.pause() }
    func resume() { pipeline.resume() }
    func skip() { pipeline.skip() }
    func stop() { pipeline.stop() }

    /// The host is shared and unloads itself when idle, so the model stays loaded.
    func teardown() async {
        stop()
    }
}
