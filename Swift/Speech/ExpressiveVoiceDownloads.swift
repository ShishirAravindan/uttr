import Foundation

@MainActor
final class ExpressiveVoiceDownloads {
    enum Status: Equatable {
        case missing
        case downloading(Double?)
        case cancelling
        case downloaded
        case failed(String)
    }

    private struct Transfer {
        let id: UUID
        let model: ExpressiveSpeechModel
        let preparation: SharedVoicePreparation<Void>
        var status: Status
    }

    private let files: VoiceModelFiles
    private var transfer: Transfer?
    private var failures: [ExpressiveSpeechModel: String] = [:]
    var onChange: (() -> Void)?
    var onSettled: (() -> Void)?

    init(files: VoiceModelFiles) {
        self.files = files
    }

    var hasActiveDownload: Bool { transfer != nil }

    func isDownloading(_ model: ExpressiveSpeechModel) -> Bool {
        transfer?.model == model
    }

    func clearFailure(for model: ExpressiveSpeechModel) {
        failures[model] = nil
        onChange?()
    }

    func status(for model: ExpressiveSpeechModel) -> Status {
        if let transfer, transfer.model == model { return transfer.status }
        if let failure = failures[model] { return .failed(failure) }
        return files.isDownloaded(model) ? .downloaded : .missing
    }

    func download(_ model: ExpressiveSpeechModel) {
        guard transfer == nil else { return }
        let id = UUID()
        failures[model] = nil
        let preparation = SharedVoicePreparation<Void> { [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                self.transfer = nil
                self.onChange?()
                self.onSettled?()
            }
            do {
                try await MLXAudioModelLoader(files: self.files).download(model) { [weak self] fraction in
                    guard let self, self.transfer?.id == id,
                          case .downloading = self.transfer?.status else { return }
                    self.transfer?.status = .downloading(fraction)
                    self.onChange?()
                }
                try Task.checkCancellation()
            } catch {
                self.failures[model] = Task.isCancelled ? "Download cancelled" : error.localizedDescription
                throw error
            }
        }
        transfer = Transfer(id: id, model: model, preparation: preparation, status: .downloading(nil))
        onChange?()
    }

    func waitingPreparation(for model: ExpressiveSpeechModel) -> SharedVoicePreparation<Void>? {
        guard transfer?.model == model else { return nil }
        return transfer?.preparation
    }

    func cancel(_ model: ExpressiveSpeechModel) {
        guard transfer?.model == model else { return }
        transfer?.status = .cancelling
        transfer?.preparation.cancel()
        onChange?()
    }

    func cancelAll() {
        if let model = transfer?.model { cancel(model) }
    }
}
