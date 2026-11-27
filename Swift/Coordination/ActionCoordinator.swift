import Foundation

enum HistoryRecord {
    case dictation(text: String, audioFileName: String?, original: String?)
    case cleanup(text: String, original: String)
    case readAloud(text: String)
}

enum ActionOutcome: Equatable {
    case success
    /// The frontmost app changed, so the text waits on the clipboard instead.
    case leftOnClipboard
    case failure(String)
}

enum Delivery: Equatable {
    case pasted, failed, leftOnClipboard
}

/// Status feedback, driven from coordinator transitions only.
@MainActor
protocol ActionFeedback: AnyObject {
    func render(_ phase: StatusPhase)
    func recordingStarted()
    func recordingStopped()
    func modelLoading()
    func ignored()
    /// `flash` is false when something else owns the icon, so a finished run never
    /// covers a recording in progress.
    func report(_ outcome: ActionOutcome, flash: Bool)
}

/// Everything the coordinator touches outside itself, so tests can substitute fakes.
@MainActor
struct ActionServices {
    typealias VoicePreparation = @MainActor (() -> Void) async -> Void
    var providerReady: @MainActor () -> Bool
    var startCapture: @MainActor () throws -> Void
    var stopCapture: @MainActor () -> URL?
    var transcribe: @MainActor (URL) async throws -> String
    var discardAudio: @MainActor (URL) -> Void
    var dictationCleanupEnabled: @MainActor () -> Bool
    var cleanDictation: @MainActor (String) async -> CleanupResult
    var accessibilityGranted: @MainActor () -> Bool
    var instructAvailable: @MainActor () -> Bool
    var readSelection: @MainActor () async -> String?
    var cleanSelection: @MainActor (String) async throws -> CleanupResult
    var speak: @MainActor (String, @escaping (SpeechCompletion) -> Void) -> Void
    var stopSpeech: @MainActor () -> Void
    var frontmostPID: @MainActor () -> pid_t?
    var paste: @MainActor (String, @escaping @MainActor (Bool) -> Void) -> Void
    var copyToClipboard: @MainActor (String) -> Void
    var record: @MainActor (HistoryRecord) -> Void
    var prepareVoice: @MainActor () -> VoicePreparation
}

/// Owns what the app is doing: one foreground state, one task per run, and the
/// policy that decides what a new request does to it. Feedback follows state.
@MainActor
final class ActionCoordinator {
    private struct Run {
        var task: Task<Void, Never>?
        var transcript: String?
        var audioFileName: String?
    }

    private let services: ActionServices
    private let feedback: ActionFeedback
    private let logger: Logger
    private(set) var state: ActionState = .idle
    private var runs: [Int: Run] = [:]
    private var lastRun = 0
    private var lastPhase: StatusPhase = .ready
    private var cancelled: [Task<Void, Never>] = []
    private var isShutDown = false

    init(services: ActionServices, feedback: ActionFeedback, logger: Logger = Logger(componentName: "ActionCoordinator")) {
        self.services = services
        self.feedback = feedback
        self.logger = logger
    }

    /// Runs finishing in the background keep the icon busy while the foreground is idle.
    var phase: StatusPhase {
        if state == .idle, !runs.isEmpty { return .processing }
        return state.phase
    }

    // MARK: - Requests

    func request(_ request: ActionRequest) {
        guard !isShutDown else { return }
        let decision = decide(request)
        switch decision {
        case .reject(let why):
            logger.log("\(request) ignored: \(why)", level: .info)
            feedback.ignored()
        case .cancel:
            preempt()
            sync()
        case .accept, .replace:
            // Checked before anything is stopped, so a refusal leaves the current action alone.
            if let refusal = refusal(for: request) {
                refusal()
                return
            }
            if decision == .replace { preempt() }
            begin(request)
            sync()
        }
    }

    func captureInterrupted() {
        guard state == .capturing else { return }
        state = .idle
        logger.log("Recording interrupted — device stopped unexpectedly", level: .error)
        conclude(nil, .failure("Microphone disconnected"))
    }

    func stopReadAloud() {
        guard state.priority == .tts else { return }
        preempt()
        sync()
    }

    private func speechEnded(_ completion: SpeechCompletion, run: Int) {
        guard state == .speaking(run: run) else { return }
        switch completion {
        case .finished: conclude(run, nil)
        case .failed(let message): conclude(run, .failure(message))
        }
    }

    /// Cancels every run. A transcript still being cleaned is kept in history as it was.
    func shutDown() {
        guard !isShutDown else { return }
        isShutDown = true
        if state == .capturing { _ = services.stopCapture() }
        for run in runs.values {
            if let text = run.transcript {
                services.record(.dictation(text: text, audioFileName: run.audioFileName, original: nil))
            }
            run.task?.cancel()
        }
        runs = [:]
        let wasSpeaking = state.priority == .tts
        state = .idle
        if wasSpeaking { services.stopSpeech() }
    }

    // MARK: - Policy

    private func decide(_ request: ActionRequest) -> ActionDecision {
        // A dictation still cleaning up in the background owns the cleanup model.
        if request == .instruct, runs.values.contains(where: { $0.transcript != nil }) {
            return .reject(.busy)
        }
        return ActionPolicy.decide(state, request)
    }

    private func refusal(for request: ActionRequest) -> (() -> Void)? {
        switch request {
        case .toggleRecord:
            guard state != .capturing, !services.providerReady() else { return nil }
            logger.log("Recording blocked — transcription model still loading", level: .warning)
            return { [feedback] in feedback.modelLoading() }
        case .instruct:
            if !services.accessibilityGranted() {
                return { [self] in conclude(nil, .failure("Cleanup needs Accessibility permission")) }
            }
            if !services.instructAvailable() {
                return { [self] in conclude(nil, .failure(CleanupOutcome.unavailable.selectionMessage)) }
            }
            return nil
        case .readAloud:
            guard !services.accessibilityGranted() else { return nil }
            return { [self] in conclude(nil, .failure("Read aloud needs Accessibility permission")) }
        }
    }

    /// Winds down the foreground action for a higher-priority request.
    private func preempt() {
        switch state {
        case .speaking:
            state = .idle
            services.stopSpeech()
        case .preparingVoice(let run):
            // Selection copying has already completed. Never queue another action behind a download.
            runs.removeValue(forKey: run)?.task?.cancel()
            state = .idle
        case .readingSelection(let run), .instructing(let run, .reading, _), .instructing(let run, .cleaning, _):
            cancel(run)
            state = .idle
        case .cleaning(let run, _):
            abortCleaning(run)
        default:
            break
        }
    }

    private func begin(_ request: ActionRequest) {
        switch request {
        case .toggleRecord: if state == .capturing { stopCapture() } else { startCapture() }
        case .instruct: startInstruct()
        case .readAloud: startReadAloud()
        }
    }

    // MARK: - Runs

    private func newRun(_ body: @escaping @MainActor (ActionCoordinator, Int) async -> Void) -> Int {
        lastRun += 1
        let id = lastRun
        runs[id] = Run()
        runs[id]?.task = Task { [weak self] in
            guard let self else { return }
            await body(self, id)
        }
        return id
    }

    private func isActive(_ run: Int) -> Bool { !isShutDown && runs[run] != nil }

    private func cancel(_ run: Int) {
        guard let task = runs.removeValue(forKey: run)?.task else { return }
        task.cancel()
        cancelled.append(task)
    }

    /// A cancelled selection read may still be mid-copy; the next read waits for it.
    private func drainCancelled() async {
        let pending = cancelled
        cancelled = []
        for task in pending { await task.value }
    }

    /// Sets the foreground state only if the run is still in front.
    private func setStage(_ run: Int, _ new: ActionState) {
        if state.run == run { state = new }
    }

    private func sync() {
        let current = phase
        guard current != lastPhase else { return }
        lastPhase = current
        feedback.render(current)
    }

    /// Ends a run and reports how it went. The result only flashes when the icon is free.
    private func conclude(_ run: Int?, _ outcome: ActionOutcome?) {
        if let run {
            runs[run] = nil
            if state.run == run { state = .idle }
        }
        guard let outcome else { return sync() }
        if phase == .ready {
            lastPhase = .ready
            feedback.report(outcome, flash: true)
        } else {
            sync()
            feedback.report(outcome, flash: false)
        }
    }

    private func concludeDelivery(_ run: Int, _ delivery: Delivery, failure: String) {
        switch delivery {
        case .pasted: conclude(run, .success)
        case .leftOnClipboard: conclude(run, .leftOnClipboard)
        case .failed: conclude(run, .failure(failure))
        }
    }

    /// Pastes only into the app the action started in; if focus moved, the text waits on the clipboard.
    private func deliver(_ text: String, target: pid_t?, done: @escaping @MainActor (Delivery) -> Void) {
        if let target, let front = services.frontmostPID(), front != target {
            logger.log("Frontmost app changed; leaving the text on the clipboard", level: .info)
            services.copyToClipboard(text)
            done(.leftOnClipboard)
            return
        }
        services.paste(text) { done($0 ? .pasted : .failed) }
    }

    // MARK: - Dictation

    private func startCapture() {
        do {
            try services.startCapture()
            state = .capturing
            feedback.recordingStarted()
            logger.log("Recording started")
        } catch {
            logger.logError(error, context: "Failed to start recording")
            conclude(nil, .failure("Failed to start recording"))
        }
    }

    private func stopCapture() {
        guard let url = services.stopCapture() else {
            state = .idle
            logger.log("Failed to get audio file", level: .error)
            conclude(nil, .failure("Failed to save audio file"))
            return
        }
        feedback.recordingStopped()
        let target = services.frontmostPID()
        let run = newRun { coordinator, run in await coordinator.transcribe(run, url, target) }
        state = .transcribing(run: run, target: target)
    }

    private func transcribe(_ run: Int, _ url: URL, _ target: pid_t?) async {
        let text: String
        do {
            text = try await services.transcribe(url)
        } catch {
            guard isActive(run) else { return }
            // No history entry will own this recording, so nothing else deletes it.
            services.discardAudio(url)
            logger.logError(error, context: "Transcription failed")
            conclude(run, .failure("Transcription failed: \(error.localizedDescription)"))
            return
        }
        guard isActive(run) else { return }
        logger.log("Transcription completed successfully", level: .info)
        let audio = url.lastPathComponent
        guard services.dictationCleanupEnabled() else {
            finishDictation(run, .original(text, .unchanged), audio: audio, original: nil, target: target)
            return
        }
        runs[run]?.transcript = text
        runs[run]?.audioFileName = audio
        setStage(run, .cleaning(run: run, target: target))
        sync()
        // Bounded by the dictation profile's deadline; anything but a clean result
        // delivers the transcript as it was.
        let result = await services.cleanDictation(text)
        guard isActive(run) else { return }
        logger.log("Dictation cleanup: \(result.outcome.rawValue)", level: .info)
        finishDictation(run, result, audio: audio, original: result.original, target: target)
    }

    /// Recording during cleanup delivers the transcript as it was, right away.
    private func abortCleaning(_ run: Int) {
        let aborted = runs[run]
        let target: pid_t? = { if case .cleaning(_, let target) = state { return target } else { return nil } }()
        cancel(run)
        state = .idle
        guard let text = aborted?.transcript else { return }
        finishDictation(run, .original(text, .failed), audio: aborted?.audioFileName, original: text, target: target)
    }

    private func finishDictation(_ run: Int, _ result: CleanupResult, audio: String?, original: String?, target: pid_t?) {
        services.record(.dictation(text: result.text, audioFileName: audio, original: original))
        // No sync: the paste settles within a run-loop turn, and the icon keeps its last phase.
        setStage(run, .inserting(run: run, target: target))
        deliver(result.text, target: target) { [weak self] delivery in
            self?.concludeDelivery(run, delivery, failure: "Failed to paste text at cursor")
        }
    }

    // MARK: - Instruct

    private func startInstruct() {
        let target = services.frontmostPID()
        let run = newRun { coordinator, run in await coordinator.runInstruct(run, target) }
        state = .instructing(run: run, stage: .reading, target: target)
    }

    private func runInstruct(_ run: Int, _ target: pid_t?) async {
        await drainCancelled()
        guard isActive(run) else { return }
        let selection = await services.readSelection()
        guard isActive(run) else { return }
        guard let selection else { return conclude(run, .failure("No text selected")) }
        setStage(run, .instructing(run: run, stage: .cleaning, target: target))
        sync()
        let result: CleanupResult
        do {
            result = try await services.cleanSelection(selection)
        } catch {
            guard isActive(run) else { return }
            return conclude(run, .failure("Cleanup failed"))
        }
        guard isActive(run) else { return }
        logger.log("Selection cleanup: \(result.outcome.rawValue)", level: .info)
        switch result.outcome {
        case .cleaned:
            services.record(.cleanup(text: result.text, original: result.original))
            setStage(run, .instructing(run: run, stage: .inserting, target: target))
            deliver(result.text, target: target) { [weak self] delivery in
                self?.concludeDelivery(run, delivery, failure: "Failed to paste the cleaned text")
            }
        case .unchanged:
            conclude(run, .success)
        default:
            conclude(run, .failure(result.outcome.selectionMessage))
        }
    }

    // MARK: - Read aloud

    private func startReadAloud() {
        let prepare = services.prepareVoice()
        let run = newRun { coordinator, run in await coordinator.runReadAloud(run, prepare: prepare) }
        state = .readingSelection(run: run)
    }

    private func runReadAloud(_ run: Int, prepare: ActionServices.VoicePreparation) async {
        await drainCancelled()
        guard isActive(run) else { return }
        let selection = await services.readSelection()
        guard isActive(run) else { return }
        guard let selection else { return conclude(run, .failure("No text selected")) }
        await prepare { [self] in
            guard isActive(run) else { return }
            state = .preparingVoice(run: run)
            sync()
        }
        guard isActive(run) else { return }
        runs[run] = nil
        services.record(.readAloud(text: selection))
        state = .speaking(run: run)
        sync()
        services.speak(selection) { [weak self] completion in
            self?.speechEnded(completion, run: run)
        }
    }
}
