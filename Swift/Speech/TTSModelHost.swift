import Foundation

@MainActor
protocol LoadedSpeechModel: AnyObject {
    func synthesize(_ text: String, voice: String?) async throws -> SpeechClip
}

@MainActor
protocol SpeechModelLoader {
    func load(_ preset: ExpressiveSpeechModel) async throws -> LoadedSpeechModel
    func clearCache()
}

/// Holds one model and serializes model loading, generation and release across
/// suspension points. Playback only calls synthesis after preparation succeeds.
@MainActor
final class TTSModelHost {
    enum State: Equatable {
        case unloaded
        case loading(ExpressiveSpeechModel)
        case ready(ExpressiveSpeechModel)
        case failed(ExpressiveSpeechModel, String)
    }

    private enum ModelError: LocalizedError {
        case notPrepared(ExpressiveSpeechModel)
        case preparationFailed(ExpressiveSpeechModel, String)

        var errorDescription: String? {
            switch self {
            case .notPrepared(let preset):
                return "\(preset.name) is not ready"
            case .preparationFailed(let preset, let message):
                return "Couldn’t prepare \(preset.name): \(message)"
            }
        }
    }

    private let loader: SpeechModelLoader
    private let idleTimeout: Duration
    private var loaded: (preset: ExpressiveSpeechModel, model: LoadedSpeechModel)?
    private var busy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var idleTask: Task<Void, Never>?

    private(set) var state = State.unloaded {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }
    var onStateChange: ((State) -> Void)?

    init(loader: SpeechModelLoader, idleTimeout: Duration = .seconds(300)) {
        self.loader = loader
        self.idleTimeout = idleTimeout
    }

    /// Prepares the preset and can fetch missing artifacts. User-initiated
    /// download approval and missing-file handling belong to the caller.
    func prepare(_ preset: ExpressiveSpeechModel) async throws {
        try await exclusively {
            if loaded?.preset == preset { return }
            releaseLoadedModel()
            state = .loading(preset)
            do {
                let model = try await loader.load(preset)
                try Task.checkCancellation()
                loaded = (preset, model)
                state = .ready(preset)
            } catch {
                if Task.isCancelled {
                    loader.clearCache()
                    state = .unloaded
                    throw CancellationError()
                }
                let failure = ModelError.preparationFailed(preset, error.localizedDescription)
                loader.clearCache()
                state = .failed(preset, failure.localizedDescription)
                throw failure
            }
        }
    }

    func synthesize(_ text: String, with preset: ExpressiveSpeechModel) async throws -> SpeechClip {
        try await exclusively {
            guard let loaded, loaded.preset == preset else { throw ModelError.notPrepared(preset) }
            let clip = try await loaded.model.synthesize(text, voice: preset.defaultVoice)
            try Task.checkCancellation()
            return clip
        }
    }

    /// Waits for the active operation to release the model before unloading.
    func unload(_ preset: ExpressiveSpeechModel? = nil, whileAllowed: () -> Bool = { true }) async throws {
        try await exclusively {
            guard whileAllowed() else { throw CancellationError() }
            if let preset, loaded?.preset != preset { return }
            releaseLoadedModel()
            state = .unloaded
        }
    }

    private func exclusively<T>(_ operation: () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        idleTask?.cancel()
        idleTask = nil
        if !busy {
            busy = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append((id, $0)) }
        } onCancel: {
            Task { @MainActor in
                guard let index = self.waiters.firstIndex(where: { $0.id == id }) else { return }
                self.waiters.remove(at: index).continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().continuation.resume()
            return
        }

        busy = false
        guard loaded != nil else { return }
        let timeout = idleTimeout
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                try Task.checkCancellation()
            } catch {
                return
            }
            guard let self, !self.busy else { return }
            self.idleTask = nil
            self.releaseLoadedModel()
            self.state = .unloaded
        }
    }

    private func releaseLoadedModel() {
        guard loaded != nil else { return }
        loaded = nil
        loader.clearCache()
    }
}
