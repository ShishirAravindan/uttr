import AppKit
import Combine

/// Owns the read-aloud voices and the in-process model host: picks the engine for
/// the selected voice, downloads and removes expressive models, and reports their
/// state to Settings and the popover.
///
/// The system voice is always available. Kokoro loads on the first read, as
/// before. An expressive voice is used once its model is downloaded; the model
/// loads on the first sentence and unloads when idle. Until a selected voice is
/// ready, the previous voice keeps reading.
@MainActor
final class ReadAloudVoices: ObservableObject {
    enum ModelStatus: Equatable {
        case notDownloaded
        /// The fraction downloaded, or `nil` while starting or preparing the model.
        case downloading(Double?)
        case downloaded
        case failed(String)
    }

    /// A downloaded model as Settings → General → Storage lists it.
    struct StoredModel: Identifiable, Equatable {
        let model: MLXSpeechModel
        let bytes: Int64
        var id: String { model.id }
    }

    @Published private(set) var modelStatus: [String: ModelStatus] = [:]
    @Published private(set) var hostState: TTSModelHostState = .unloaded
    @Published private(set) var storedModels: [StoredModel] = []
    /// The voice actually reading, which lags the selection until it is ready.
    @Published private(set) var activeVoice: ReadAloudVoice = .system
    /// Why the selected voice isn't the active one, when there's a reason to show.
    @Published private(set) var notice: String?

    let player = SpeechAudioPlayer()
    let host: TTSModelHost
    private let settings: SettingsManager
    private weak var readAloud: ReadAloud?
    private var currentEngine: SpeechEngine?
    private var kokoro: KokoroSpeechEngine?
    private var kokoroPreparation: Task<Void, Never>?
    private var downloads: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(componentName: "ReadAloudVoices")

    static let previewText = "Hello! This is how I'll read to you. \"Really?\" she asked, leaning closer. \"Every word of it?\""

    init(settings: SettingsManager) {
        self.settings = settings
        host = TTSModelHost(loader: MLXAudioModelLoader(),
                            idleTimeout: .seconds(settings.readAloud.idleUnloadMinutes * 60))
        player.rate = Float(settings.readAloud.speed)
        host.onStateChange = { [weak self] state in self?.hostState = state }
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

    /// Whether Preview would use the selected voice rather than a fallback.
    var canPreview: Bool { activeVoice == selectedVoice && readAloud != nil }

    /// Reads a short sample with dialogue and a question, without touching history.
    func preview() {
        guard let readAloud else { return }
        if readAloud.isSpeaking { readAloud.stop() }
        readAloud.speak(Self.previewText)
    }

    // MARK: - Downloads

    func status(of model: MLXSpeechModel) -> ModelStatus {
        modelStatus[model.id] ?? .notDownloaded
    }

    /// Downloads `model`, then loads it once so the codec and tokenizer files it
    /// needs are fetched too. The model then stays warm until the idle timeout.
    func download(_ model: MLXSpeechModel) {
        guard downloads[model.id] == nil else { return }
        modelStatus[model.id] = .downloading(nil)
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.downloads[model.id]?.id == id { self.downloads[model.id] = nil } }
            self.logger.log("Downloading \(model.repo)", level: .info)
            do {
                try await MLXModelDownloader.download(model.repo) { [weak self] fraction in
                    guard self?.downloads[model.id]?.id == id else { return }
                    self?.modelStatus[model.id] = .downloading(fraction)
                }
                try Task.checkCancellation()
                self.modelStatus[model.id] = .downloading(nil)
                try await self.host.warmUp(model.repo)
                self.modelStatus[model.id] = .downloaded
                self.logger.log("Downloaded \(model.repo)", level: .info)
                self.refreshStorage()
                if self.selectedVoice == .mlx(model) { self.applySelection(preparingKokoro: false) }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self.refresh(model)
                } else {
                    self.logger.logError(error, context: "Download of \(model.repo) failed")
                    self.modelStatus[model.id] = .failed(error.localizedDescription)
                }
            }
        }
        downloads[model.id] = (id, task)
    }

    /// Stops a download; files already fetched stay, and the next download resumes.
    func cancelDownload(_ model: MLXSpeechModel) {
        downloads[model.id]?.task.cancel()
        downloads[model.id] = nil
        refresh(model)
    }

    /// Deletes the model's folder, unloading it first if it's in memory.
    func remove(_ model: MLXSpeechModel) {
        cancelDownload(model)
        if hostState == .ready(model.repo) || hostState == .loading(model.repo) {
            if case .mlx(let active) = activeVoice, active == model { readAloud?.stop() }
            host.unload()
        }
        do {
            try FileManager.default.removeItem(at: TTSModelFiles.folder(repo: model.repo))
            logger.log("Removed \(model.repo)", level: .info)
        } catch {
            logger.logError(error, context: "Couldn't remove \(model.repo)")
        }
        refresh()
    }

    // MARK: - Managing models

    /// Re-reads which models are on disk, for example after the reader deletes
    /// one in Finder.
    func refresh() {
        MLXSpeechModel.presets.forEach(refresh)
        refreshStorage()
        if case .mlx(let model) = activeVoice, status(of: model) != .downloaded {
            // Its files are gone; fall back until it's downloaded again.
            applySelection(preparingKokoro: false)
        }
    }

    private func refresh(_ model: MLXSpeechModel) {
        guard downloads[model.id] == nil else { return }
        if TTSModelFiles.isDownloaded(repo: model.repo) {
            modelStatus[model.id] = .downloaded
        } else if case .failed = modelStatus[model.id] {
            return
        } else {
            modelStatus[model.id] = .notDownloaded
        }
    }

    private func refreshStorage() {
        storedModels = MLXSpeechModel.presets
            .filter { status(of: $0) == .downloaded }
            .map { StoredModel(model: $0, bytes: TTSModelFiles.size(of: TTSModelFiles.folder(repo: $0.repo))) }
    }

    var modelsFolder: URL { TTSModelFiles.modelsRoot() }

    func revealModelsFolder() {
        let folder = modelsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func reveal(_ model: MLXSpeechModel) {
        let folder = TTSModelFiles.folder(repo: model.repo)
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            revealModelsFolder()
        }
    }

    /// Unloads the model now instead of waiting for the idle timeout.
    func unloadModel() {
        if case .mlx = activeVoice, readAloud?.isSpeaking == true { readAloud?.stop() }
        host.unload()
    }

    /// Stops downloads and releases the model. Called from `applicationWillTerminate`.
    func shutdown() {
        downloads.values.forEach { $0.task.cancel() }
        downloads = [:]
        host.unload()
        player.shutDown()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    // MARK: - Selection

    private func selectionChanged() {
        notice = nil
        if case .mlx(let model) = selectedVoice, status(of: model) == .notDownloaded {
            download(model)
        }
        applySelection(preparingKokoro: false)
    }

    private func playbackSettingsChanged() {
        player.rate = Float(settings.readAloud.speed)
        host.idleTimeout = .seconds(settings.readAloud.idleUnloadMinutes * 60)
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
            if status(of: model) == .downloaded {
                notice = nil
                guard activeVoice != .mlx(model) else { return }
                // A different expressive model was loaded; free it now rather than
                // holding two in memory until the idle timeout.
                if case .mlx = activeVoice { host.unload() }
                let settings = self.settings
                let engine = MLXSpeechEngine(
                    model: model, host: host, player: player,
                    sentencesPerChunk: { [weak settings] in settings?.readAloud.sentencesPerChunk ?? 3 },
                    values: { [weak settings] in settings?.parameterValues(for: model) ?? [:] }
                )
                use(engine, as: .mlx(model), on: readAloud)
            } else {
                switch status(of: model) {
                case .downloading:
                    notice = "\(model.name) is downloading; \(fallbackName) reads until it's ready."
                case .failed(let message):
                    notice = "\(model.name) couldn't download: \(message)"
                default:
                    notice = "\(model.name) isn't downloaded yet. Download it in Settings → Text to Speech."
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
            // The selection may have changed while Kokoro loaded.
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
}
