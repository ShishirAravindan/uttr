import Combine
import Foundation

protocol SessionRecording: AnyObject {
    var preferredInputDeviceUID: String? { get set }
    var onInterrupted: (() -> Void)? { get set }
    func startRecording() throws
    func stopRecording() -> URL?
}

protocol SessionPasting: AnyObject {
    func pasteText(_ text: String, completion: @escaping (Bool) -> Void)
}

enum SessionState: Equatable {
    case loading
    case idle
    case capturing(startedAt: Date)
    case transcribing(audioURL: URL)
    case inserting(text: String)
    case unavailable(message: String)
    case stopped

    var isRecording: Bool {
        if case .capturing = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .capturing, .transcribing, .inserting: return true
        default: return false
        }
    }
}

enum SessionEvent {
    case providerReady(name: String)
    case providerFailed(message: String)
    case notReady
    case recordingStarted
    case recordingStopped
    case recordingFailed(message: String)
    case recordingInterrupted
    case transcribed(text: String, audioFileName: String)
    case transcriptionFailed(message: String)
    case inserted
    case insertionFailed
}

/// Owns one utterance from capture to insertion. Platform effects are supplied by
/// the app boundary so lifecycle transitions can be exercised without a microphone.
@MainActor
final class TranscriptionSession: ObservableObject {
    @Published private(set) var state: SessionState = .loading
    var onEvent: ((SessionEvent) -> Void)?

    private let recorder: SessionRecording
    private let pasteManager: SessionPasting
    private var provider: TranscriptionProvider
    private var pendingProvider: TranscriptionProvider?
    private var operationTask: Task<Void, Never>?
    private var revision = 0

    init(recorder: SessionRecording, provider: TranscriptionProvider, pasteManager: SessionPasting) {
        self.recorder = recorder
        self.provider = provider
        self.pasteManager = pasteManager
    }

    func providerStatus(for state: SessionState) -> String {
        if pendingProvider != nil { return "Switching after this transcription…" }
        switch state {
        case .loading: return "Loading…"
        case .unavailable(let message): return "Failed — \(message)"
        case .stopped: return "Stopped"
        default: return "Loaded · ~600 MB"
        }
    }

    func prepare() {
        guard state == .loading, operationTask == nil else { return }
        prepareProvider(provider)
    }

    func changeProvider(_ newProvider: TranscriptionProvider) {
        guard state != .stopped else { return }
        if state.isBusy {
            // Preserve this utterance and apply only the latest requested provider.
            pendingProvider = newProvider
        } else {
            prepareProvider(newProvider)
        }
    }

    func setInputDevice(uid: String?) {
        recorder.preferredInputDeviceUID = uid
    }

    func toggleRecording() {
        if state.isRecording { stopRecording() } else { startRecording() }
    }

    func startRecording() {
        guard state == .idle else {
            if case .loading = state { onEvent?(.notReady) }
            if case .unavailable = state { onEvent?(.notReady) }
            return
        }

        revision += 1
        let captureRevision = revision
        recorder.onInterrupted = { [weak self] in
            Task { @MainActor [weak self] in
                self?.recordingInterrupted(revision: captureRevision)
            }
        }

        do {
            try recorder.startRecording()
            state = .capturing(startedAt: Date())
            onEvent?(.recordingStarted)
        } catch {
            recorder.onInterrupted = nil
            // A start failure can leave a partially configured engine behind.
            _ = recorder.stopRecording()
            onEvent?(.recordingFailed(message: "Failed to start recording: \(error.localizedDescription)"))
        }
    }

    func stopRecording() {
        guard state.isRecording else { return }
        recorder.onInterrupted = nil
        guard let url = recorder.stopRecording() else {
            finish(.recordingFailed(message: "Failed to save audio file"))
            return
        }

        state = .transcribing(audioURL: url)
        onEvent?(.recordingStopped)
        let transcriptionRevision = revision
        let provider = self.provider
        operationTask = Task { [weak self] in
            do {
                let text = try await provider.transcribe(audioFileURL: url)
                guard let self, self.isCurrent(transcriptionRevision) else { return }
                self.state = .inserting(text: text)
                self.onEvent?(.transcribed(text: text, audioFileName: url.lastPathComponent))
                guard self.isCurrent(transcriptionRevision) else { return }
                self.pasteManager.pasteText(text) { [weak self] success in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCurrent(transcriptionRevision),
                              case .inserting = self.state else { return }
                        self.finish(success ? .inserted : .insertionFailed)
                    }
                }
            } catch {
                guard let self, self.isCurrent(transcriptionRevision) else { return }
                self.finish(.transcriptionFailed(message: error.localizedDescription))
            }
        }
    }

    /// Invalidate results immediately, then wait for provider use to finish before
    /// teardown. Cancellation alone cannot stop an uncooperative inference call.
    @discardableResult
    func shutDown() -> Task<Void, Never> {
        if state == .stopped, let operationTask { return operationTask }
        if state.isRecording { _ = recorder.stopRecording() }
        recorder.onInterrupted = nil
        pendingProvider = nil
        revision += 1
        state = .stopped

        let previousTask = operationTask
        previousTask?.cancel()
        let provider = self.provider
        let task = Task {
            await previousTask?.value
            await provider.teardown()
        }
        operationTask = task
        return task
    }

    // MARK: - Lifecycle transitions

    private func prepareProvider(_ newProvider: TranscriptionProvider) {
        let previousTask = operationTask
        previousTask?.cancel()
        let previousProvider = provider
        provider = newProvider
        pendingProvider = nil
        revision += 1
        let preparationRevision = revision
        state = .loading

        operationTask = Task { [weak self] in
            await previousTask?.value
            if previousProvider !== newProvider {
                await previousProvider.teardown()
            }
            guard self?.isCurrent(preparationRevision) == true else { return }
            do {
                try await newProvider.prepare()
                guard let self, self.isCurrent(preparationRevision) else { return }
                self.state = .idle
                self.onEvent?(.providerReady(name: newProvider.displayName))
            } catch {
                guard let self, self.isCurrent(preparationRevision) else { return }
                self.state = .unavailable(message: error.localizedDescription)
                self.onEvent?(.providerFailed(message: error.localizedDescription))
            }
        }
    }

    private func recordingInterrupted(revision: Int) {
        guard isCurrent(revision), state.isRecording else { return }
        recorder.onInterrupted = nil
        // AudioRecorder has already discarded the interrupted capture.
        finish(.recordingInterrupted)
    }

    private func finish(_ event: SessionEvent) {
        state = .idle
        onEvent?(event)
        if state == .idle, let pendingProvider {
            prepareProvider(pendingProvider)
        }
    }

    private func isCurrent(_ revision: Int) -> Bool {
        self.revision == revision && state != .stopped && !Task.isCancelled
    }
}
