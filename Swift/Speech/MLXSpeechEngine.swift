/// Reads with one preset through the same bounded audio pipeline as Kokoro.
@MainActor
final class MLXSpeechEngine: SpeechPlaybackControlling {
    private let player: SpeechAudioPlayer
    private let pipeline: SpeechPipeline
    private let model: ExpressiveSpeechModel
    private let host: TTSModelHost

    var isSpeaking: Bool { pipeline.isActive }
    var isBuffering: Bool { pipeline.progress?.isBuffering ?? false }
    var canSkip: Bool {
        guard let progress = pipeline.progress else { return false }
        return progress.index + 1 < progress.count
    }
    var playbackRate: Double {
        get { player.playbackRate }
        set { player.playbackRate = newValue }
    }
    var onPlaybackChanged: (() -> Void)?
    func skip() { if canSkip { pipeline.skip() } }

    init(model: ExpressiveSpeechModel, host: TTSModelHost) {
        self.model = model
        self.host = host
        let player = SpeechAudioPlayer()
        self.player = player
        let pipeline = SpeechPipeline(player: player)
        self.pipeline = pipeline
        pipeline.onProgress = { [weak self] _ in self?.onPlaybackChanged?() }
        player.onInterrupted = { [weak pipeline] in
            pipeline?.fail("Audio output changed during read-aloud")
        }
    }

    func prepare() async throws {
        try await host.prepare(model)
    }

    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void) {
        let chunks = Self.chunks(from: text)
        pipeline.speak(chunks, synthesize: { [host, model] chunk in
            try await host.synthesize(chunk, with: model)
        }, completion: completion)
    }

    func stop() {
        pipeline.stop()
    }

    func teardown() async {
        stop()
        player.shutDown()
        await pipeline.drainSynthesis()
    }

    /// Start on one sentence so the first audio arrives earlier, then keep a
    /// little more context in each chunk for expressive delivery.
    private static func chunks(from text: String) -> [String] {
        let sentences = SpeechChunks.split(text, maxCharacters: 400)
        guard let first = sentences.first else { return [] }
        var chunks = [first]
        var group: [String] = []
        var length = 0
        for sentence in sentences.dropFirst() {
            if !group.isEmpty, group.count == 3 || length + 1 + sentence.count > 240 {
                chunks.append(group.joined(separator: " "))
                group.removeAll(keepingCapacity: true)
                length = 0
            }
            length += group.isEmpty ? sentence.count : sentence.count + 1
            group.append(sentence)
        }
        if !group.isEmpty { chunks.append(group.joined(separator: " ")) }
        return chunks
    }
}
