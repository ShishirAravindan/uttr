import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MLXAudioRuntimeError: Error, LocalizedError, Equatable {
    case notInstalled
    case startupTimedOut
    case workerExited(Int32)
    case shutDown

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Expressive voices need the mlx-audio runtime. Install it in Settings → Read Aloud."
        case .startupTimedOut: return "The mlx-audio worker didn't start in time."
        case .workerExited(let status): return "The mlx-audio worker stopped (status \(status))."
        case .shutDown: return "Read-aloud stopped."
        }
    }
}

/// Every chunk would hit the same `MLXAudioRuntimeError`, so the pipeline stops at
/// once; a model error on one chunk (`MLXWorkerServerError`) only skips that chunk.
extension MLXAudioRuntimeError: FatalSpeechError {}

/// The worker answered with an error, usually the model failing on one chunk.
struct MLXWorkerServerError: Error, LocalizedError, Equatable {
    var status: Int
    var message: String

    var errorDescription: String? { "mlx-audio: \(message)" }
}

/// What the runtime is doing, for Settings and the popover.
enum MLXRuntimeState: Equatable {
    /// No worker running; the next read starts one.
    case stopped
    case starting
    /// Loading model weights into memory.
    case loading(String)
    /// A worker is running with this model loaded, warm for the next sentence.
    case ready(String)
    case failed(String)
}

// MARK: - Process and HTTP seams

/// A running worker process.
@MainActor
protocol MLXWorkerProcess: AnyObject {
    var isRunning: Bool { get }
    /// Asks the worker to exit, then kills it if it hasn't after a short grace period.
    func terminate()
}

/// Starts the worker. `onLine` gets each stdout line, `onExit` the exit status; both
/// run on the main actor.
@MainActor
protocol MLXWorkerLauncher {
    func launch(onLine: @escaping @MainActor (String) -> Void,
                onExit: @escaping @MainActor (Int32) -> Void) throws -> MLXWorkerProcess
}

/// Talks to a worker listening on `port`.
protocol MLXWorkerClient: Sendable {
    func loadModel(_ repo: String, port: Int) async throws
    func speak(_ request: MLXSpeechRequest, port: Int) async throws -> Data
    func cancel(requestID: String, port: Int) async
}

// MARK: - Runtime

/// Owns the mlx-audio worker's lifetime. The worker starts on the first read, stays
/// warm between sentences and reads, and exits after `idleTimeout` without requests
/// or when uttr quits, returning the model's unified memory to the system.
@MainActor
final class MLXAudioRuntime {
    typealias Sleeper = (Duration) async throws -> Void

    private let launcher: MLXWorkerLauncher
    private let client: MLXWorkerClient
    private let isInstalled: () -> Bool
    private let sleep: Sleeper
    private let startupTimeout: Duration
    private let logger: Logger

    private var process: MLXWorkerProcess?
    private var port: Int?
    private var portWaiters: [CheckedContinuation<Int, Error>] = []
    private var loadedModel: String?
    private var loading: (repo: String, task: Task<Void, Error>)?
    private var activeRequests = 0
    private var idleTask: Task<Void, Never>?
    /// Bumped whenever a worker starts or stops, so stale callbacks are ignored.
    private var workerGeneration = 0

    var idleTimeout: Duration
    private(set) var state: MLXRuntimeState = .stopped {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((MLXRuntimeState) -> Void)?

    var isRunning: Bool { process != nil }

    init(launcher: MLXWorkerLauncher,
         client: MLXWorkerClient,
         idleTimeout: Duration = .seconds(300),
         startupTimeout: Duration = .seconds(90),
         isInstalled: @escaping () -> Bool = { true },
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
         logger: Logger = Logger(componentName: "MLXAudio")) {
        self.launcher = launcher
        self.client = client
        self.idleTimeout = idleTimeout
        self.startupTimeout = startupTimeout
        self.isInstalled = isInstalled
        self.sleep = sleep
        self.logger = logger
    }

    /// Synthesizes one chunk, starting the worker and loading the model if needed.
    /// Cancelling the calling task cancels the request in the worker too.
    func synthesize(_ request: MLXSpeechRequest) async throws -> SpeechClip {
        activeRequests += 1
        idleTask?.cancel()
        idleTask = nil
        defer {
            activeRequests -= 1
            if activeRequests == 0 { scheduleIdleShutdown() }
        }

        let port = try await ensureModel(request.model)
        try Task.checkCancellation()
        var request = request
        let requestID = UUID().uuidString
        request.requestID = requestID
        let client = self.client
        let data = try await withTaskCancellationHandler {
            try await client.speak(request, port: port)
        } onCancel: {
            Task { await client.cancel(requestID: requestID, port: port) }
        }
        try Task.checkCancellation()
        return try WAVDecoder.decode(data)
    }

    /// Starts the worker and loads `repo` ahead of the first sentence.
    func warmUp(_ repo: String) async throws {
        activeRequests += 1
        idleTask?.cancel()
        defer {
            activeRequests -= 1
            if activeRequests == 0 { scheduleIdleShutdown() }
        }
        _ = try await ensureModel(repo)
    }

    /// Stops the worker now. Safe to call from `applicationWillTerminate`: the
    /// process is signalled synchronously.
    func shutdown() {
        idleTask?.cancel()
        idleTask = nil
        loading?.task.cancel()
        loading = nil
        stopWorker(reason: "shut down")
        state = .stopped
    }

    // MARK: - Private

    private func ensureModel(_ repo: String) async throws -> Int {
        let port = try await ensureWorker()
        if loadedModel == repo { return port }

        if let loading, loading.repo == repo {
            try await loading.task.value
        } else {
            loading?.task.cancel()
            state = .loading(repo)
            let client = self.client
            let generation = workerGeneration
            let task = Task { try await client.loadModel(repo, port: port) }
            loading = (repo, task)
            do {
                try await task.value
            } catch {
                if self.loading?.repo == repo { self.loading = nil }
                if generation == workerGeneration, !(error is CancellationError) {
                    state = .failed(error.localizedDescription)
                }
                throw error
            }
            guard generation == workerGeneration else { throw MLXAudioRuntimeError.shutDown }
            if self.loading?.repo == repo { self.loading = nil }
            loadedModel = repo
            logger.log("Loaded \(repo)", level: .info)
        }
        state = .ready(repo)
        return port
    }

    private func ensureWorker() async throws -> Int {
        if let port, process != nil { return port }
        if process == nil {
            guard isInstalled() else {
                state = .failed(MLXAudioRuntimeError.notInstalled.localizedDescription)
                throw MLXAudioRuntimeError.notInstalled
            }
            try startWorker()
        }
        return try await withCheckedThrowingContinuation { portWaiters.append($0) }
    }

    private func startWorker() throws {
        workerGeneration += 1
        let generation = workerGeneration
        state = .starting
        logger.log("Starting mlx-audio worker", level: .info)
        do {
            process = try launcher.launch(
                onLine: { [weak self] line in self?.handleLine(line, generation: generation) },
                onExit: { [weak self] status in self?.workerExited(status: status, generation: generation) }
            )
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
        let timeout = startupTimeout
        let sleep = self.sleep
        Task { [weak self] in
            try? await sleep(timeout)
            guard let self, generation == self.workerGeneration, self.port == nil, self.process != nil else { return }
            self.logger.log("mlx-audio worker didn't start in time", level: .error)
            self.stopWorker(reason: "startup timed out", error: .startupTimedOut)
            self.state = .failed(MLXAudioRuntimeError.startupTimedOut.localizedDescription)
        }
    }

    private func handleLine(_ line: String, generation: Int) {
        guard generation == workerGeneration,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["event"] as? String == "listening",
              let port = object["port"] as? Int else { return }
        logger.log("mlx-audio worker listening on port \(port)", level: .info)
        self.port = port
        let waiters = portWaiters
        portWaiters = []
        waiters.forEach { $0.resume(returning: port) }
    }

    private func workerExited(status: Int32, generation: Int) {
        guard generation == workerGeneration else { return }
        logger.log("mlx-audio worker exited with status \(status)", level: .warning)
        process = nil
        resetWorkerState(error: .workerExited(status))
        state = .failed(MLXAudioRuntimeError.workerExited(status).localizedDescription)
    }

    private func stopWorker(reason: String, error: MLXAudioRuntimeError = .shutDown) {
        guard process != nil || !portWaiters.isEmpty else { return }
        logger.log("Stopping mlx-audio worker: \(reason)", level: .info)
        workerGeneration += 1
        process?.terminate()
        process = nil
        resetWorkerState(error: error)
    }

    private func resetWorkerState(error: MLXAudioRuntimeError) {
        port = nil
        loadedModel = nil
        loading?.task.cancel()
        loading = nil
        let waiters = portWaiters
        portWaiters = []
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        guard process != nil else { return }
        let timeout = idleTimeout
        let sleep = self.sleep
        let generation = workerGeneration
        idleTask = Task { [weak self] in
            do { try await sleep(timeout) } catch { return }
            guard let self, !Task.isCancelled, generation == self.workerGeneration,
                  self.activeRequests == 0 else { return }
            self.stopWorker(reason: "idle")
            self.state = .stopped
        }
    }
}

// MARK: - Real process and HTTP

/// Runs `mlx_audio_worker.py serve` with the managed environment's Python.
struct MLXWorkerProcessLauncher: MLXWorkerLauncher {
    let python: URL
    let script: URL
    let workingDirectory: URL
    let logFile: URL

    func launch(onLine: @escaping @MainActor (String) -> Void,
                onExit: @escaping @MainActor (Int32) -> Void) throws -> MLXWorkerProcess {
        let process = Process()
        process.executableURL = python
        process.arguments = ["-u", script.path, "serve", "--port", "0",
                             "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        process.currentDirectoryURL = workingDirectory
        process.environment = MLXAudioEnvironment.workerEnvironment()

        let output = Pipe()
        process.standardOutput = output
        try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFile.path) {
            _ = FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logFile) {
            log.seekToEndOfFile()
            process.standardError = log
        }

        let lines = LineSplitter { line in Task { @MainActor in onLine(line) } }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                lines.append(data)
            }
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in onExit(status) }
        }
        try process.run()
        return RunningWorker(process: process)
    }
}

@MainActor
private final class RunningWorker: MLXWorkerProcess {
    private let process: Process

    init(process: Process) { self.process = process }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        let process = self.process
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

/// Splits a byte stream into UTF-8 lines. Called from the pipe's reading thread.
final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            lines.append(String(decoding: line, as: UTF8.self))
        }
        lock.unlock()
        lines.forEach(onLine)
    }
}

struct MLXWorkerHTTPClient: MLXWorkerClient {
    func loadModel(_ repo: String, port: Int) async throws {
        // A first load can fetch codec weights, so it gets a long timeout.
        _ = try await post("/v1/models", body: ["model": repo], port: port, timeout: 900)
    }

    func speak(_ request: MLXSpeechRequest, port: Int) async throws -> Data {
        try await post("/v1/audio/speech", body: request, port: port, timeout: 180)
    }

    func cancel(requestID: String, port: Int) async {
        _ = try? await post("/v1/cancel", body: ["request_id": requestID], port: port, timeout: 5)
    }

    private func post<Body: Encodable>(_ path: String, body: Body, port: Int, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 499 { throw CancellationError() }
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw MLXWorkerServerError(status: status, message: message ?? "HTTP \(status)")
        }
        return data
    }
}
