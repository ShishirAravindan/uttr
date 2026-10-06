import Combine
import Foundation
import XCTest

final class TranscriptCleanupTests: XCTestCase {
    @MainActor
    func testUnavailableAndLongInputUseRawWithoutGeneration() async throws {
        let backend = CleanupFake()
        backend.isAvailable = false
        let cleanup = TranscriptCleanup(backend: backend)
        let result = try await cleanup.clean("A thought.")
        XCTAssertEqual(result.outcome, .unavailable)
        XCTAssertEqual(result.text, "A thought.")
        backend.isAvailable = true
        backend.supportsText = false
        let unsupported = try await cleanup.clean("Unsupported language")
        XCTAssertEqual(unsupported.outcome, .unsupportedLanguage)
        XCTAssertEqual(unsupported.text, "Unsupported language")
        backend.supportsText = true
        let long = String(repeating: "A", count: 4001)
        let skipped = try await cleanup.clean(long)
        XCTAssertEqual(skipped.outcome, .tooLong)
        XCTAssertEqual(skipped.text, long)
        XCTAssertEqual(backend.calls, [])
    }

    @MainActor
    func testSuccessKeepsRawAndDeliversOnlyCleanedText() async throws {
        let backend = CleanupFake()
        backend.output = "Keep the original."
        let result = try await TranscriptCleanup(backend: backend).clean("Um keep the original.")
        XCTAssertEqual(result.outcome, .cleaned)
        XCTAssertEqual(result.rawText, "Um keep the original.")
        XCTAssertEqual(result.text, "Keep the original.")
    }

    @MainActor
    func testFailureAndInvalidOutputFallBackWithoutLosingRawText() async throws {
        for output in ["", String(repeating: "Unexpected expansion", count: 20)] {
            let backend = CleanupFake()
            backend.output = output
            let result = try await TranscriptCleanup(backend: backend).clean("Do not delete it.")
            XCTAssertEqual(result.outcome, .invalidOutput)
            XCTAssertEqual(result.text, "Do not delete it.")
        }
        let backend = CleanupFake()
        backend.fails = true
        let result = try await TranscriptCleanup(backend: backend).clean("Do not delete it.")
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.text, "Do not delete it.")
    }

    @MainActor
    func testDeadlineDoesNotWaitForUncooperativeModelOrStartAnotherGeneration() async throws {
        let backend = CleanupFake()
        backend.suspended = true
        let cleanup = TranscriptCleanup(backend: backend, timeoutNanoseconds: 20_000_000)
        let request = Task { try await cleanup.clean("Raw first") }
        await fulfillment(of: [backend.started], timeout: 3)
        let result = try await request.value
        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertEqual(result.text, "Raw first")
        let second = try await cleanup.clean("Raw second")
        XCTAssertEqual(second.outcome, .busy)
        XCTAssertEqual(second.text, "Raw second")
        XCTAssertEqual(backend.calls.count, 1)
        backend.resolve("Late first")
        await cleanup.shutDown()
        backend.suspended = false
        backend.output = "Next"
        let next = try await cleanup.clean("Next raw")
        XCTAssertEqual(next.text, "Next")
        XCTAssertEqual(backend.calls.count, 2)
    }

    @MainActor
    func testCancellationReturnsBeforeUncooperativeGenerationEnds() async throws {
        let backend = CleanupFake()
        backend.suspended = true
        let cleanup = TranscriptCleanup(backend: backend)
        let request = Task { try await cleanup.clean("Raw") }
        await fulfillment(of: [backend.started], timeout: 3)
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled cleanup must not succeed") }
        catch { XCTAssertTrue(error is CancellationError) }
        backend.resolve("Too late")
        await cleanup.shutDown()
    }

    @MainActor
    func testLateGenerationLosesEvenWhenTimerHasNotRun() async throws {
        let cleanup = TranscriptCleanup(backend: CleanupFake(), timeoutNanoseconds: 0,
                                        waitForDeadline: { _ in try await Task.sleep(nanoseconds: 1_000_000_000) })
        let result = try await cleanup.clean("Raw text")
        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertEqual(result.text, "Raw text")
    }

    @MainActor
    func testSessionWaitsThroughCleanupAndQueuesProviderSwitchUntilPaste() async throws {
        let fixture = CleanupSessionFixture()
        fixture.backend.suspended = true
        fixture.session.prepare()
        await idle(fixture.session)
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await fulfillment(of: [fixture.backend.started], timeout: 3)
        XCTAssertEqual(fixture.session.state, .cleaning)
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.starts, 1)
        let replacement = CleanupASR()
        fixture.session.changeProvider(replacement)
        XCTAssertEqual(replacement.prepares, 0)
        fixture.backend.resolve("Keep the thought.")
        await idle(fixture.session)
        XCTAssertEqual(fixture.paste.texts, ["Keep the thought."])
        XCTAssertEqual(fixture.history.first?.rawText, "Um keep the thought.")
        XCTAssertEqual(fixture.history.first?.text, "Keep the thought.")
        XCTAssertEqual(replacement.prepares, 1)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testShutdownDuringCleanupSuppressesLateHistoryAndPaste() async throws {
        let fixture = CleanupSessionFixture()
        fixture.backend.suspended = true
        fixture.session.prepare()
        await idle(fixture.session)
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await fulfillment(of: [fixture.backend.started], timeout: 3)
        let shutdown = fixture.session.shutDown()
        fixture.backend.resolve("Late cleanup")
        await shutdown.value
        XCTAssertEqual(fixture.session.state, .stopped)
        XCTAssertTrue(fixture.paste.texts.isEmpty)
        XCTAssertTrue(fixture.history.isEmpty)
    }

    @MainActor
    func testSessionTimeoutPastesRawOnceAndLateResultCannotReplaceAnotherUtterance() async throws {
        let fixture = CleanupSessionFixture(timeoutNanoseconds: 20_000_000)
        fixture.backend.suspended = true
        fixture.session.prepare()
        await idle(fixture.session)
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await fulfillment(of: [fixture.backend.started], timeout: 3)
        await idle(fixture.session)
        XCTAssertEqual(fixture.history.map(\.outcome), [.timedOut])
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await idle(fixture.session)
        XCTAssertEqual(fixture.history.map(\.outcome), [.timedOut, .busy])
        XCTAssertEqual(fixture.paste.texts, ["Um keep the thought.", "Um keep the thought."])
        fixture.backend.resolve("Late text must not be pasted")
        await fixture.session.shutDown().value
        XCTAssertEqual(fixture.history.count, 2)
        XCTAssertEqual(fixture.paste.texts.count, 2)
    }

    func testOldHistoryDecodesAndNewHistoryRetainsBothVersions() throws {
        let entry = TranscriptionEntry(text: "Cleaned.", rawText: "Um cleaned.")
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptionEntry.self, from: data)
        XCTAssertEqual(decoded.text, "Cleaned.")
        XCTAssertEqual(decoded.originalText, "Um cleaned.")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "rawText")
        let legacy = try JSONDecoder().decode(TranscriptionEntry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.rawText)
        XCTAssertEqual(legacy.originalText, "Cleaned.")
        XCTAssertNil(TranscriptionEntry(text: "Same", rawText: "Same").rawText)
    }

    func testOutputChecksKeepScriptsEmphasisAndTechnicalLiterals() {
        XCTAssertFalse(CleanupOutput.accepts("Tomorrow morning.", for: "நாளை காலை."))
        XCTAssertFalse(CleanupOutput.accepts("This is very important.", for: "This is very very important."))
        XCTAssertFalse(CleanupOutput.accepts("Call getUserByID.", for: "Call getUserById."))
        XCTAssertFalse(CleanupOutput.accepts("Use 0.1.8.", for: "Use 0.1.7."))
        XCTAssertFalse(CleanupOutput.accepts("Save the file.", for: "Save /tmp/output.json."))
        XCTAssertFalse(CleanupOutput.accepts("Keep 5 entries and wait 2 seconds.", for: "Keep 5 entries and wait 2 seconds, not 20."))
        XCTAssertFalse(CleanupOutput.accepts("Delete the original.", for: "Do not delete the original."))
        XCTAssertFalse(CleanupOutput.accepts("Can you explain why.", for: "Can you explain why?"))
        XCTAssertTrue(CleanupOutput.accepts("I think कल सुबह we should try again.", for: "Um I think कल सुबह we should try again."))
        XCTAssertTrue(CleanupOutput.accepts("We should move history.", for: "We should we should move history."))
    }

    @MainActor
    private func idle(_ session: TranscriptionSession) async {
        if session.state == .idle { return }
        let reached = expectation(description: "Idle")
        let observation = session.$state.filter { $0 == .idle }.prefix(1).sink { _ in reached.fulfill() }
        await fulfillment(of: [reached], timeout: 3)
        observation.cancel()
        await Task { @MainActor in }.value
    }
}

private enum CleanupTestError: Error { case expected }

@MainActor
private final class CleanupFake: CleanupGenerating {
    var isAvailable = true
    var supportsText = true
    var output = "Cleaned."
    var fails = false
    var suspended = false
    var calls: [String] = []
    let started = XCTestExpectation(description: "Cleanup generation suspended")
    private var continuation: CheckedContinuation<String, Never>?

    func supports(_ text: String) -> Bool { supportsText }

    func generate(_ text: String) async throws -> String {
        calls.append(text)
        if fails { throw CleanupTestError.expected }
        if suspended {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        return output
    }
    func resolve(_ text: String) { continuation?.resume(returning: text); continuation = nil }
}

private final class CleanupRecorder: SessionRecording {
    var preferredInputDeviceUID: String?
    var onInterrupted: (() -> Void)?
    var starts = 0
    func startRecording() throws { starts += 1 }
    func stopRecording() -> URL? { URL(fileURLWithPath: "/unused/audio.wav") }
}
@MainActor
private final class CleanupASR: TranscriptionProvider {
    let id = "cleanup-asr-test"
    let displayName = "Test ASR"
    var prepares = 0
    func prepare() async throws { prepares += 1 }
    func transcribe(audioFileURL: URL) async throws -> String { "Um keep the thought." }
    func teardown() async { }
}
private final class CleanupPaste: SessionPasting {
    var texts: [String] = []
    func pasteText(_ text: String, completion: @escaping (Bool) -> Void) { texts.append(text); completion(true) }
}
@MainActor
private final class CleanupSessionFixture {
    let backend = CleanupFake()
    let recorder = CleanupRecorder()
    let paste = CleanupPaste()
    let session: TranscriptionSession
    var history: [TranscriptCleanupResult] = []
    init(timeoutNanoseconds: UInt64 = 2_000_000_000) {
        session = TranscriptionSession(recorder: recorder, provider: CleanupASR(), pasteManager: paste,
                                       removeRecording: { _ in }, cleaner: TranscriptCleanup(backend: backend, timeoutNanoseconds: timeoutNanoseconds))
        session.onEvent = { [weak self] event in
            if case .transcribed(let result, _) = event { self?.history.append(result) }
        }
    }
}
