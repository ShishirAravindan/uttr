import Foundation

struct SpeechClip {
    let samples: [Float]
    let sampleRate: Double
}

struct SpeechProgress: Equatable {
    let index: Int
    let count: Int
    let isBuffering: Bool
}

@MainActor
protocol SpeechClipPlayer: AnyObject {
    /// Reports playback after the buffer reaches the output. Dropped buffers do not report completion.
    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void) throws
    func stop()
}

/// Synthesizes one chunk at a time and keeps no more than two chunks ahead of playback.
@MainActor
final class SpeechPipeline {
    typealias Synthesize = (String) async throws -> SpeechClip

    private let player: SpeechClipPlayer
    private var chunks: [String] = []
    private var synthesize: Synthesize?
    private var completion: ((SpeechCompletion) -> Void)?
    private var clips: [Int: SpeechClip] = [:]
    private var playing = 0
    private var queued = 0
    private var nextToSynthesize = 0
    private var inFlight: (run: Int, index: Int, task: Task<Void, Never>)?
    private var run = 0
    private var playback = 0
    private(set) var progress: SpeechProgress? {
        didSet {
            if progress != oldValue, let progress { onProgress?(progress) }
        }
    }

    var onProgress: ((SpeechProgress) -> Void)?
    var isActive: Bool { completion != nil }

    init(player: SpeechClipPlayer) {
        self.player = player
    }

    func speak(_ chunks: [String], synthesize: @escaping Synthesize, completion: @escaping (SpeechCompletion) -> Void) {
        stop()
        guard !chunks.isEmpty else { return completion(.failed("No text to read aloud")) }
        self.chunks = chunks
        self.synthesize = synthesize
        self.completion = completion
        pump()
    }

    func stop() {
        run += 1
        if isActive { dropAudio() }
        inFlight?.task.cancel()
        completion = nil
        synthesize = nil
        clips.removeAll()
        chunks.removeAll()
        playing = 0
        nextToSynthesize = 0
        progress = nil
    }

    func skip() {
        guard isActive else { return }
        dropAudio()
        clips[playing] = nil
        playing += 1
        if let inFlight, inFlight.index < playing {
            inFlight.task.cancel()
        }
        pump()
    }

    func fail(_ message: String) {
        if isActive { finish(.failed(message)) }
    }

    func drainSynthesis() async {
        await inFlight?.task.value
    }

    private func dropAudio() {
        playback += 1
        player.stop()
        queued = 0
    }

    private func pump() {
        guard isActive else { return }
        guard playing < chunks.count else { return finish(.finished) }

        while queued < 2, let clip = clips[playing + queued] {
            let playback = self.playback
            do {
                try player.play(clip) { [weak self] in self?.played(playback) }
                queued += 1
            } catch {
                return finish(.failed("Couldn’t play read-aloud audio: \(error.localizedDescription)"))
            }
        }

        nextToSynthesize = max(nextToSynthesize, playing)
        if inFlight == nil, nextToSynthesize < chunks.count, nextToSynthesize <= playing + 2 {
            startSynthesis(nextToSynthesize)
        }
        progress = SpeechProgress(index: playing, count: chunks.count, isBuffering: queued == 0)
    }

    private func startSynthesis(_ index: Int) {
        guard let synthesize else { return }
        let run = self.run
        let text = chunks[index]
        nextToSynthesize += 1
        // Keep the task until it returns even after stop. A backend may take time to cancel.
        let task = Task { [weak self] in
            let result: Result<SpeechClip, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await synthesize(text))
            } catch {
                result = .failure(error)
            }
            self?.synthesized(result, index: index, run: run)
        }
        inFlight = (run, index, task)
    }

    private func synthesized(_ result: Result<SpeechClip, Error>, index: Int, run: Int) {
        if inFlight?.run == run, inFlight?.index == index { inFlight = nil }
        guard run == self.run, index >= playing else { return pump() }
        switch result {
        case .success(let clip): clips[index] = clip
        case .failure(let error):
            return finish(.failed("Couldn’t synthesize read-aloud audio: \(error.localizedDescription)"))
        }
        pump()
    }

    private func played(_ playback: Int) {
        guard playback == self.playback, queued > 0 else { return }
        clips[playing] = nil
        playing += 1
        queued -= 1
        pump()
    }

    private func finish(_ outcome: SpeechCompletion) {
        let completion = self.completion
        stop()
        completion?(outcome)
    }
}
