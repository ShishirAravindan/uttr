import Foundation

@main
struct SpeechPipelineChecks {
    @MainActor
    static func main() async {
        await boundsAndStaleAudio()
        await failedReads()
        print("Speech pipeline checks passed")
    }

    @MainActor
    static func boundsAndStaleAudio() async {
        let player = FakeSpeechPlayer()
        let pipe = SpeechPipeline(player: player)
        var requested: [String] = []
        var outcomes: [SpeechCompletion] = []
        func synthesize(_ text: String) async throws -> SpeechClip {
            requested.append(text)
            return SpeechClip(samples: [0.01], sampleRate: 24_000)
        }
        pipe.speak(["a", "b", "c", "d", "e"], synthesize: synthesize) { outcomes.append($0) }
        await waitUntil { requested.count == 3 }
        precondition(requested == ["a", "b", "c"] && player.queued.count == 2)
        let stale = player.queued[0]
        player.finishOne()
        await waitUntil { requested.count == 4 }
        precondition(player.queued.count == 2)

        pipe.stop()
        pipe.speak(["new"], synthesize: synthesize) { outcomes.append($0) }
        await waitUntil { player.queued.count == 1 }
        stale()
        precondition(pipe.isActive && outcomes.isEmpty)
        player.finishOne()
        precondition(outcomes == [.finished] && !pipe.isActive)
    }

    @MainActor
    static func failedReads() async {
        let player = FakeSpeechPlayer()
        let pipe = SpeechPipeline(player: player)
        var outcomes: [SpeechCompletion] = []
        pipe.speak(["current"], synthesize: { _ in throw CancellationError() }) { outcomes.append($0) }
        await waitUntil { !outcomes.isEmpty }
        guard case .failed = outcomes.removeFirst() else { preconditionFailure("active cancellation must fail") }
        precondition(!pipe.isActive)

        player.fail = true
        pipe.speak(["current"], synthesize: { _ in
            SpeechClip(samples: [0.01], sampleRate: 24_000)
        }) { outcomes.append($0) }
        await waitUntil { !outcomes.isEmpty }
        guard case .failed = outcomes.removeFirst() else { preconditionFailure("output startup must fail") }
        precondition(!pipe.isActive && player.queued.isEmpty)
    }

    @MainActor
    static func waitUntil(_ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while !condition(), clock.now < deadline { await Task.yield() }
        precondition(condition(), "expected the pipeline to settle")
    }
}

@MainActor
private final class FakeSpeechPlayer: SpeechClipPlayer {
    var queued: [@MainActor () -> Void] = []
    var fail = false

    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void) throws {
        if fail { throw CancellationError() }
        queued.append(completion)
    }

    func stop() { queued.removeAll() }
    func finishOne() { queued.removeFirst()() }
}
