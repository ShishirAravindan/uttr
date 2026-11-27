/// Plays synthesized PCM through one queue, independent of the synthesis backend.
@MainActor
final class BufferedSpeechEngine: SpeechEngine {
    private let player: SpeechAudioPlayer
    private let pipeline: SpeechPipeline
    private let chunks: (String) -> [String]
    private let synthesize: SpeechPipeline.Synthesize
    private let release: () async -> Void

    var isSpeaking: Bool { pipeline.isActive }
    var isBuffering: Bool { pipeline.progress?.isBuffering == true }
    var canSkip: Bool {
        guard let progress = pipeline.progress else { return false }
        return progress.index + 1 < progress.count
    }
    var playbackRate: Double {
        get { player.playbackRate }
        set { player.playbackRate = newValue }
    }
    var onPlaybackChanged: (() -> Void)?

    init(chunks: @escaping (String) -> [String], synthesize: @escaping SpeechPipeline.Synthesize,
         release: @escaping () async -> Void = {}) {
        self.chunks = chunks
        self.synthesize = synthesize
        self.release = release
        let player = SpeechAudioPlayer()
        let pipeline = SpeechPipeline(player: player)
        self.player = player
        self.pipeline = pipeline
        pipeline.onProgress = { [weak self] _ in self?.onPlaybackChanged?() }
        player.onInterrupted = { [weak pipeline] in pipeline?.fail("Audio output changed during read-aloud") }
    }

    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void) {
        pipeline.speak(chunks(text), synthesize: synthesize, completion: completion)
    }

    func skip() {
        if canSkip { pipeline.skip() }
    }

    func stop() {
        pipeline.stop()
    }

    func teardown() async {
        stop()
        player.shutDown()
        await pipeline.drainSynthesis()
        await release()
    }
}
