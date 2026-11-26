import Combine
import Foundation

@MainActor
final class ReadAloudVoices: ObservableObject {
    enum DownloadStatus: Equatable {
        case missing
        case downloading(Double?)
        case cancelling
        case downloaded
        case failed(String)
    }

    let files = VoiceModelFiles.application
    let speech = ReadAloud()
    private(set) lazy var host = TTSModelHost(loader: MLXAudioModelLoader(files: files))
    private var activeVoice = ReadAloudVoice.system
    private var kokoroPreparation: Task<BufferedSpeechEngine?, Never>?
    private var downloads: [ExpressiveSpeechModel: Task<Bool, Never>] = [:]
    @Published private var statuses: [ExpressiveSpeechModel: DownloadStatus] = [:]

    func status(for model: ExpressiveSpeechModel) -> DownloadStatus {
        statuses[model] ?? (files.isDownloaded(model) ? .downloaded : .missing)
    }

    func refresh() {
        for model in ExpressiveSpeechModel.allCases where downloads[model] == nil {
            if files.isDownloaded(model) {
                if case .failed = statuses[model] { continue }
                statuses[model] = .downloaded
            } else if statuses[model] == .downloaded {
                statuses[model] = .missing
            }
        }
    }

    var hasActiveDownload: Bool { !downloads.isEmpty }

    func download(_ model: ExpressiveSpeechModel) {
        guard !hasActiveDownload else { return }
        statuses[model] = .downloading(nil)
        downloads[model] = Task { [weak self] in
            guard let self else { return false }
            defer { downloads[model] = nil }
            do {
                try await MLXAudioModelLoader(files: files).download(model) { [weak self] progress in
                    guard let self, case .downloading = self.statuses[model] else { return }
                    self.statuses[model] = .downloading(progress)
                }
                statuses[model] = .downloaded
                return true
            } catch {
                statuses[model] = .failed(Task.isCancelled ? "Download cancelled" : error.localizedDescription)
                return false
            }
        }
    }

    func cancelDownload(_ model: ExpressiveSpeechModel) {
        guard let task = downloads[model] else { return }
        statuses[model] = .cancelling
        task.cancel()
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
                kokoroPreparation = Task { await KokoroSpeechSource.makeEngine() }
            }
            let engine = await kokoroPreparation?.value
            guard !Task.isCancelled else { return }
            kokoroPreparation = nil
            if let engine { use(engine, as: .kokoro) }
            else { useSystem() }
        case .expressive(let model):
            if let download = downloads[model] {
                loading()
                let ready = await download.value
                guard !Task.isCancelled else { return }
                guard ready else { return useSystem() }
            }
            if case .failed = statuses[model] { return useSystem() }
            guard files.isDownloaded(model) else {
                if statuses[model] == .downloaded { statuses[model] = .missing }
                return useSystem()
            }
            if host.state != .ready(model) {
                loading()
                do {
                    try await host.prepare(model)
                } catch {
                    guard !Task.isCancelled else { return }
                    statuses[model] = .failed(error.localizedDescription)
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
            Task { await pending.value?.teardown() }
        }
        for task in downloads.values { task.cancel() }
    }

    private func useSystem() {
        if activeVoice != .system { use(SystemSpeechEngine(), as: .system) }
    }

    private func use(_ engine: SpeechEngine, as voice: ReadAloudVoice) {
        speech.useEngine(engine)
        activeVoice = voice
    }
}
