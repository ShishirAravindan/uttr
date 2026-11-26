import Foundation

/// Each preset has its own managed directory. Shared upstream assets live outside it.
struct VoiceModelFiles {
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
        let directory = directory(for: model)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(".uttr-ready").path) else { return false }
        let payload = payload(model.repository, in: directory)
        guard FileManager.default.fileExists(atPath: payload.appendingPathComponent("config.json").path),
              let entries = try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.fileSizeKey])
        else { return false }
        return entries.contains { file in
            file.pathExtension == "safetensors" && ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }
    }

    func markDownloaded(_ model: ExpressiveSpeechModel) throws {
        try Data().write(to: directory(for: model).appendingPathComponent(".uttr-ready"), options: .atomic)
    }
}
