import Combine
import XCTest

final class TranscriptionSessionTests: XCTestCase {
    @MainActor
    func testOneUtteranceWaitsForTranscriptionAndPaste() async {
        let fixture = await readyFixture()
        let transcript = Deferred<String>()
        fixture.provider.transcript = transcript
        fixture.paste.automaticallyComplete = false
        fixture.session.toggleRecording()
        XCTAssertTrue(fixture.session.state.isRecording)
        fixture.session.toggleRecording()
        await fulfillment(of: [transcript.started], timeout: 3)

        fixture.session.toggleRecording()
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.starts, 1)
        transcript.resolve(.success("A thought to keep."))
        await wait(for: .inserting(text: "A thought to keep."), in: fixture.session)
        fixture.session.toggleRecording()
        XCTAssertEqual(fixture.recorder.starts, 1)
        XCTAssertEqual(fixture.history, ["A thought to keep."])
        XCTAssertEqual(fixture.paste.texts, ["A thought to keep."])

        fixture.paste.complete(true)
        await wait(for: .idle, in: fixture.session)
        fixture.session.toggleRecording()
        XCTAssertEqual(fixture.recorder.starts, 2)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testLoadingBlocksCaptureAndFailureCanRecoverWithAnotherProvider() async {
        let fixture = Fixture()
        let preparation = Deferred<Void>()
        fixture.provider.preparation = preparation
        fixture.session.prepare()
        await fulfillment(of: [preparation.started], timeout: 3)
        fixture.session.toggleRecording()
        XCTAssertEqual(fixture.recorder.starts, 0)
        preparation.resolve(.failure(TestFailure.expected))
        await waitUntilUnavailable(fixture.session)
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.starts, 0)

        let replacement = TestProvider()
        fixture.session.changeProvider(replacement)
        await wait(for: .idle, in: fixture.session)
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.starts, 1)
        XCTAssertEqual(fixture.provider.teardowns, 1)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testStartFailureReleasesRecorderAndAllowsRetry() async {
        let fixture = await readyFixture()
        fixture.recorder.startError = TestFailure.expected
        fixture.session.startRecording()
        XCTAssertEqual(fixture.session.state, .idle)
        XCTAssertEqual(fixture.recorder.stops, 1)
        XCTAssertEqual(fixture.history, [])
        fixture.recorder.startError = nil
        fixture.session.startRecording()
        XCTAssertTrue(fixture.session.state.isRecording)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testMissingRecordingFileDoesNotLeaveSessionStuck() async {
        let fixture = await readyFixture()
        fixture.recorder.url = nil
        fixture.session.startRecording()
        fixture.session.stopRecording()
        XCTAssertEqual(fixture.session.state, .idle)
        XCTAssertEqual(fixture.provider.transcriptions, 0)
        fixture.session.toggleRecording()
        XCTAssertEqual(fixture.recorder.starts, 2)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testInterruptionRecoversAndOldCallbackCannotStopNewCapture() async {
        let fixture = await readyFixture()
        fixture.session.startRecording()
        let interrupted = fixture.recorder.onInterrupted
        interrupted?()
        await wait(for: .idle, in: fixture.session)
        fixture.session.startRecording()
        interrupted?()
        // Let the old callback run, then inspect state through the actor queue.
        await Task { @MainActor in }.value
        XCTAssertTrue(fixture.session.state.isRecording)
        XCTAssertEqual(fixture.recorder.starts, 2)
        XCTAssertEqual(fixture.provider.transcriptions, 0)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testTranscriptionFailureDoesNotPasteAndNextUtteranceWorks() async {
        let fixture = await readyFixture()
        fixture.provider.transcriptionError = TestFailure.expected
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await wait(for: .idle, in: fixture.session)
        XCTAssertEqual(fixture.paste.texts, [])
        XCTAssertEqual(fixture.history, [])
        fixture.provider.transcriptionError = nil
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await wait(for: .idle, in: fixture.session)
        XCTAssertEqual(fixture.paste.texts, ["Transcript"])
        await fixture.session.shutDown().value
    }

    @MainActor
    func testPasteFailureKeepsHistoryAndAllowsRetry() async {
        let fixture = await readyFixture()
        fixture.paste.result = false
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await wait(for: .idle, in: fixture.session)
        XCTAssertEqual(fixture.history, ["Transcript"])
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.starts, 2)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testProviderChangesWaitForCaptureAndPasteAndUseLatestRequest() async {
        let fixture = await readyFixture()
        fixture.paste.automaticallyComplete = false
        let superseded = TestProvider()
        let latest = TestProvider()
        let preparation = Deferred<Void>()
        latest.preparation = preparation
        fixture.session.startRecording()
        fixture.session.changeProvider(superseded)
        fixture.session.changeProvider(latest)
        XCTAssertEqual(latest.prepares, 0)
        XCTAssertEqual(fixture.provider.teardowns, 0)
        fixture.session.stopRecording()
        await wait(for: .inserting(text: "Transcript"), in: fixture.session)
        XCTAssertEqual(latest.prepares, 0)
        fixture.paste.complete(true)
        await fulfillment(of: [preparation.started], timeout: 3)
        XCTAssertEqual(fixture.provider.teardowns, 1)
        XCTAssertEqual(superseded.prepares, 0)
        XCTAssertEqual(superseded.teardowns, 0)
        preparation.resolve(.success(()))
        await wait(for: .idle, in: fixture.session)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testProviderSwitchDuringInferenceDoesNotTeardownActiveProvider() async {
        let fixture = await readyFixture()
        let transcript = Deferred<String>()
        fixture.provider.transcript = transcript
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await fulfillment(of: [transcript.started], timeout: 3)
        let replacement = TestProvider()
        let preparation = Deferred<Void>()
        replacement.preparation = preparation
        fixture.session.changeProvider(replacement)
        XCTAssertEqual(fixture.provider.teardowns, 0)
        transcript.resolve(.success("Keep this utterance"))
        await fulfillment(of: [preparation.started], timeout: 3)
        XCTAssertEqual(fixture.history, ["Keep this utterance"])
        XCTAssertEqual(fixture.paste.texts, ["Keep this utterance"])
        XCTAssertFalse(fixture.provider.tornDownWhileInUse)
        preparation.resolve(.success(()))
        await wait(for: .idle, in: fixture.session)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testProviderChangeDuringInsertionWaitsForItsCompletion() async {
        let fixture = await readyFixture()
        fixture.paste.automaticallyComplete = false
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await wait(for: .inserting(text: "Transcript"), in: fixture.session)
        let replacement = TestProvider()
        let preparation = Deferred<Void>()
        replacement.preparation = preparation
        fixture.session.changeProvider(replacement)
        XCTAssertEqual(fixture.provider.teardowns, 0)
        fixture.paste.complete(false)
        await fulfillment(of: [preparation.started], timeout: 3)
        preparation.resolve(.success(()))
        await wait(for: .idle, in: fixture.session)
        XCTAssertEqual(fixture.history, ["Transcript"])
        await fixture.session.shutDown().value
    }

    @MainActor
    func testSupersededPreparationCannotPublishSuccessOrFailure() async {
        for outcome: Result<Void, Error> in [.success(()), .failure(TestFailure.expected)] {
            let fixture = Fixture()
            let oldPreparation = Deferred<Void>()
            fixture.provider.preparation = oldPreparation
            fixture.session.prepare()
            await fulfillment(of: [oldPreparation.started], timeout: 3)
            let replacement = TestProvider()
            let newPreparation = Deferred<Void>()
            replacement.preparation = newPreparation
            fixture.session.changeProvider(replacement)
            oldPreparation.resolve(outcome)
            await fulfillment(of: [newPreparation.started], timeout: 3)
            XCTAssertEqual(fixture.session.state, .loading)
            XCTAssertEqual(fixture.readyEvents, 0)
            XCTAssertEqual(fixture.failureEvents, 0)
            XCTAssertFalse(fixture.provider.tornDownWhileInUse)
            newPreparation.resolve(.success(()))
            await wait(for: .idle, in: fixture.session)
            XCTAssertEqual(fixture.readyEvents, 1)
            await fixture.session.shutDown().value
        }
    }

    @MainActor
    func testRapidProviderChangesSkipSupersededPreparation() async {
        let fixture = Fixture()
        let oldPreparation = Deferred<Void>()
        fixture.provider.preparation = oldPreparation
        fixture.session.prepare()
        await fulfillment(of: [oldPreparation.started], timeout: 3)
        let intermediate = TestProvider()
        let latest = TestProvider()
        let latestPreparation = Deferred<Void>()
        latest.preparation = latestPreparation
        fixture.session.changeProvider(intermediate)
        fixture.session.changeProvider(latest)
        oldPreparation.resolve(.success(()))
        await fulfillment(of: [latestPreparation.started], timeout: 3)
        XCTAssertEqual(intermediate.prepares, 0)
        XCTAssertEqual(fixture.provider.teardowns, 1)
        XCTAssertFalse(fixture.provider.tornDownWhileInUse)
        latestPreparation.resolve(.success(()))
        await wait(for: .idle, in: fixture.session)
        await fixture.session.shutDown().value
    }

    @MainActor
    func testShutdownDuringPreparationSuppressesReadinessAndWaitsForTeardown() async {
        let fixture = Fixture()
        let preparation = Deferred<Void>()
        fixture.provider.preparation = preparation
        fixture.session.prepare()
        await fulfillment(of: [preparation.started], timeout: 3)
        let shutdown = fixture.session.shutDown()
        XCTAssertEqual(fixture.session.state, .stopped)
        XCTAssertEqual(fixture.provider.teardowns, 0)
        preparation.resolve(.success(()))
        await shutdown.value
        XCTAssertEqual(fixture.readyEvents, 0)
        XCTAssertEqual(fixture.provider.teardowns, 1)
        XCTAssertFalse(fixture.provider.tornDownWhileInUse)
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.starts, 0)
    }

    @MainActor
    func testShutdownStopsCaptureAndIsIdempotent() async {
        let fixture = await readyFixture()
        fixture.session.startRecording()
        let first = fixture.session.shutDown()
        let second = fixture.session.shutDown()
        await first.value
        await second.value
        XCTAssertEqual(fixture.recorder.stops, 1)
        XCTAssertEqual(fixture.provider.teardowns, 1)
        XCTAssertEqual(fixture.provider.transcriptions, 0)
        XCTAssertEqual(fixture.session.state, .stopped)
    }

    @MainActor
    func testShutdownDuringInferenceCannotDeliverLateText() async {
        let fixture = await readyFixture()
        let transcript = Deferred<String>()
        fixture.provider.transcript = transcript
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await fulfillment(of: [transcript.started], timeout: 3)
        let shutdown = fixture.session.shutDown()
        XCTAssertEqual(fixture.provider.teardowns, 0)
        transcript.resolve(.success("Too late"))
        await shutdown.value
        XCTAssertEqual(fixture.session.state, .stopped)
        XCTAssertEqual(fixture.paste.texts, [])
        XCTAssertEqual(fixture.history, [])
        XCTAssertEqual(fixture.provider.teardowns, 1)
        XCTAssertFalse(fixture.provider.tornDownWhileInUse)
    }

    @MainActor
    func testShutdownDuringInsertionIgnoresLatePasteCallback() async {
        let fixture = await readyFixture()
        fixture.paste.automaticallyComplete = false
        fixture.session.startRecording()
        fixture.session.stopRecording()
        await wait(for: .inserting(text: "Transcript"), in: fixture.session)
        await fixture.session.shutDown().value
        fixture.paste.complete(true)
        await Task { @MainActor in }.value
        XCTAssertEqual(fixture.session.state, .stopped)
        XCTAssertEqual(fixture.insertedEvents, 0)
    }

    @MainActor
    func testInputDeviceSelectionIsHandedToRecorder() async {
        let fixture = await readyFixture()
        fixture.session.setInputDevice(uid: "chosen-device")
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.devicesAtStart, ["chosen-device"])
        fixture.session.setInputDevice(uid: nil)
        fixture.session.stopRecording()
        await wait(for: .idle, in: fixture.session)
        fixture.session.startRecording()
        XCTAssertEqual(fixture.recorder.devicesAtStart, ["chosen-device", nil])
        await fixture.session.shutDown().value
    }

    @MainActor
    private func readyFixture() async -> Fixture {
        let fixture = Fixture()
        fixture.session.prepare()
        await wait(for: .idle, in: fixture.session)
        return fixture
    }

    @MainActor
    private func wait(for state: SessionState, in session: TranscriptionSession) async {
        await waitForState(in: session) { $0 == state }
    }

    @MainActor
    private func waitUntilUnavailable(_ session: TranscriptionSession) async {
        await waitForState(in: session) {
            if case .unavailable = $0 { return true }
            return false
        }
    }

    @MainActor
    private func waitForState(in session: TranscriptionSession, matching predicate: @escaping (SessionState) -> Bool) async {
        if predicate(session.state) { return }
        let reached = expectation(description: "Session reaches expected state")
        let observation = session.$state.filter(predicate).sink { _ in reached.fulfill() }
        await fulfillment(of: [reached], timeout: 3)
        observation.cancel()
        XCTAssertTrue(predicate(session.state), "Unexpected state: \(session.state)")
    }
}

// MARK: - Controlled platform effects

private enum TestFailure: Error { case expected }

@MainActor
private final class Deferred<Value> {
    let started = XCTestExpectation(description: "Operation suspended")
    private var continuation: CheckedContinuation<Value, Error>?

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

private final class TestRecorder: SessionRecording {
    var preferredInputDeviceUID: String?
    var onInterrupted: (() -> Void)?
    var starts = 0
    var stops = 0
    var devicesAtStart: [String?] = []
    var startError: Error?
    var url: URL? = URL(fileURLWithPath: "/unused/recording.wav")

    func startRecording() throws {
        starts += 1
        devicesAtStart.append(preferredInputDeviceUID)
        if let startError { throw startError }
    }

    func stopRecording() -> URL? {
        stops += 1
        return url
    }
}

@MainActor
private final class TestProvider: TranscriptionProvider {
    let id = UUID().uuidString
    let displayName = "Test provider"
    var preparation: Deferred<Void>?
    var transcript: Deferred<String>?
    var transcriptionError: Error?
    var prepares = 0
    var transcriptions = 0
    var teardowns = 0
    var tornDownWhileInUse = false
    private var inUse = false

    func prepare() async throws {
        prepares += 1
        inUse = true
        defer { inUse = false }
        if let preparation { try await preparation.value() }
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        transcriptions += 1
        inUse = true
        defer { inUse = false }
        if let transcriptionError { throw transcriptionError }
        if let transcript { return try await transcript.value() }
        return "Transcript"
    }

    func teardown() async {
        tornDownWhileInUse = tornDownWhileInUse || inUse
        teardowns += 1
    }
}

private final class TestPaste: SessionPasting {
    var texts: [String] = []
    var automaticallyComplete = true
    var result = true
    private var completion: ((Bool) -> Void)?

    func pasteText(_ text: String, completion: @escaping (Bool) -> Void) {
        texts.append(text)
        if automaticallyComplete { completion(result) } else { self.completion = completion }
    }

    func complete(_ success: Bool) {
        let completion = self.completion
        self.completion = nil
        completion?(success)
    }
}

@MainActor
private final class Fixture {
    let recorder = TestRecorder()
    let provider = TestProvider()
    let paste = TestPaste()
    let session: TranscriptionSession
    var history: [String] = []
    var readyEvents = 0
    var failureEvents = 0
    var insertedEvents = 0

    init() {
        session = TranscriptionSession(recorder: recorder, provider: provider, pasteManager: paste)
        session.onEvent = { [weak self] event in
            switch event {
            case .transcribed(let text, let audioFileName):
                XCTAssertEqual(audioFileName, "recording.wav")
                self?.history.append(text)
            case .providerReady: self?.readyEvents += 1
            case .providerFailed: self?.failureEvents += 1
            case .inserted: self?.insertedEvents += 1
            default: break
            }
        }
    }
}
