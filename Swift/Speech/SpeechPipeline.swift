import Foundation

/// Mono audio for one chunk of text.
struct SpeechClip {
    var samples: [Float]
    var sampleRate: Double

    var duration: Double { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
}

/// A synthesis error that means the voice can't speak at all, such as a runtime that
/// isn't installed. The pipeline stops at once instead of trying the next chunk.
protocol FatalSpeechError: Error {}

/// Plays clips in the order they're handed over, back to back.
@MainActor
protocol SpeechClipPlayer: AnyObject {
    /// `completion` runs on the main actor once the clip has played. It is not called
    /// for clips dropped by `stop()`.
    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void)
    func pause()
    func resume()
    /// Drops every queued clip.
    func stop()
}

/// Synthesizes chunks of text one at a time, ahead of playback, and plays them in
/// order. Shared by the voices that synthesize a buffer per call (Kokoro and the
/// mlx-audio models), so they pause, skip, cancel, and report progress the same way.
///
/// - Synthesis stays at most `prefetch` chunks ahead of the chunk playing, so a
///   long selection doesn't hold every clip in memory or keep the GPU busy after
///   the reader stops.
/// - Up to two clips are queued at the player, so sentences play without a gap.
/// - `stop()` and `skip()` take effect at once: they cancel synthesis that is no
///   longer needed and ignore results and completions that arrive afterward.
@MainActor
final class SpeechPipeline {
    typealias Synthesize = (String) async throws -> SpeechClip

    private let player: SpeechClipPlayer
    private let prefetch: Int
    private let logger: Logger

    private var chunks: [String] = []
    private var synthesize: Synthesize?
    /// Ready clips by chunk index. An empty clip marks a chunk that failed.
    private var clips: [Int: SpeechClip] = [:]
    /// The chunk playing, or the next one to play.
    private var playing = 0
    /// Chunks handed to the player, starting at `playing`.
    private var queued = 0
    private var nextToSynthesize = 0
    private var inFlight: (index: Int, task: Task<Void, Never>)?
    private var consecutiveFailures = 0
    private var lastReported: SpeechProgress?
    private var started = Date()
    /// Bumped when a read starts or stops, so late synthesis results are ignored.
    private var session = 0
    /// Bumped whenever queued clips are dropped, so their completions are ignored.
    private var playback = 0

    private(set) var isActive = false
    private(set) var isPaused = false

    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    var onProgress: ((SpeechProgress) -> Void)?

    init(player: SpeechClipPlayer, prefetch: Int = 2, logger: Logger = Logger(componentName: "SpeechPipeline")) {
        self.player = player
        self.prefetch = max(1, prefetch)
        self.logger = logger
    }

    func speak(_ chunks: [String], synthesize: @escaping Synthesize) {
        stop()
        guard !chunks.isEmpty else { return }
        self.chunks = chunks
        self.synthesize = synthesize
        isActive = true
        started = Date()
        pump()
    }

    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true
        player.pause()
    }

    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false
        player.resume()
    }

    func skip() {
        guard isActive else { return }
        dropQueuedClips()
        clips[playing] = nil
        playing += 1
        if isPaused {
            isPaused = false
            player.resume()
        }
        pump()
    }

    func stop() {
        session += 1
        if isActive || queued > 0 { dropQueuedClips() }
        inFlight?.task.cancel()
        inFlight = nil
        chunks = []
        synthesize = nil
        clips = [:]
        playing = 0
        nextToSynthesize = 0
        consecutiveFailures = 0
        lastReported = nil
        isActive = false
        isPaused = false
    }

    // MARK: - Scheduling

    private func dropQueuedClips() {
        playback += 1
        player.stop()
        queued = 0
    }

    /// Moves everything forward that can move: finishes, queues ready clips, and
    /// starts the next synthesis. Called after every change.
    private func pump() {
        guard isActive else { return }

        if playing >= chunks.count, queued == 0 {
            finish()
            return
        }

        // A failed chunk at the head is passed over once nothing is ahead of it.
        while queued == 0, playing < chunks.count, clips[playing]?.samples.isEmpty == true {
            clips[playing] = nil
            playing += 1
        }
        if playing >= chunks.count, queued == 0 {
            finish()
            return
        }

        while queued < 2, playing + queued < chunks.count,
              let clip = clips[playing + queued], !clip.samples.isEmpty {
            let token = playback
            player.play(clip) { [weak self] in self?.clipPlayed(token: token) }
            if queued == 0, playing == 0 {
                logger.log("First audio after \(Int(Date().timeIntervalSince(started) * 1000)) ms", level: .info)
            }
            queued += 1
        }

        if let inFlight, inFlight.index < playing {
            inFlight.task.cancel()
            self.inFlight = nil
        }
        nextToSynthesize = max(nextToSynthesize, playing)
        if inFlight == nil, nextToSynthesize < chunks.count, nextToSynthesize <= playing + prefetch {
            startSynthesis(of: nextToSynthesize)
        }

        report(SpeechProgress(index: playing, count: chunks.count,
                              text: chunks[playing], isBuffering: queued == 0))
    }

    private func startSynthesis(of index: Int) {
        guard let synthesize else { return }
        let session = self.session
        let text = chunks[index]
        nextToSynthesize = index + 1
        let task = Task { [weak self] in
            let result: Result<SpeechClip, Error>
            do {
                result = .success(try await synthesize(text))
            } catch {
                result = .failure(error)
            }
            self?.synthesisEnded(index: index, session: session, result: result)
        }
        inFlight = (index, task)
    }

    private func synthesisEnded(index: Int, session: Int, result: Result<SpeechClip, Error>) {
        guard session == self.session, isActive else { return }
        if inFlight?.index == index { inFlight = nil }
        guard index >= playing else {
            pump()
            return
        }
        switch result {
        case .success(let clip):
            consecutiveFailures = 0
            clips[index] = clip
        case .failure(let error):
            if error is CancellationError { break }
            consecutiveFailures += 1
            logger.logError(error, context: "Chunk \(index + 1)/\(chunks.count) failed")
            // One bad chunk is skipped; two in a row means the voice itself is failing.
            if error is FatalSpeechError || consecutiveFailures >= 2 || chunks.count == 1 {
                let message = error.localizedDescription
                stop()
                onFailed?(message)
                return
            }
            clips[index] = SpeechClip(samples: [], sampleRate: 0)
        }
        pump()
    }

    private func clipPlayed(token: Int) {
        guard token == playback, isActive, queued > 0 else { return }
        queued -= 1
        clips[playing] = nil
        playing += 1
        pump()
    }

    private func finish() {
        let elapsed = Date().timeIntervalSince(started)
        logger.log(String(format: "Read %d chunks in %.1f s", chunks.count, elapsed), level: .info)
        stop()
        onFinished?()
    }

    private func report(_ progress: SpeechProgress) {
        guard progress != lastReported else { return }
        lastReported = progress
        onProgress?(progress)
    }
}
