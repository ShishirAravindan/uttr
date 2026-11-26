import Foundation

/// The action policy table and the coordinator's interleavings, with fakes for
/// capture, models, selection, speech, paste, and focus. No audio, models,
/// clipboard, or permissions.
@main
struct CoordinationChecks {
    @MainActor
    static func main() async {
        checkPriorityOrder()
        checkTable()
        await checkDictation()
        await checkRecordingOverTranscribing()
        await checkRecordingOverCleaning()
        await checkFocusChange()
        await checkReadAloud()
        await checkReadAloudTransport()
        await checkInstruct()
        await checkPriorityRejections()
        await checkBlockedRecording()
        await checkQuit()
        print("Coordination checks passed")
    }

    static func checkPriorityOrder() {
        precondition(ActionPriority.order == [.stt, .instruct, .tts])
        precondition(ActionRequest.toggleRecord.priority > ActionRequest.instruct.priority)
        precondition(ActionRequest.instruct.priority > ActionRequest.readAloud.priority)
    }

    static func checkTable() {
        let states: [(String, ActionState)] = [
            ("idle", .idle),
            ("capturing", .capturing),
            ("transcribing", .transcribing(run: 1, target: 10)),
            ("cleaning", .cleaning(run: 1, target: 10)),
            ("inserting", .inserting(run: 1, target: 10)),
            ("readingSelection", .readingSelection(run: 1)),
            ("speaking", .speaking(run: 1)),
            ("instructing.reading", .instructing(run: 1, stage: .reading, target: 10)),
            ("instructing.cleaning", .instructing(run: 1, stage: .cleaning, target: 10)),
            ("instructing.inserting", .instructing(run: 1, stage: .inserting, target: 10)),
        ]
        // Columns: record, instruct, readAloud.
        let expected: [String: [ActionDecision]] = [
            "idle": [.accept, .accept, .accept],
            "capturing": [.accept, .reject(.recording), .reject(.recording)],
            "transcribing": [.accept, .reject(.busy), .reject(.busy)],
            "cleaning": [.replace, .reject(.busy), .reject(.busy)],
            "inserting": [.accept, .reject(.busy), .reject(.busy)],
            "readingSelection": [.replace, .replace, .cancel],
            "speaking": [.replace, .replace, .cancel],
            "instructing.reading": [.replace, .reject(.busy), .reject(.busy)],
            "instructing.cleaning": [.replace, .reject(.busy), .reject(.busy)],
            "instructing.inserting": [.accept, .reject(.busy), .reject(.busy)],
        ]
        let requests: [ActionRequest] = [.toggleRecord, .instruct, .readAloud]
        for (name, state) in states {
            let row = expected[name]!
            for (request, want) in zip(requests, row) {
                let got = ActionPolicy.decide(state, request)
                precondition(got == want, "\(name) x \(request): \(got), expected \(want)")
            }
        }

        // Lower priority never preempts higher.
        for (name, state) in states {
            guard let held = state.priority else { continue }
            for request in requests where request.priority < held {
                guard case .reject = ActionPolicy.decide(state, request) else {
                    preconditionFailure("\(request) must not preempt \(name)")
                }
            }
        }
    }
}

// MARK: - Scenarios

extension CoordinationChecks {
    @MainActor
    static func checkDictation() async {
        let h = Harness()
        h.coordinator.request(.toggleRecord)
        precondition(h.coordinator.state == .capturing && h.feedback.renders == [.recording])
        h.coordinator.request(.toggleRecord)
        guard case .transcribing = h.coordinator.state else { preconditionFailure("expected transcribing") }
        await settle()
        h.transcriptions[0].open(.success("hello"))
        await settle()
        precondition(h.pastes == ["hello"])
        precondition(h.coordinator.state == .idle)
        precondition(h.history == ["dictation:hello"])
        precondition(h.feedback.renders == [.recording, .processing], "the success flash replaces a final ready render")
        precondition(h.feedback.reports == [.init(.success, flash: true)])

        // A failed transcription reports and discards the recording.
        let failing = Harness()
        failing.coordinator.request(.toggleRecord)
        failing.coordinator.request(.toggleRecord)
        await settle()
        failing.transcriptions[0].open(.failure(TestError.boom))
        await settle()
        precondition(failing.discarded.count == 1 && failing.pastes.isEmpty)
        precondition(failing.coordinator.state == .idle)
        precondition(failing.feedback.reports.count == 1 && failing.feedback.reports[0].outcome != .success)
    }

    /// The previous dictation still pastes; the recording icon is never stomped.
    @MainActor
    static func checkRecordingOverTranscribing() async {
        let h = Harness()
        h.coordinator.request(.toggleRecord)
        h.coordinator.request(.toggleRecord)
        await settle()
        h.coordinator.request(.toggleRecord)
        precondition(h.coordinator.state == .capturing, "a new recording starts over transcription")
        precondition(h.captures == 2)
        h.transcriptions[0].open(.success("first"))
        await settle()
        precondition(h.pastes == ["first"], "the earlier run still delivers")
        precondition(h.coordinator.state == .capturing)
        precondition(h.feedback.renders.last == .recording, "icon stays on the recording")
        precondition(h.feedback.reports.last == .init(.success, flash: false), "no flash over a recording")
    }

    /// Recording during cleanup delivers the transcript as it was, then records.
    @MainActor
    static func checkRecordingOverCleaning() async {
        let h = Harness()
        h.cleanDictation = true
        h.coordinator.request(.toggleRecord)
        h.coordinator.request(.toggleRecord)
        await settle()
        h.transcriptions[0].open(.success("um raw"))
        await settle()
        guard case .cleaning = h.coordinator.state else { preconditionFailure("expected cleaning") }
        h.coordinator.request(.toggleRecord)
        await settle()
        precondition(h.pastes == ["um raw"], "the raw transcript is delivered")
        precondition(h.coordinator.state == .capturing)
        precondition(h.history == ["dictation:um raw"])
        h.dictationCleanups[0].open(CleanupResult(original: "um raw", text: "Raw.", outcome: .cleaned))
        await settle()
        precondition(h.pastes == ["um raw"], "a late cleanup result is dropped")
        precondition(h.history.count == 1)
    }

    @MainActor
    static func checkFocusChange() async {
        let dictation = Harness()
        dictation.coordinator.request(.toggleRecord)
        dictation.coordinator.request(.toggleRecord)
        await settle()
        dictation.frontmost = 99
        dictation.transcriptions[0].open(.success("hello"))
        await settle()
        precondition(dictation.pastes.isEmpty, "nothing pastes into another app")
        precondition(dictation.clipboard == ["hello"])
        precondition(dictation.history == ["dictation:hello"])
        precondition(dictation.feedback.reports == [.init(.leftOnClipboard, flash: true)])

        let instruct = Harness()
        instruct.coordinator.request(.instruct)
        await settle()
        instruct.selections[0].open("rough text")
        await settle()
        instruct.frontmost = 99
        instruct.selectionCleanups[0].open(.success(CleanupResult(original: "rough text", text: "Rough text.", outcome: .cleaned)))
        await settle()
        precondition(instruct.pastes.isEmpty && instruct.clipboard == ["Rough text."])
        precondition(instruct.history == ["cleanup:Rough text."])
        precondition(instruct.feedback.reports == [.init(.leftOnClipboard, flash: true)])
        precondition(instruct.coordinator.state == .idle)
    }

    @MainActor
    static func checkReadAloud() async {
        // Record right after the shortcut: the read is cancelled, so nothing speaks.
        let h = Harness()
        h.coordinator.request(.readAloud)
        await settle()
        precondition(h.coordinator.state.priority == .tts && h.reads == 1)
        h.coordinator.request(.toggleRecord)
        precondition(h.coordinator.state == .capturing)
        h.selections[0].open("late text")
        await settle()
        precondition(h.spoken.isEmpty, "speech never starts over a recording")
        precondition(h.coordinator.state == .capturing && h.history.isEmpty)

        // Reading, then speaking, then the shortcut again stops it.
        let reader = Harness()
        reader.coordinator.request(.readAloud)
        await settle()
        reader.selections[0].open("hello world")
        await settle()
        precondition(reader.spoken == ["hello world"] && reader.history == ["readAloud:hello world"])
        precondition(reader.coordinator.state.phase == .speaking)
        reader.coordinator.request(.readAloud)
        precondition(reader.stops == 1 && reader.coordinator.state == .idle)

        // Speech ending on its own returns to idle.
        let ending = Harness()
        ending.coordinator.request(.readAloud)
        await settle()
        ending.selections[0].open("done soon")
        await settle()
        ending.speechCompletions[0](.finished)
        precondition(ending.coordinator.state == .idle && ending.feedback.renders.last == .ready)

        // Report failure only for the currently speaking run.
        let restarted = Harness()
        restarted.coordinator.request(.readAloud)
        await settle()
        restarted.selections[0].open("old")
        await settle()
        restarted.coordinator.stopReadAloud()
        restarted.coordinator.request(.readAloud)
        await settle()
        restarted.selections[1].open("new")
        await settle()
        restarted.speechCompletions[0](.failed("stale output error"))
        precondition(restarted.coordinator.state.phase == .speaking && restarted.feedback.reports.isEmpty)
        restarted.speechCompletions[1](.failed("current output error"))
        precondition(restarted.coordinator.state == .idle)
        precondition(restarted.feedback.reports == [.init(.failure("current output error"), flash: true)])

        // Shutdown stops active output and suppresses a late terminal event.
        let quitting = Harness()
        quitting.coordinator.request(.readAloud)
        await settle()
        quitting.selections[0].open("quit during speech")
        await settle()
        quitting.coordinator.shutDown()
        quitting.speechCompletions[0](.failed("failure after quit"))
        precondition(quitting.stops == 1 && quitting.coordinator.state == .idle && quitting.feedback.reports.isEmpty)

        // Nothing selected.
        let empty = Harness()
        empty.coordinator.request(.readAloud)
        await settle()
        empty.selections[0].open(nil)
        await settle()
        precondition(empty.coordinator.state == .idle && empty.feedback.reports.count == 1)

        // Recording replaces speech.
        let speaking = Harness()
        speaking.coordinator.request(.readAloud)
        await settle()
        speaking.selections[0].open("talking")
        await settle()
        speaking.coordinator.request(.toggleRecord)
        precondition(speaking.stops == 1 && speaking.coordinator.state == .capturing)
    }

    @MainActor
    static func checkReadAloudTransport() async {
        let h = Harness()
        var statuses: [ReadAloudPlayback?] = []
        h.coordinator.onReadAloudPlaybackChanged = { statuses.append($0) }

        h.coordinator.stopReadAloud()
        h.coordinator.skipReadAloud()
        precondition(h.stops == 0 && h.skips == 0 && statuses.isEmpty)

        h.coordinator.request(.readAloud)
        await settle()
        precondition(h.coordinator.readAloudPlayback == .readingSelection)
        h.coordinator.skipReadAloud()
        precondition(h.skips == 0)
        h.selections[0].open("two sections")
        await settle()
        precondition(h.coordinator.readAloudPlayback == .buffering(canSkip: false))

        h.coordinator.updateReadAloudPlayback(isBuffering: false, canSkip: true)
        h.coordinator.skipReadAloud()
        precondition(h.skips == 1 && h.history.count == 1)
        h.coordinator.stopReadAloud()
        h.coordinator.updateReadAloudPlayback(isBuffering: false, canSkip: true)
        h.coordinator.skipReadAloud()
        precondition(h.stops == 1 && h.skips == 1 && h.coordinator.state == .idle)
        precondition(statuses == [.readingSelection, .buffering(canSkip: false), .playing(canSkip: true), nil])
        h.coordinator.shutDown()
        await settle()
        precondition(h.voiceCancelled)
    }

    @MainActor
    static func checkInstruct() async {
        // Selection reads never overlap, even when one replaces another.
        let h = Harness()
        h.coordinator.request(.readAloud)
        await settle()
        h.coordinator.request(.instruct)
        await settle()
        precondition(h.readsInFlight == 1 && h.selections.count == 1, "the second read waits for the first")
        h.selections[0].open("stale")
        await settle()
        precondition(h.selections.count == 2 && h.maxReadsInFlight == 1)
        h.selections[1].open("selected")
        await settle()
        h.selectionCleanups[0].open(.success(CleanupResult(original: "selected", text: "Selected.", outcome: .cleaned)))
        await settle()
        precondition(h.pastes == ["Selected."] && h.spoken.isEmpty)

        // A cleanup that throws returns to idle with a failure.
        let failing = Harness()
        failing.coordinator.request(.instruct)
        await settle()
        failing.selections[0].open("text")
        await settle()
        precondition(failing.coordinator.state.phase == .transforming)
        failing.selectionCleanups[0].open(.failure(TestError.boom))
        await settle()
        precondition(failing.coordinator.state == .idle && failing.coordinator.phase == .ready)
        precondition(failing.feedback.reports == [.init(.failure("Cleanup failed"), flash: true)], "the transforming icon is released")

        // Recording during the read or the cleanup cancels it; nothing is pasted.
        let recording = Harness()
        recording.coordinator.request(.instruct)
        await settle()
        recording.selections[0].open("text")
        await settle()
        recording.coordinator.request(.toggleRecord)
        precondition(recording.coordinator.state == .capturing)
        recording.selectionCleanups[0].open(.success(CleanupResult(original: "text", text: "Text.", outcome: .cleaned)))
        await settle()
        precondition(recording.pastes.isEmpty && recording.history.isEmpty)

        // Recording during the paste lets it finish.
        let inserting = Harness()
        inserting.holdPastes = true
        inserting.coordinator.request(.instruct)
        await settle()
        inserting.selections[0].open("text")
        await settle()
        inserting.selectionCleanups[0].open(.success(CleanupResult(original: "text", text: "Text.", outcome: .cleaned)))
        await settle()
        precondition(inserting.coordinator.state.phase == .transforming)
        inserting.coordinator.request(.toggleRecord)
        precondition(inserting.coordinator.state == .capturing)
        inserting.releasePaste()
        await settle()
        precondition(inserting.pastes == ["Text."] && inserting.coordinator.state == .capturing)
        precondition(inserting.feedback.reports.last == .init(.success, flash: false))
    }

    @MainActor
    static func checkPriorityRejections() async {
        // Read-aloud during dictation work, and instructions during recording, are ignored.
        let h = Harness()
        h.coordinator.request(.toggleRecord)
        h.coordinator.request(.instruct)
        h.coordinator.request(.readAloud)
        precondition(h.feedback.ignoredCount == 2 && h.reads == 0 && h.coordinator.state == .capturing)
        h.coordinator.request(.toggleRecord)
        h.coordinator.request(.readAloud)
        precondition(h.feedback.ignoredCount == 3 && h.reads == 0)

        // Instruct during instruct is ignored, not cancelled.
        let instruct = Harness()
        instruct.coordinator.request(.instruct)
        await settle()
        instruct.coordinator.request(.instruct)
        precondition(instruct.feedback.ignoredCount == 1 && instruct.coordinator.state.priority == .instruct)
        instruct.coordinator.request(.readAloud)
        precondition(instruct.feedback.ignoredCount == 2)

        // Instruct is refused while a dictation still cleans up in the background.
        let background = Harness()
        background.cleanDictation = true
        background.coordinator.request(.toggleRecord)
        background.coordinator.request(.toggleRecord)
        await settle()
        background.transcriptions[0].open(.success("words"))
        await settle()
        background.coordinator.request(.instruct)
        precondition(background.feedback.ignoredCount == 1 && background.reads == 0)
    }

    @MainActor
    static func checkBlockedRecording() async {
        // A model that is still loading refuses recording without disturbing speech.
        let h = Harness()
        h.coordinator.request(.readAloud)
        await settle()
        h.selections[0].open("speaking now")
        await settle()
        h.providerReady = false
        h.coordinator.request(.toggleRecord)
        precondition(h.feedback.modelLoadingCount == 1 && h.stops == 0 && h.captures == 0)
        precondition(h.coordinator.state.phase == .speaking)
    }

    @MainActor
    static func checkQuit() async {
        let h = Harness()
        h.cleanDictation = true
        h.coordinator.request(.toggleRecord)
        h.coordinator.request(.toggleRecord)
        await settle()
        h.transcriptions[0].open(.success("kept transcript"))
        await settle()
        h.coordinator.request(.readAloud)
        h.coordinator.shutDown()
        precondition(h.history == ["dictation:kept transcript"], "quit mid-cleanup keeps the transcript")
        h.dictationCleanups[0].open(CleanupResult(original: "kept transcript", text: "Kept.", outcome: .cleaned))
        await settle()
        precondition(h.pastes.isEmpty && h.history.count == 1, "nothing delivers after quit")
        h.coordinator.request(.toggleRecord)
        precondition(h.captures == 1, "requests are ignored after quit")

        let voice = Harness()
        voice.coordinator.request(.readAloud)
        await settle()
        precondition(voice.voicePrepares == 1)
        voice.coordinator.shutDown()
        await settle()
        precondition(voice.voiceCancelled, "voice preparation is cancelled at quit")
    }

    @MainActor
    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }
}

enum TestError: Error { case boom }

// MARK: - Fakes

@MainActor
final class Gate<T> {
    private var continuation: CheckedContinuation<T, Never>?
    private var value: T?
    func wait() async -> T {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
    func open(_ value: T) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
final class FakeFeedback: ActionFeedback {
    struct Report: Equatable {
        let outcome: ActionOutcome
        let flash: Bool
        init(_ outcome: ActionOutcome, flash: Bool) { self.outcome = outcome; self.flash = flash }
    }
    var renders: [StatusPhase] = []
    var reports: [Report] = []
    var ignoredCount = 0
    var modelLoadingCount = 0
    func render(_ phase: StatusPhase) { renders.append(phase) }
    func recordingStarted() {}
    func recordingStopped() {}
    func modelLoading() { modelLoadingCount += 1 }
    func ignored() { ignoredCount += 1 }
    func report(_ outcome: ActionOutcome, flash: Bool) { reports.append(Report(outcome, flash: flash)) }
}

@MainActor
final class Harness {
    var providerReady = true
    var cleanDictation = false
    var frontmost: pid_t = 10
    var holdPastes = false
    var captures = 0
    var stops = 0
    var skips = 0
    var reads = 0
    var readsInFlight = 0
    var maxReadsInFlight = 0
    var voicePrepares = 0
    var voiceCancelled = false
    var pastes: [String] = []
    var clipboard: [String] = []
    var history: [String] = []
    var spoken: [String] = []
    var speechCompletions: [(SpeechCompletion) -> Void] = []
    var discarded: [URL] = []
    var transcriptions: [Gate<Result<String, Error>>] = []
    var dictationCleanups: [Gate<CleanupResult>] = []
    var selections: [Gate<String?>] = []
    var selectionCleanups: [Gate<Result<CleanupResult, Error>>] = []
    private var heldPaste: (@MainActor (Bool) -> Void)?
    let feedback = FakeFeedback()
    private(set) var coordinator: ActionCoordinator!

    init() {
        let logger = Logger(writer: LogWriter(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("uttr-coordination-checks-\(UUID().uuidString).log")))
        let services = ActionServices(
            providerReady: { [unowned self] in providerReady },
            startCapture: { [unowned self] in captures += 1 },
            stopCapture: { URL(fileURLWithPath: "/tmp/uttr-fake-recording.wav") },
            transcribe: { [unowned self] _ in
                let gate = Gate<Result<String, Error>>()
                transcriptions.append(gate)
                return try await gate.wait().get()
            },
            discardAudio: { [unowned self] in discarded.append($0) },
            dictationCleanupEnabled: { [unowned self] in cleanDictation },
            cleanDictation: { [unowned self] _ in
                let gate = Gate<CleanupResult>()
                dictationCleanups.append(gate)
                return await gate.wait()
            },
            accessibilityGranted: { true },
            instructAvailable: { true },
            readSelection: { [unowned self] in
                reads += 1
                readsInFlight += 1
                maxReadsInFlight = max(maxReadsInFlight, readsInFlight)
                let gate = Gate<String?>()
                selections.append(gate)
                let text = await gate.wait()
                readsInFlight -= 1
                return text
            },
            cleanSelection: { [unowned self] _ in
                let gate = Gate<Result<CleanupResult, Error>>()
                selectionCleanups.append(gate)
                return try await gate.wait().get()
            },
            speak: { [unowned self] text, done in
                spoken.append(text)
                speechCompletions.append(done)
            },
            stopSpeech: { [unowned self] in stops += 1 },
            frontmostPID: { [unowned self] in frontmost },
            paste: { [unowned self] text, done in
                if holdPastes {
                    heldPaste = { [unowned self] ok in if ok { pastes.append(text) }; done(ok) }
                } else {
                    pastes.append(text)
                    done(true)
                }
            },
            copyToClipboard: { [unowned self] in clipboard.append($0) },
            record: { [unowned self] record in
                switch record {
                case .dictation(let text, _, _): history.append("dictation:\(text)")
                case .cleanup(let text, _): history.append("cleanup:\(text)")
                case .readAloud(let text): history.append("readAloud:\(text)")
                }
            },
            prepareVoice: { [unowned self] in
                voicePrepares += 1
                let gate = Gate<Void>()
                await withTaskCancellationHandler {
                    await gate.wait()
                } onCancel: {
                    Task { @MainActor in self.voiceCancelled = true; gate.open(()) }
                }
            },
            skipSpeech: { [unowned self] in skips += 1 }
        )
        coordinator = ActionCoordinator(services: services, feedback: feedback, logger: logger)
    }

    func releasePaste() { heldPaste?(true); heldPaste = nil }
}
