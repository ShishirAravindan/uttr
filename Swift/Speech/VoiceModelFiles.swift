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

    struct StoredVoice: Identifiable {
        let model: ExpressiveSpeechModel
        let bytes: Int64
        let downloaded: Bool

        var id: ExpressiveSpeechModel { model }
    }

    func storedDirectory(for model: ExpressiveSpeechModel) -> URL? {
        let directory = directory(for: model)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let rootValues = try? root.resourceValues(forKeys: keys),
              rootValues.isDirectory == true, rootValues.isSymbolicLink == false,
              let values = try? directory.resourceValues(forKeys: keys),
              values.isDirectory == true, values.isSymbolicLink == false
        else { return nil }
        return directory
    }

    func storedVoices() -> [StoredVoice] {
        ExpressiveSpeechModel.allCases.compactMap { model in
            guard let directory = storedDirectory(for: model) else { return nil }
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys))
            else { return nil }
            var bytes: Int64 = 0
            for case let file as URL in files {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                      values.isSymbolicLink == false else { continue }
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
            let downloaded = isDownloaded(model)
            return bytes > 0 || downloaded ? StoredVoice(model: model, bytes: bytes, downloaded: downloaded) : nil
        }
    }

    func remove(_ model: ExpressiveSpeechModel) throws {
        guard let directory = storedDirectory(for: model) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.removeItem(at: directory)
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
