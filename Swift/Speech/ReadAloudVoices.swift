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

    init(files: VoiceModelFiles = .application) {
        self.files = files
        host = TTSModelHost(loader: MLXAudioModelLoader(files: files))
        downloads = ExpressiveVoiceDownloads(files: files)
        downloads.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    func status(for model: ExpressiveSpeechModel) -> ExpressiveVoiceDownloads.Status {
        downloads.status(for: model)
    }

    func refresh() {
        objectWillChange.send()
    }

    var hasActiveDownload: Bool { downloads.hasActiveDownload }

    func download(_ model: ExpressiveSpeechModel) {
        guard !hasActiveDownload else { return }
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
