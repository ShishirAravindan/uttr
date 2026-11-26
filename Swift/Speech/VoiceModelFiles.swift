import Foundation

/// Each preset has its own managed directory. Shared upstream assets live outside it.
struct VoiceModelFiles {
    static let orpheusCodec = "mlx-community/snac_24khz"
    static let marvisCodec = "kyutai/moshiko-pytorch-bf16"
    static let marvisCodecWeights = "tokenizer-e351c8d8-checkpoint125.safetensors"

    let root: URL

    static var application: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundle = Bundle.main.bundleIdentifier ?? "uttr"
        return Self(root: support.appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("Voice Models", isDirectory: true))
    }

    func directory(for model: ExpressiveSpeechModel) -> URL {
        root.appendingPathComponent(model.rawValue, isDirectory: true)
    }

    func payload(_ repository: String, in directory: URL) -> URL {
        directory.appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(repository.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    func isDownloaded(_ model: ExpressiveSpeechModel) -> Bool {
        let marker = directory(for: model).appendingPathComponent(".uttr-ready")
        return FileManager.default.fileExists(atPath: marker.path) && hasModelFiles(model)
    }

    func markDownloaded(_ model: ExpressiveSpeechModel) throws {
        guard hasModelFiles(model) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The download is missing files required to read with \(model.name)."
            ])
        }
        try Data().write(to: directory(for: model).appendingPathComponent(".uttr-ready"), options: .atomic)
    }

    private func hasModelFiles(_ model: ExpressiveSpeechModel) -> Bool {
        let directory = directory(for: model)
        let modelDirectory = payload(model.repository, in: directory)
        guard hasFile("config.json", in: modelDirectory), hasWeights(in: modelDirectory) else { return false }

        switch model {
        case .chatterbox, .chatterboxTurbo:
            return hasFile("conds.safetensors", in: modelDirectory)
        case .qwenCustomVoice, .qwenVoiceDesign:
            let tokenizer = modelDirectory.appendingPathComponent("speech_tokenizer", isDirectory: true)
            return hasFile("config.json", in: tokenizer) && hasWeights(in: tokenizer)
        case .orpheus:
            let codec = payload(Self.orpheusCodec, in: directory)
            return hasFile("config.json", in: codec) && hasFile("model.safetensors", in: codec)
        case .marvis:
            return hasFile(Self.marvisCodecWeights, in: payload(Self.marvisCodec, in: directory))
        }
    }

    private func hasWeights(in directory: URL) -> Bool {
        let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        return entries?.contains { file in
            file.pathExtension == "safetensors" && file.lastPathComponent != "conds.safetensors"
                && ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        } ?? false
    }

    private func hasFile(_ name: String, in directory: URL) -> Bool {
        let file = directory.appendingPathComponent(name)
        return ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }
}
