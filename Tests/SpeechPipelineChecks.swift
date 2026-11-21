import Foundation

/// The shared sentence pipeline with a fake player and fake synthesis: ordering,
/// the prefetch bound, pause, skip, cancellation, and failures. Plays no audio and
/// loads no model.
@main
struct SpeechPipelineChecks {
    @MainActor
    static func main() async {
        await checkOrderAndPrefetch()
        await checkStopCancelsSynthesis()
        await checkSkip()
        await checkPause()
        await checkFailures()
        await checkStaleCompletions()
        print("Speech pipeline checks passed")
    }

    static let logger = Logger(writer: LogWriter(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("uttr-pipeline-checks-\(UUID().uuidString).log")))

    @MainActor
    static func make(_ chunks: [String] = ["a", "b", "c", "d", "e"])
        -> (SpeechPipeline, FakePlayer, FakeSynth, Events) {
        let player = FakePlayer()
        let synth = FakeSynth()
        let events = Events()
        let pipeline = SpeechPipeline(player: player, prefetch: 2, logger: logger)
        pipeline.onFinished = { events.finished += 1 }
        pipeline.onFailed = { events.failures.append($0) }
        pipeline.onProgress = { events.progress.append($0) }
        pipeline.speak(chunks) { try await synth.synthesize($0) }
        return (pipeline, player, synth, events)
    }

    @MainActor
    static func checkOrderAndPrefetch() async {
        let (pipeline, player, synth, events) = make()
        await settle()
        precondition(synth.requests == ["a"], "only the first chunk is requested at first")
        precondition(events.progress.last == SpeechProgress(index: 0, count: 5, text: "a", isBuffering: true))

        synth.finish("a")
        await settle()
        precondition(player.queue.map(\.text) == ["a"])
        precondition(events.progress.last?.isBuffering == false)
        synth.finish("b")
        await settle()
        synth.finish("c")
        await settle()
        precondition(player.queue.map(\.text) == ["a", "b"], "at most two clips wait at the player")
        precondition(synth.requests == ["a", "b", "c"], "synthesis stays two chunks ahead of playback")

        player.finishCurrent()
        await settle()
        precondition(player.queue.map(\.text) == ["b", "c"])
        precondition(synth.requests == ["a", "b", "c", "d"])
        precondition(events.progress.last == SpeechProgress(index: 1, count: 5, text: "b", isBuffering: false))

        precondition(synth.pendingTexts == ["d"])
        await drain(player, synth)
        precondition(player.played == ["a", "b", "c", "d", "e"], "chunks play in order")
        precondition(events.finished == 1 && events.failures.isEmpty)
        precondition(!pipeline.isActive)
    }

    @MainActor
    static func checkStopCancelsSynthesis() async {
        let (pipeline, player, synth, events) = make()
        await settle()
        let started = Date()
        pipeline.stop()
        precondition(!pipeline.isActive, "stop takes effect synchronously")
        await settle()
        precondition(Date().timeIntervalSince(started) < 0.5)
        precondition(synth.cancelled == ["a"], "in-flight synthesis is cancelled")
        precondition(player.stops >= 1)
        synth.finish("a")
        await settle()
        precondition(player.queue.isEmpty && synth.requests == ["a"], "late results are ignored")
        precondition(events.finished == 0, "stopping isn't finishing")

        // Speaking again replaces the previous read.
        let (again, _, againSynth, _) = make()
        await settle()
        again.speak(["x"]) { try await againSynth.synthesize($0) }
        await settle()
        precondition(againSynth.cancelled == ["a"] && againSynth.requests == ["a", "x"])
        again.stop()
        await settle()
    }

    @MainActor
    static func checkSkip() async {
        let (pipeline, player, synth, events) = make()
        await settle()
        synth.finish("a")
        await settle()
        synth.finish("b")
        await settle()
        precondition(player.queue.map(\.text) == ["a", "b"])

        pipeline.skip()
        await settle()
        precondition(player.stops == 1)
        precondition(player.queue.map(\.text) == ["b"], "the next ready clip starts at once")
        precondition(events.progress.last?.index == 1)

        // c is synthesizing; skipping past b and c cancels it and moves on to d.
        precondition(synth.pendingTexts == ["c"])
        pipeline.skip()
        pipeline.skip()
        await settle()
        precondition(synth.cancelled == ["c"])
        precondition(synth.pendingTexts == ["d"])
        precondition(events.progress.last == SpeechProgress(index: 3, count: 5, text: "d", isBuffering: true))

        // Skipping the last chunk finishes.
        pipeline.skip()
        pipeline.skip()
        await settle()
        precondition(events.finished == 1 && !pipeline.isActive)
    }

    @MainActor
    static func checkPause() async {
        let (pipeline, player, synth, _) = make()
        await settle()
        synth.finish("a")
        await settle()
        pipeline.pause()
        precondition(pipeline.isPaused && player.paused)
        pipeline.resume()
        precondition(!pipeline.isPaused && !player.paused)
        pipeline.pause()
        pipeline.skip()
        precondition(!pipeline.isPaused && !player.paused, "skipping resumes")
        pipeline.stop()
        precondition(!pipeline.isPaused)
        await settle()
    }

    @MainActor
    static func checkFailures() async {
        // One failed chunk is passed over.
        let (pipeline, player, synth, events) = make(["a", "b", "c"])
        await settle()
        synth.finish("a")
        await settle()
        synth.fail("b")
        await settle()
        await drain(player, synth)
        precondition(player.played == ["a", "c"] && events.finished == 1 && events.failures.isEmpty)
        precondition(!pipeline.isActive)

        // Two in a row stop the read.
        let (twice, _, twiceSynth, twiceEvents) = make(["a", "b", "c"])
        await settle()
        twiceSynth.fail("a")
        await settle()
        twiceSynth.fail("b")
        await settle()
        precondition(twiceEvents.failures.count == 1 && twiceEvents.finished == 0 && !twice.isActive)

        // A fatal error stops at once.
        let (fatal, _, fatalSynth, fatalEvents) = make(["a", "b", "c"])
        await settle()
        fatalSynth.fail("a", error: Unavailable())
        await settle()
        precondition(fatalEvents.failures == ["unavailable"] && !fatal.isActive)
        precondition(fatalSynth.requests == ["a"])
    }

    @MainActor
    static func checkStaleCompletions() async {
        let (pipeline, player, synth, events) = make(["a", "b", "c"])
        await settle()
        synth.finish("a")
        await settle()
        let stale = player.queue[0].completion
        pipeline.skip()
        await settle()
        stale()
        await settle()
        precondition(events.progress.last?.index == 1, "a dropped clip's completion doesn't advance")
        pipeline.stop()
        await settle()
    }

    /// Finishes synthesis as it's requested and plays everything queued.
    @MainActor
    static func drain(_ player: FakePlayer, _ synth: FakeSynth) async {
        while true {
            synth.pendingTexts.forEach(synth.finish)
            await settle()
            if player.queue.isEmpty { return }
            player.finishCurrent()
            await settle()
        }
    }

    @MainActor
    static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}

struct Unavailable: FatalSpeechError, LocalizedError {
    var errorDescription: String? { "unavailable" }
}

struct ChunkFailed: LocalizedError {
    var errorDescription: String? { "chunk failed" }
}

@MainActor
final class Events {
    var finished = 0
    var failures: [String] = []
    var progress: [SpeechProgress] = []
}

@MainActor
final class FakePlayer: SpeechClipPlayer {
    var queue: [(text: String, completion: @MainActor () -> Void)] = []
    var played: [String] = []
    var paused = false
    var stops = 0

    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void) {
        queue.append((FakeSynth.text(of: clip), completion))
    }

    func finishCurrent() {
        let current = queue.removeFirst()
        played.append(current.text)
        current.completion()
    }

    func pause() { paused = true }
    func resume() { paused = false }
    func stop() {
        stops += 1
        paused = false
        queue.removeAll()
    }
}

/// Synthesis that waits until the check finishes or fails each chunk. A clip's
/// first sample encodes its chunk, a single letter.
@MainActor
final class FakeSynth {
    var requests: [String] = []
    var cancelled: [String] = []
    private var pending: [String: CheckedContinuation<SpeechClip, Error>] = [:]

    var pendingTexts: [String] { pending.keys.sorted() }

    func synthesize(_ text: String) async throws -> SpeechClip {
        requests.append(text)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[text] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel(text) }
        }
    }

    func finish(_ text: String) {
        let code = Float(text.unicodeScalars.first!.value)
        pending.removeValue(forKey: text)?.resume(returning: SpeechClip(samples: [code], sampleRate: 1))
    }

    func fail(_ text: String, error: Error = ChunkFailed()) {
        pending.removeValue(forKey: text)?.resume(throwing: error)
    }

    private func cancel(_ text: String) {
        guard let continuation = pending.removeValue(forKey: text) else { return }
        cancelled.append(text)
        continuation.resume(throwing: CancellationError())
    }

    static func text(of clip: SpeechClip) -> String {
        String(UnicodeScalar(UInt32(clip.samples[0]))!)
    }
}
