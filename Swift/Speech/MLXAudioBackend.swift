import Foundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioTTS

/// Wraps the upstream model without exposing MLX types to the app's speech pipeline.
struct MLXAudioModelLoader: SpeechModelLoader {
    let files: VoiceModelFiles

    func load(_ preset: ExpressiveSpeechModel) async throws -> LoadedSpeechModel {
        let directory = files.directory(for: preset)
        let cache = HubCache(cacheDirectory: directory)
        let payload = files.payload(preset.repository, in: directory)
        let model: SpeechGenerationModel
        switch preset {
        case .orpheus:
            // Pass the owned cache through to Orpheus's codec loader.
            model = try await LlamaTTSModel.fromModelDirectory(payload, cache: cache)
        case .marvis:
            // Marvis resolves its prompt and codec files from the supplied cache.
            model = try await TTS.loadModel(modelRepo: preset.repository, modelType: "csm", cache: cache)
        default:
            model = try await TTS.loadModel(modelRepo: payload.path, cache: cache)
        }
        if let chatterbox = model as? ChatterboxModel, chatterbox.defaultConditioning == nil {
            throw AudioGenerationError.modelNotInitialized("This Chatterbox checkpoint has no default voice.")
        }
        return MLXLoadedSpeechModel(model: model)
    }

    func download(_ preset: ExpressiveSpeechModel, progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws {
        let directory = files.directory(for: preset)
        let cache = HubCache(cacheDirectory: directory)
        let reports: @MainActor @Sendable (Progress) -> Void = { value in
            progress(value.totalUnitCount > 0 ? value.fractionCompleted : nil)
        }
        try await fetch(preset.repository, cache: cache, progress: reports)
        try Task.checkCancellation()
        progress(nil)
        switch preset {
        case .orpheus:
            try await fetch(VoiceModelFiles.orpheusCodec, cache: cache, progress: nil)
        case .chatterbox, .chatterboxTurbo:
            // The pinned Chatterbox loader uses its shared default cache for this tokenizer.
            try await fetch("mlx-community/S3TokenizerV2", cache: .default, progress: nil)
        case .marvis:
            let repository = VoiceModelFiles.marvisCodec
            let codec = files.payload(repository, in: directory)
            let name = VoiceModelFiles.marvisCodecWeights
            if !FileManager.default.fileExists(atPath: codec.appendingPathComponent(name).path) {
                _ = try await HubClient(cache: cache).downloadSnapshot(
                    of: repoID(repository), kind: .model, to: codec, matching: [name]
                )
            }
        default: break
        }
        try Task.checkCancellation()
        try files.markDownloaded(preset)
    }

    private func fetch(_ repository: String, cache: HubCache, progress: (@MainActor @Sendable (Progress) -> Void)?) async throws {
        _ = try await ModelUtils.resolveOrDownloadModel(
            client: HubClient(cache: cache), cache: cache, repoID: repoID(repository),
            requiredExtension: "safetensors", progressHandler: progress
        )
    }

    private func repoID(_ repository: String) throws -> Repo.ID {
        guard let id = Repo.ID(rawValue: repository) else { throw TTSModelError.invalidRepositoryID(repository) }
        return id
    }

    func clearCache() {
        Memory.clearCache()
    }
}

private final class MLXLoadedSpeechModel: LoadedSpeechModel {
    private let model: SpeechGenerationModel

    init(model: SpeechGenerationModel) {
        self.model = model
    }

    func synthesize(_ text: String, voice: String?) async throws -> SpeechClip {
        let audio = try await model.generate(
            text: text,
            voice: voice,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: model.defaultGenerationParameters
        )
        return SpeechClip(samples: audio.asArray(Float.self), sampleRate: Double(model.sampleRate))
    }
}
