import Foundation

/// Where uttr keeps its mlx-audio environment and where Hugging Face keeps models.
struct MLXAudioEnvironment {
    /// `~/Library/Application Support/uttr/mlx-audio`
    let root: URL
    /// An existing Python with mlx-audio installed, used instead of the managed one.
    let customPython: URL?
    let script: URL?

    init(root: URL = MLXAudioEnvironment.defaultRoot,
         customPython: URL? = nil,
         script: URL? = Bundle.main.url(forResource: "mlx_audio_worker", withExtension: "py")) {
        self.root = root
        self.customPython = customPython
        self.script = script
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("uttr").appendingPathComponent("mlx-audio")
    }

    var venv: URL { root.appendingPathComponent("venv") }
    var python: URL { customPython ?? venv.appendingPathComponent("bin").appendingPathComponent("python") }
    var logFile: URL { root.appendingPathComponent("worker.log") }

    /// A cheap check that doesn't start Python: the interpreter and worker script exist.
    var isInstalled: Bool {
        script != nil && FileManager.default.isExecutableFile(atPath: python.path)
    }

    func launcher() -> MLXWorkerProcessLauncher? {
        guard let script else { return nil }
        return MLXWorkerProcessLauncher(python: python, script: script, workingDirectory: root, logFile: logFile)
    }

    // MARK: Hugging Face cache

    /// Follows `HF_HUB_CACHE` and `HF_HOME` like huggingface_hub does, when uttr
    /// was given them; otherwise `~/.cache/huggingface/hub`.
    static func hubCache(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let cache = environment["HF_HUB_CACHE"], !cache.isEmpty {
            return URL(fileURLWithPath: (cache as NSString).expandingTildeInPath)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath).appendingPathComponent("hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    static func modelFolder(repo: String, hubCache: URL = hubCache()) -> URL {
        hubCache.appendingPathComponent("models--" + repo.replacingOccurrences(of: "/", with: "--"))
    }

    /// A model is downloaded when a snapshot has files and no blob is still partial.
    /// Deleting its folder in Finder makes it not downloaded again.
    static func isModelDownloaded(repo: String, hubCache: URL = hubCache()) -> Bool {
        let folder = modelFolder(repo: repo, hubCache: hubCache)
        let fileManager = FileManager.default
        let snapshots = folder.appendingPathComponent("snapshots")
        guard let revisions = try? fileManager.contentsOfDirectory(atPath: snapshots.path),
              revisions.contains(where: { revision in
                  let files = (try? fileManager.contentsOfDirectory(atPath: snapshots.appendingPathComponent(revision).path)) ?? []
                  return !files.isEmpty
              }) else { return false }
        let blobs = (try? fileManager.contentsOfDirectory(atPath: folder.appendingPathComponent("blobs").path)) ?? []
        return !blobs.contains { $0.hasSuffix(".incomplete") }
    }

    /// The environment for every Python uttr starts. GUI apps don't get the login
    /// shell's PATH, so the usual tool locations are added.
    static func workerEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        environment["PATH"] = (path + extra.filter { !path.contains($0) }).joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        return environment
    }
}

enum MLXAudioInstallerError: Error, LocalizedError {
    case noPython
    case missingWorkerScript
    case commandFailed(String, Int32)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPython:
            return "Install uv (brew install uv) or Python 3.11 or later, then try again."
        case .missingWorkerScript:
            return "uttr's mlx-audio worker script is missing from the app."
        case .commandFailed(let command, let status):
            return "\(command) failed (status \(status)). See the worker log."
        case .downloadFailed(let message):
            return message
        }
    }
}

/// Download state reported while a model installs.
struct MLXDownloadProgress: Equatable {
    enum Phase: Equatable { case downloading, verifying }
    var phase: Phase
    var bytes: Int64
    var total: Int64

    var fraction: Double? {
        guard phase == .downloading, total > 0 else { return nil }
        return min(1, Double(bytes) / Double(total))
    }
}

/// Sets up the managed mlx-audio environment and downloads models into the
/// Hugging Face cache. Both run as child processes and stop when their task is
/// cancelled.
@MainActor
struct MLXAudioInstaller {
    let environment: MLXAudioEnvironment
    /// The mlx-audio requirement installed into the managed environment.
    static let requirement = "mlx-audio>=0.6"

    /// Creates `venv` with uv, which also fetches a suitable Python, or with a
    /// Python 3.11+ already on the Mac; then installs mlx-audio and checks it imports.
    func installRuntime(status: @escaping @MainActor (String) -> Void) async throws {
        guard environment.script != nil else { throw MLXAudioInstallerError.missingWorkerScript }
        try FileManager.default.createDirectory(at: environment.root, withIntermediateDirectories: true)
        let venv = environment.venv.path
        let python = environment.venv.appendingPathComponent("bin/python").path

        if let uv = Self.findUV() {
            status("Creating Python environment…")
            try await run(uv, ["venv", "--python", "3.12", "--allow-existing", venv], label: "uv venv")
            status("Installing mlx-audio…")
            try await run(uv, ["pip", "install", "--python", python, "--upgrade", Self.requirement], label: "uv pip install")
        } else if let system = await Self.findPython() {
            status("Creating Python environment…")
            try await run(system, ["-m", "venv", venv], label: "python -m venv")
            status("Installing mlx-audio…")
            try await run(python, ["-m", "pip", "install", "--upgrade", "pip", Self.requirement], label: "pip install")
        } else {
            throw MLXAudioInstallerError.noPython
        }
        status("Checking mlx-audio…")
        try await check()
    }

    /// Confirms the environment's Python can import mlx-audio.
    func check() async throws {
        guard let script = environment.script else { throw MLXAudioInstallerError.missingWorkerScript }
        try await run(environment.python.path, ["-u", script.path, "check"], label: "mlx-audio check")
    }

    /// Downloads `repo`, reporting progress, then loads it once so dependent files
    /// (codecs, tokenizers) are fetched before the first read.
    func downloadModel(_ repo: String, progress: @escaping @MainActor (MLXDownloadProgress) -> Void) async throws {
        guard let script = environment.script else { throw MLXAudioInstallerError.missingWorkerScript }
        var failure: String?
        var total: Int64 = 0
        do {
            try await run(environment.python.path, ["-u", script.path, "download", repo], label: "download") { line in
                guard let data = line.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                switch event["event"] as? String {
                case "total":
                    total = (event["bytes"] as? NSNumber)?.int64Value ?? 0
                    progress(MLXDownloadProgress(phase: .downloading, bytes: 0, total: total))
                case "progress":
                    let bytes = (event["bytes"] as? NSNumber)?.int64Value ?? 0
                    progress(MLXDownloadProgress(phase: .downloading, bytes: bytes, total: total))
                case "phase":
                    progress(MLXDownloadProgress(phase: .verifying, bytes: total, total: total))
                case "error":
                    failure = event["message"] as? String
                default:
                    break
                }
            }
        } catch let error as MLXAudioInstallerError {
            if let failure { throw MLXAudioInstallerError.downloadFailed(failure) }
            throw error
        }
    }

    // MARK: - Discovery

    nonisolated static func findUV(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let candidates = [
            home.appendingPathComponent(".local/bin/uv").path,
            home.appendingPathComponent(".cargo/bin/uv").path,
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The first Python 3.11+ among the usual install locations. Apple's
    /// /usr/bin/python3 is 3.9, too old for mlx-audio, and is only used if newer.
    static func findPython() async -> String? {
        var candidates: [String] = []
        for version in ["3.13", "3.12", "3.11"] {
            candidates += ["/opt/homebrew/bin/python\(version)", "/usr/local/bin/python\(version)",
                           "/Library/Frameworks/Python.framework/Versions/\(version)/bin/python3"]
        }
        candidates += ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            let ok = try? await runProcess(candidate, ["-c", "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)"],
                                           environment: MLXAudioEnvironment.workerEnvironment(), onLine: { _ in })
            if ok == 0 { return candidate }
        }
        return nil
    }

    // MARK: - Processes

    private func run(_ executable: String, _ arguments: [String], label: String,
                     onLine: @escaping @MainActor (String) -> Void = { _ in }) async throws {
        let status = try await Self.runProcess(executable, arguments, environment: MLXAudioEnvironment.workerEnvironment(),
                                               logFile: environment.logFile, onLine: onLine)
        guard status == 0 else { throw MLXAudioInstallerError.commandFailed(label, status) }
    }

    /// Runs a process to completion, passing stdout lines to `onLine` and appending
    /// stderr to `logFile`. Cancelling the task terminates the process.
    nonisolated static func runProcess(_ executable: String, _ arguments: [String], environment: [String: String],
                           logFile: URL? = nil, onLine: @escaping @MainActor (String) -> Void) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        if let logFile {
            try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logFile.path) {
                _ = FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            if let log = try? FileHandle(forWritingTo: logFile) {
                log.seekToEndOfFile()
                process.standardError = log
            }
        } else {
            process.standardError = FileHandle.nullDevice
        }
        let lines = LineSplitter { line in Task { @MainActor in onLine(line) } }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { lines.append(data) }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { finished in
                    // Let the last stdout lines reach the main actor before returning.
                    Task { @MainActor in continuation.resume(returning: finished.terminationStatus) }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
