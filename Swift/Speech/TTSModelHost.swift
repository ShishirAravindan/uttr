import Foundation

/// A loaded speech model. Calls must not overlap; `TTSModelHost` serializes them.
protocol LoadedSpeechModel: AnyObject {
    var sampleRate: Int { get }
    /// Mono samples for one chunk. Cancelling the calling task stops generation.
    func synthesize(_ request: TTSRequest) async throws -> [Float]
}

/// Loads models by repository, downloading anything missing.
@MainActor
protocol SpeechModelLoader {
    func load(repo: String) async throws -> LoadedSpeechModel
    /// Called after the host drops a model, to return cached GPU buffers.
    func didUnload()
}

/// A model that couldn't load. Every chunk would fail the same way, so the
/// pipeline stops at once.
struct TTSModelLoadError: FatalSpeechError, LocalizedError, Equatable {
    var repo: String
    var message: String

    var errorDescription: String? { "Couldn't load the voice: \(message)" }
}

/// What the host is doing, for Settings and the popover.
enum TTSModelHostState: Equatable {
    /// No model in memory; the next read loads one.
    case unloaded
    /// Loading weights into memory, downloading anything missing first.
    case loading(String)
    /// The model is in memory, warm for the next sentence.
    case ready(String)
    case failed(String)
}

/// Owns the in-process speech model. It loads on the first sentence, runs one
/// generation at a time, stays warm between sentences and reads, and drops the
/// model after `idleTimeout` without requests (or on `unload()`), returning its
/// unified memory.
@MainActor
final class TTSModelHost {
    typealias Sleeper = (Duration) async throws -> Void

    private let loader: SpeechModelLoader
    private let sleep: Sleeper
    private let logger: Logger

    private var model: LoadedSpeechModel?
    private var loadedRepo: String?
    private var isBusy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var idleTask: Task<Void, Never>?
    /// Bumped by `unload()`, so a load that finishes afterward is discarded.
    private var generation = 0

    var idleTimeout: Duration
    private(set) var state: TTSModelHostState = .unloaded {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((TTSModelHostState) -> Void)?

    var isLoaded: Bool { model != nil }

    init(loader: SpeechModelLoader,
         idleTimeout: Duration = .seconds(300),
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
         logger: Logger = Logger(componentName: "TTSModelHost")) {
        self.loader = loader
        self.idleTimeout = idleTimeout
        self.sleep = sleep
        self.logger = logger
    }

    /// Synthesizes one chunk, loading the model first if needed.
    func synthesize(_ request: TTSRequest) async throws -> SpeechClip {
        try await exclusively {
            let model = try await self.ensureModel(request.repo)
            try Task.checkCancellation()
            let samples = try await model.synthesize(request)
            try Task.checkCancellation()
            return SpeechClip(samples: samples, sampleRate: Double(model.sampleRate))
        }
    }

    /// Loads `repo` ahead of the first sentence.
    func warmUp(_ repo: String) async throws {
        try await exclusively { _ = try await self.ensureModel(repo) }
    }

    /// Drops the model now. A generation already running finishes with its own
    /// reference; nothing new starts on the dropped model.
    func unload() {
        idleTask?.cancel()
        idleTask = nil
        generation += 1
        guard model != nil || loadedRepo != nil else {
            if case .loading = state { state = .unloaded }
            return
        }
        logger.log("Unloading \(loadedRepo ?? "model")", level: .info)
        model = nil
        loadedRepo = nil
        loader.didUnload()
        state = .unloaded
    }

    // MARK: - Private

    private func ensureModel(_ repo: String) async throws -> LoadedSpeechModel {
        if let model, loadedRepo == repo { return model }
        if model != nil { unload() }
        let generation = self.generation
        state = .loading(repo)
        let started = Date()
        let loaded: LoadedSpeechModel
        do {
            loaded = try await loader.load(repo: repo)
        } catch {
            if error is CancellationError {
                if generation == self.generation { state = .unloaded }
                throw error
            }
            if generation == self.generation { state = .failed(error.localizedDescription) }
            throw TTSModelLoadError(repo: repo, message: error.localizedDescription)
        }
        guard generation == self.generation else {
            loader.didUnload()
            throw CancellationError()
        }
        model = loaded
        loadedRepo = repo
        state = .ready(repo)
        logger.log("Loaded \(repo) in \(Int(Date().timeIntervalSince(started) * 1000)) ms", level: .info)
        return loaded
    }

    /// Runs `work` while no other work runs. Waiting is cancellable.
    private func exclusively<T>(_ work: @escaping () async throws -> T) async throws -> T {
        idleTask?.cancel()
        idleTask = nil
        try await acquire()
        defer {
            release()
            if !isBusy { scheduleIdleUnload() }
        }
        return try await work()
    }

    private func acquire() async throws {
        if !isBusy {
            isBusy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append((id, $0)) }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            // The lock passes straight to the next waiter.
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        guard model != nil else { return }
        let timeout = idleTimeout
        let sleep = self.sleep
        let generation = self.generation
        idleTask = Task { [weak self] in
            do { try await sleep(timeout) } catch { return }
            guard let self, !Task.isCancelled, generation == self.generation, !self.isBusy else { return }
            self.logger.log("Idle for \(timeout); unloading", level: .info)
            self.unload()
        }
    }
}

// MARK: - Model files

/// Where mlx-audio-swift keeps downloaded models: `<Hugging Face cache>/mlx-audio/<org>_<name>`.
enum TTSModelFiles {
    /// Follows `HF_HUB_CACHE` and `HF_HOME` like swift-huggingface does, when uttr
    /// was given them; otherwise `~/.cache/huggingface/hub`.
    static func hubCache(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let cache = environment["HF_HUB_CACHE"], !cache.isEmpty {
            return URL(fileURLWithPath: (cache as NSString).expandingTildeInPath)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath).appendingPathComponent("hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
    }

    static func modelsRoot(hubCache: URL = hubCache()) -> URL {
        hubCache.appendingPathComponent("mlx-audio")
    }

    static func folder(repo: String, root: URL = modelsRoot()) -> URL {
        root.appendingPathComponent(repo.replacingOccurrences(of: "/", with: "_"))
    }

    /// Downloaded when the folder has a valid config.json and non-empty weights,
    /// as mlx-audio-swift itself checks. Deleting the folder makes it not downloaded.
    static func isDownloaded(repo: String, root: URL = modelsRoot()) -> Bool {
        let folder = folder(repo: repo, root: root)
        guard let config = try? Data(contentsOf: folder.appendingPathComponent("config.json")),
              (try? JSONSerialization.jsonObject(with: config)) != nil,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        else { return false }
        return files.contains { file in
            file.pathExtension == "safetensors"
                && ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
        }
    }

    /// Bytes on disk under `url`.
    static func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
