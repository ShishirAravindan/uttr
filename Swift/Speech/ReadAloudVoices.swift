import Combine
import Foundation

@MainActor
final class ReadAloudVoices: ObservableObject {
    let files: VoiceModelFiles
    let speech = ReadAloud()
    private let host: TTSModelHost
    private let downloads: ExpressiveVoiceDownloads
    private var activeVoice = ReadAloudVoice.system
    private var kokoroPreparation: SharedVoicePreparation<BufferedSpeechEngine?>?
    @Published private(set) var preparationErrors: [ExpressiveSpeechModel: String] = [:]

    @Published private(set) var storedVoices: [VoiceModelFiles.StoredVoice] = []
    @Published private(set) var loadedModel: ExpressiveSpeechModel?
    @Published private(set) var readActive = false
    @Published private(set) var removing: ExpressiveSpeechModel?
    @Published private(set) var storageMessage: String?
    private var readGeneration = 0

    init(files: VoiceModelFiles = .application) {
        self.files = files
        host = TTSModelHost(loader: MLXAudioModelLoader(files: files))
        downloads = ExpressiveVoiceDownloads(files: files)
        downloads.onChange = { [weak self] in self?.objectWillChange.send() }
        downloads.onSettled = { [weak self] in self?.refresh() }
        host.onStateChange = { [weak self] state in
            if case .ready(let model) = state { self?.loadedModel = model }
            else { self?.loadedModel = nil }
        }
    }

    func updateReadActivity(_ active: Bool) {
        if active && !readActive { readGeneration += 1 }
        readActive = active
    }

    func canRemove(_ model: ExpressiveSpeechModel) -> Bool {
        !readActive && removing == nil && !downloads.isDownloading(model)
    }

    func remove(_ model: ExpressiveSpeechModel, onRemoved: @escaping () -> Void) {
        guard canRemove(model) else {
            storageMessage = "Finish the current read or download before removing this model."
            return
        }
        let generation = readGeneration
        removing = model
        storageMessage = nil
        Task {
            defer {
                removing = nil
                refresh()
            }
            let isStillIdle = { [self] in !readActive && readGeneration == generation }
            do {
                try await host.unload(model, whileAllowed: isStillIdle)
                guard isStillIdle() else { throw CancellationError() }
                try files.remove(model)
                preparationErrors[model] = nil
                downloads.clearFailure(for: model)
                onRemoved()
            } catch is CancellationError {
                storageMessage = "A read started. Try removing the model again when read-aloud is idle."
            } catch {
                storageMessage = "Couldn’t remove the model: \(error.localizedDescription)"
            }
        }
    }

    func revealDirectory(for model: ExpressiveSpeechModel) -> URL? {
        guard let directory = files.storedDirectory(for: model) else {
            refresh()
            storageMessage = "The model folder is no longer on disk."
            return nil
        }
        storageMessage = nil
        return directory
    }

    func status(for model: ExpressiveSpeechModel) -> ExpressiveVoiceDownloads.Status {
        downloads.status(for: model)
    }

    func refresh() {
        storedVoices = files.storedVoices()
        objectWillChange.send()
    }

    var hasActiveDownload: Bool { downloads.hasActiveDownload }

    func download(_ model: ExpressiveSpeechModel) {
        guard !hasActiveDownload, removing == nil else { return }
        preparationErrors[model] = nil
        downloads.download(model)
    }

    func cancelDownload(_ model: ExpressiveSpeechModel) {
        downloads.cancel(model)
    }

    func retryPreparation(_ model: ExpressiveSpeechModel) {
        preparationErrors[model] = nil
    }

    /// The coordinator snapshots the voice before copying the selection.
    func prepare(_ voice: ReadAloudVoice, loading: () -> Void) async {
        guard !Task.isCancelled else { return }
        switch voice {
        case .system:
            useSystem()
        case .kokoro:
            guard activeVoice != .kokoro else { return }
            loading()
            if kokoroPreparation == nil {
                kokoroPreparation = SharedVoicePreparation { await KokoroSpeechSource.makeEngine() }
            }
            let engine = try? await kokoroPreparation?.value()
            guard !Task.isCancelled else { return }
            kokoroPreparation = nil
            if let engine { use(engine, as: .kokoro) }
            else { useSystem() }
        case .expressive(let model):
            if let preparation = downloads.waitingPreparation(for: model) {
                loading()
                do {
                    try await preparation.value()
                } catch {
                    if !Task.isCancelled { useSystem() }
                    return
                }
            }
            guard !Task.isCancelled else { return }
            guard downloads.status(for: model) == .downloaded, preparationErrors[model] == nil else {
                return useSystem()
            }
            if host.state != .ready(model) {
                loading()
                do {
                    try await host.prepare(model)
                } catch {
                    guard !Task.isCancelled else { return }
                    preparationErrors[model] = error.localizedDescription
                    return useSystem()
                }
            }
            guard !Task.isCancelled else { return }
            if activeVoice != voice { use(MLXSpeechSource.makeEngine(model: model, host: host), as: voice) }
        }
    }

    func cancelPreparation() {
        if let pending = kokoroPreparation {
            pending.cancel()
            kokoroPreparation = nil
            Task { if let engine = try? await pending.value() { await engine.teardown() } }
        }
        downloads.cancelAll()
    }

    private func useSystem() {
        if activeVoice != .system { use(SystemSpeechEngine(), as: .system) }
    }

    private func use(_ engine: SpeechEngine, as voice: ReadAloudVoice) {
        speech.useEngine(engine)
        activeVoice = voice
    }
}
