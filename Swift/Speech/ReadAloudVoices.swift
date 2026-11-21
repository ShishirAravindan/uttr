import AppKit
import Combine

/// Owns the read-aloud voices and the mlx-audio runtime: picks the engine for the
/// selected voice, installs the runtime and models, and reports their state to
/// Settings and the popover.
///
/// The system voice is always available. Kokoro loads on the first read, as
/// before. An mlx-audio voice is used once its model is downloaded; its worker
/// starts on the first sentence and stops when idle or when uttr quits. Until a
/// selected voice is ready, the previous voice keeps reading.
@MainActor
final class ReadAloudVoices: ObservableObject {
    enum RuntimeStatus: Equatable {
        case notInstalled
        case installing(String)
        case installed
        case failed(String)
    }

    enum ModelStatus: Equatable {
        case notDownloaded
        case downloading(MLXDownloadProgress?)
        case downloaded
        case failed(String)
    }

    @Published private(set) var runtimeStatus: RuntimeStatus
    @Published private(set) var modelStatus: [String: ModelStatus] = [:]
    @Published private(set) var workerState: MLXRuntimeState = .stopped
    /// The voice actually reading, which lags the selection until it is ready.
    @Published private(set) var activeVoice: ReadAloudVoice = .system
    /// Why the selected voice isn't the active one, when there's a reason to show.
    @Published private(set) var notice: String?

    let player = SpeechAudioPlayer()
    private let settings: SettingsManager
    private let environment: MLXAudioEnvironment
    private let runtime: MLXAudioRuntime
    private weak var readAloud: ReadAloud?
    private var kokoro: KokoroSpeechEngine?
    private var kokoroPreparation: Task<Void, Never>?
    private var runtimeInstall: Task<Bool, Never>?
    private var downloads: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(componentName: "ReadAloudVoices")

    init(settings: SettingsManager) {
        self.settings = settings
        let environment = MLXAudioEnvironment(customPython: settings.readAloud.pythonPath.map { URL(fileURLWithPath: $0) })
        self.environment = environment
        let launcher: MLXWorkerLauncher
        if let workerLauncher = environment.launcher() {
            launcher = workerLauncher
        } else {
            launcher = MissingWorkerLauncher()
        }
        runtime = MLXAudioRuntime(
            launcher: launcher,
            client: MLXWorkerHTTPClient(),
            idleTimeout: .seconds(settings.readAloud.idleUnloadMinutes * 60),
            isInstalled: { environment.isInstalled }
        )
        runtimeStatus = environment.isInstalled ? .installed : .notInstalled
        player.rate = Float(settings.readAloud.speed)
        runtime.onStateChange = { [weak self] state in self?.workerState = state }
        refresh()

        observers.append(NotificationCenter.default.addObserver(
            forName: .readAloudVoiceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectionChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .readAloudPlaybackChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.playbackSettingsChanged() }
        })
    }

    /// Wires the voices to read-aloud and applies the saved selection.
    func attach(to readAloud: ReadAloud) {
        self.readAloud = readAloud
        player.onInterrupted = { [weak readAloud] in readAloud?.stop() }
        applySelection(preparingKokoro: false)
    }

    var selectedVoice: ReadAloudVoice { settings.readAloudVoice }

    /// Called on each read-aloud request: loads Kokoro on first use and makes sure
    /// the selected voice reads if it's ready.
    func prepareForRead() {
        applySelection(preparingKokoro: true)
    }

    // MARK: - Installing

    var isRuntimeInstalled: Bool { runtimeStatus == .installed }

    func status(of model: MLXSpeechModel) -> ModelStatus {
        modelStatus[model.id] ?? .notDownloaded
    }

    /// Installs the runtime if needed, then downloads `model`.
    func install(_ model: MLXSpeechModel) {
        guard downloads[model.id] == nil else { return }
        modelStatus[model.id] = .downloading(nil)
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.downloads[model.id]?.id == id { self.downloads[model.id] = nil } }
            guard await self.ensureRuntime() else {
                self.modelStatus[model.id] = .failed("Install the mlx-audio runtime first")
                return
            }
            self.logger.log("Downloading \(model.repo)", level: .info)
            do {
                try await MLXAudioInstaller(environment: self.environment).downloadModel(model.repo) { [weak self] progress in
                    guard self?.downloads[model.id] != nil else { return }
                    self?.modelStatus[model.id] = .downloading(progress)
                }
                self.modelStatus[model.id] = .downloaded
                self.logger.log("Downloaded \(model.repo)", level: .info)
                if self.selectedVoice == .mlx(model) { self.applySelection(preparingKokoro: false) }
            } catch is CancellationError {
                self.refresh(model)
            } catch {
                self.logger.logError(error, context: "Download of \(model.repo) failed")
                self.modelStatus[model.id] = Task.isCancelled ? .notDownloaded : .failed(error.localizedDescription)
                if Task.isCancelled { self.refresh(model) }
            }
        }
        downloads[model.id] = (id, task)
    }

    /// Stops a download; files already fetched stay in the Hugging Face cache and
    /// the next download resumes from them.
    func cancelDownload(_ model: MLXSpeechModel) {
        downloads[model.id]?.task.cancel()
        downloads[model.id] = nil
        refresh(model)
    }

    func installRuntime() {
        Task { _ = await ensureRuntime(force: true) }
    }

    @discardableResult
    private func ensureRuntime(force: Bool = false) async -> Bool {
        if !force, environment.isInstalled {
            runtimeStatus = .installed
            return true
        }
        if let runtimeInstall { return await runtimeInstall.value }
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            self.runtimeStatus = .installing("Preparing…")
            do {
                // A reinstall replaces the worker's environment, so stop it first.
                self.runtime.shutdown()
                try await MLXAudioInstaller(environment: self.environment).installRuntime { [weak self] message in
                    self?.runtimeStatus = .installing(message)
                }
                self.runtimeStatus = .installed
                self.logger.log("mlx-audio runtime installed", level: .info)
                return true
            } catch {
                self.logger.logError(error, context: "mlx-audio runtime install failed")
                self.runtimeStatus = .failed(error.localizedDescription)
                return false
            }
        }
        runtimeInstall = task
        let installed = await task.value
        runtimeInstall = nil
        return installed
    }

    // MARK: - Managing models

    /// Re-reads which models are on disk, for example after the reader deletes
    /// one in Finder.
    func refresh() {
        if runtimeInstall == nil {
            runtimeStatus = environment.isInstalled ? .installed : (runtimeStatus.isFailure ? runtimeStatus : .notInstalled)
        }
        MLXSpeechModel.presets.forEach(refresh)
        if case .mlx(let model) = activeVoice, status(of: model) != .downloaded {
            // Its files are gone; fall back until it's downloaded again.
            applySelection(preparingKokoro: false)
        }
    }

    private func refresh(_ model: MLXSpeechModel) {
        guard downloads[model.id] == nil else { return }
        if MLXAudioEnvironment.isModelDownloaded(repo: model.repo) {
            modelStatus[model.id] = .downloaded
        } else if case .failed = modelStatus[model.id] {
            return
        } else {
            modelStatus[model.id] = .notDownloaded
        }
    }

    var modelsFolder: URL { MLXAudioEnvironment.hubCache() }

    /// Opens the Hugging Face cache, where each model is a `models--…` folder that
    /// can be moved to the Trash to free space.
    func revealModelsFolder() {
        let folder = modelsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func reveal(_ model: MLXSpeechModel) {
        let folder = MLXAudioEnvironment.modelFolder(repo: model.repo)
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            revealModelsFolder()
        }
    }

    func revealRuntimeFolder() {
        try? FileManager.default.createDirectory(at: environment.root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([environment.root])
    }

    /// Unloads the model now instead of waiting for the idle timeout.
    func unloadModel() {
        runtime.shutdown()
    }

    /// Stops the worker and downloads. Called from `applicationWillTerminate`, so
    /// everything here signals processes synchronously.
    func shutdown() {
        downloads.values.forEach { $0.task.cancel() }
        downloads = [:]
        runtimeInstall?.cancel()
        runtime.shutdown()
        player.shutDown()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    // MARK: - Selection

    private func selectionChanged() {
        notice = nil
        if case .mlx(let model) = selectedVoice, status(of: model) != .downloaded {
            install(model)
        }
        applySelection(preparingKokoro: false)
    }

    private func playbackSettingsChanged() {
        player.rate = Float(settings.readAloud.speed)
        runtime.idleTimeout = .seconds(settings.readAloud.idleUnloadMinutes * 60)
    }

    /// Makes read-aloud use the selected voice if it's ready; otherwise keeps the
    /// current voice and explains why in `notice`.
    private func applySelection(preparingKokoro: Bool) {
        guard let readAloud else { return }
        switch selectedVoice {
        case .system:
            notice = nil
            use(SystemSpeechEngine(), as: .system, on: readAloud)
        case .kokoro:
            notice = nil
            useKokoro(on: readAloud, preparing: preparingKokoro)
        case .mlx(let model):
            if status(of: model) == .downloaded, environment.isInstalled {
                notice = nil
                guard activeVoice != .mlx(model) else { return }
                let engine = MLXSpeechEngine(model: model, runtime: runtime, player: player) { [weak settings] in
                    settings?.modelOptions(for: model) ?? MLXModelOptions()
                }
                use(engine, as: .mlx(model), on: readAloud)
            } else {
                if case .downloading = status(of: model) {
                    notice = "\(model.name) is downloading; \(fallbackName) reads until it's ready."
                } else {
                    notice = "\(model.name) isn't downloaded yet. Download it in Settings → Read Aloud."
                }
                useKokoro(on: readAloud, preparing: preparingKokoro)
            }
        }
    }

    private var fallbackName: String { activeVoice == .system ? "the system voice" : "Kokoro" }

    private func useKokoro(on readAloud: ReadAloud, preparing: Bool) {
        if let kokoro, kokoro.isReady {
            use(kokoro, as: .kokoro, on: readAloud)
            return
        }
        // Until Kokoro has loaded, the system voice reads.
        if case .mlx = activeVoice { use(SystemSpeechEngine(), as: .system, on: readAloud) }
        guard preparing, kokoroPreparation == nil else { return }
        let kokoro = self.kokoro ?? KokoroSpeechEngine(player: player)
        self.kokoro = kokoro
        kokoroPreparation = Task { [weak self] in
            let ready = await kokoro.prepare()
            guard let self else { return }
            self.kokoroPreparation = nil
            guard ready else { return }
            // Selected voices may have changed while Kokoro loaded.
            self.applySelection(preparingKokoro: false)
        }
    }

    /// Switches only when the voice changes; the first call always applies, since
    /// read-aloud starts with its own system voice.
    private func use(_ engine: SpeechEngine, as voice: ReadAloudVoice, on readAloud: ReadAloud) {
        guard voice != activeVoice || currentEngine == nil else { return }
        currentEngine = engine
        activeVoice = voice
        readAloud.useEngine(engine)
        logger.log("Read-aloud voice is now \(voice.id)", level: .info)
    }

    private var currentEngine: SpeechEngine?
}

private extension ReadAloudVoices.RuntimeStatus {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Used when the worker script is missing from the bundle, so reads fail with a
/// clear error instead of crashing.
private struct MissingWorkerLauncher: MLXWorkerLauncher {
    func launch(onLine: @escaping @MainActor (String) -> Void,
                onExit: @escaping @MainActor (Int32) -> Void) throws -> MLXWorkerProcess {
        throw MLXAudioInstallerError.missingWorkerScript
    }
}
