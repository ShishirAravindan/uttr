import Foundation

/// Runs the cleanup engine against a fake backend. No model, clipboard, or history.
@main
struct CleanupEngineChecks {
    @MainActor
    static func main() async throws {
        // A broken deadline hangs instead of failing; fail it instead.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 30)
            FileHandle.standardError.write(Data("Cleanup checks timed out\n".utf8))
            exit(1)
        }
        try await checkSkips()
        try await checkCleaned()
        try await checkFailure()
        try await checkGeneralRejections()
        try await checkSpeechRejections()
        try await checkDeadlineAndBusy()
        try await checkCancellationAndShutDown()
        print("Cleanup checks passed")
    }

    @MainActor
    static func checkSkips() async throws {
        let backend = FakeBackend()
        let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
        try await expect(cleanup, "  \n", .unchanged, text: "  \n")
        backend.isAvailable = false
        try await expect(cleanup, "A thought.", .unavailable, text: "A thought.")
        backend.isAvailable = true
        backend.supportsText = false
        try await expect(cleanup, "Une pensée.", .unsupportedLanguage, text: "Une pensée.")
        backend.supportsText = true
        let long = String(repeating: "A", count: TextCleanup.maxCharacters + 1)
        try await expect(cleanup, long, .tooLong, text: long)
        precondition(backend.calls.isEmpty)
    }

    @MainActor
    static func checkCleaned() async throws {
        let backend = FakeBackend()
        let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
        backend.output = "  I think we should ship.  "
        let result = try await cleanup.clean("Um I think we should ship.\n", instructions: "Clean.", profile: .dictation)
        precondition(result.outcome == .cleaned)
        precondition(result.original == "Um I think we should ship.\n")
        precondition(result.text == "I think we should ship.\n")
        precondition(backend.calls == ["Um I think we should ship."])
        precondition(backend.instructions == ["Clean."])

        backend.output = "Already clean."
        try await expect(cleanup, "Already clean.", .unchanged, text: "Already clean.")
    }

    @MainActor
    static func checkFailure() async throws {
        let backend = FakeBackend()
        backend.error = URLError(.unknown)
        let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
        try await expect(cleanup, "Um, keep this.", .failed, text: "Um, keep this.")
    }

    @MainActor
    static func checkGeneralRejections() async throws {
        let cases: [(String, String)] = [
            ("Um, keep this.", ""),
            ("Short one.", String(repeating: "Unexpected expansion. ", count: 5)),
            ("Set the limit to 15 entries.", "Set the limit to entries."),
            ("It takes 2 seconds, not 20.", "It takes 2 seconds."),
            ("It might work, but I'm not sure.", "It might work, but I'm sure."),
            ("I can’t make it.", "I can make it."),
            ("Say नमस्ते to them.", "Say hello to them."),
            ("Open ~/Library/Logs/uttr now.", "Open the logs now."),
            ("Rename max_entries please.", "Rename max entries please."),
            ("See https://example.com/a for details.", "See the site for details."),
            ("Can you explain why the logger is racing?", "The logger is racing."),
        ]
        for profile in [CleanupProfile.selection, .dictation] {
            for (input, output) in cases {
                let backend = FakeBackend()
                backend.output = output
                let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
                try await expect(cleanup, input, .rejected, text: input, profile: profile)
            }
        }
    }

    @MainActor
    static func checkSpeechRejections() async throws {
        let cases: [(String, String)] = [
            ("Do it twice no three times.", "Do it twice."),
            ("This is very very important.", "This is very important."),
            ("We could maybe wait until Friday.", "We could wait until Friday."),
        ]
        for (input, output) in cases {
            let backend = FakeBackend()
            backend.output = output
            let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
            try await expect(cleanup, input, .rejected, text: input, profile: .dictation)
            // An edited prompt may legitimately do these to typed text.
            try await expect(cleanup, input, .cleaned, text: output, profile: .selection)
        }

        for (input, output) in [("Um, do not delete the original file.", "Don't delete the original file."),
                                ("I can not make it.", "I cannot make it.")] {
            let backend = FakeBackend()
            backend.output = output
            let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
            try await expect(cleanup, input, .cleaned, text: output, profile: .dictation)
        }

        let backend = FakeBackend()
        backend.output = "Let's meet on Wednesday at three."
        let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
        try await expect(cleanup, "Let's meet on Tuesday no Wednesday at three.", .cleaned,
                         text: "Let's meet on Wednesday at three.", profile: .dictation)
    }

    @MainActor
    static func checkDeadlineAndBusy() async throws {
        let backend = FakeBackend()
        backend.hold = true
        let gate = DeadlineGate()
        let cleanup = TextCleanup(backend: backend, waitForDeadline: gate.wait)
        try await expect(cleanup, "Um, a slow model.", .timedOut, text: "Um, a slow model.")
        // The abandoned generation ignores cancellation and still runs; nothing stacks up.
        try await expect(cleanup, "Um, another request.", .busy, text: "Um, another request.")
        precondition(backend.calls == ["Um, a slow model."])

        backend.output = "A slow model."
        backend.release()
        await cleanup.shutDown()
        gate.expires = false
        backend.output = "Another request."
        try await expect(cleanup, "Um, another request.", .cleaned, text: "Another request.")
    }

    @MainActor
    static func checkCancellationAndShutDown() async throws {
        let backend = FakeBackend()
        backend.hold = true
        let cleanup = TextCleanup(backend: backend, waitForDeadline: neverExpires)
        let request = Task { try await cleanup.clean("Um, cancel me.", instructions: "", profile: .selection) }
        await settle()
        request.cancel()
        do {
            _ = try await request.value
            preconditionFailure("A cancelled request should throw")
        } catch is CancellationError {}

        var finished = false
        let shutDown = Task { await cleanup.shutDown(); finished = true }
        await settle()
        precondition(!finished, "shutDown must wait for the outstanding generation")
        backend.release()
        await shutDown.value
        precondition(finished)
    }

    // MARK: - Helpers

    static let neverExpires: (UInt64) async throws -> Void = { _ in try await Task.sleep(nanoseconds: 60_000_000_000) }

    @MainActor
    static func expect(_ cleanup: TextCleanup, _ input: String, _ outcome: CleanupOutcome, text: String,
                       profile: CleanupProfile = .dictation) async throws {
        let result = try await cleanup.clean(input, instructions: "Clean.", profile: profile)
        precondition(result.outcome == outcome, "\(input): expected \(outcome), got \(result.outcome)")
        precondition(result.text == text, "\(input): delivered \(result.text)")
        precondition(result.original == input)
    }

    @MainActor
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
final class FakeBackend: CleanupGenerating {
    var isAvailable = true
    var supportsText = true
    var output = ""
    var error: Error?
    var hold = false
    private(set) var calls: [String] = []
    private(set) var instructions: [String] = []
    private var held: [CheckedContinuation<Void, Never>] = []

    func supports(_ text: String) -> Bool { supportsText }

    /// Ignores cancellation while held, like a model that keeps generating.
    func generate(_ text: String, instructions: String) async throws -> String {
        calls.append(text)
        self.instructions.append(instructions)
        if hold { await withCheckedContinuation { held.append($0) } }
        if let error { throw error }
        return output
    }

    func release() {
        hold = false
        held.forEach { $0.resume() }
        held.removeAll()
    }
}

/// Expires deadlines at once until told otherwise.
final class DeadlineGate: @unchecked Sendable {
    var expires = true

    func wait(_ nanoseconds: UInt64) async throws {
        if !expires { try await Task.sleep(nanoseconds: 60_000_000_000) }
    }
}
