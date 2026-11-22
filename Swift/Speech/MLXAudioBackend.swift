import Foundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioTTS

/// The only file that talks to mlx-audio-swift: loads speech-LLMs in-process on
/// the Apple Silicon GPU and downloads their weights into the Hugging Face cache.
struct MLXAudioModelLoader: SpeechModelLoader {
    func load(repo: String) async throws -> LoadedSpeechModel {
        MLXLoadedSpeechModel(model: try await TTS.loadModel(modelRepo: repo))
    }

    func didUnload() {
        Memory.clearCache()
    }
}

/// One loaded mlx-audio-swift model. The host never calls it concurrently.
final class MLXLoadedSpeechModel: LoadedSpeechModel, @unchecked Sendable {
    private let model: SpeechGenerationModel

    init(model: SpeechGenerationModel) { self.model = model }

    var sampleRate: Int { model.sampleRate }

    func synthesize(_ request: TTSRequest) async throws -> [Float] {
        // Chatterbox reads emotion and CFG from the model rather than the request.
        if let chatterbox = model as? ChatterboxModel {
            chatterbox.emotionAdvOverride = request.exaggeration
            chatterbox.cfgWeightOverride = request.cfgWeight
        }
        var parameters = model.defaultGenerationParameters
        if let temperature = request.temperature { parameters.temperature = temperature }
        if let topP = request.topP { parameters.topP = topP }
        if let penalty = request.repetitionPenalty { parameters.repetitionPenalty = penalty }
        // Most models sample from MLX's global generator, so seeding it keeps the
        // voice the same from one chunk to the next.
        if let seed = request.seed {
            parameters.seed = seed
            MLXRandom.seed(seed)
        }
        let audio = try await model.generate(
            text: request.text,
            voice: request.voice,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: parameters
        )
        return audio.reshaped(-1).asArray(Float.self)
    }
}

enum MLXModelDownloader {
    /// Downloads `repo`'s weights and configuration, reporting the fraction done.
    /// Files already present are kept, so a cancelled download resumes. Codec and
    /// tokenizer repositories a model needs are fetched when it first loads.
    static func download(_ repo: String, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard let id = Repo.ID(rawValue: repo) else { throw TTSModelError.invalidRepositoryID(repo) }
        let cache = HubCache.default
        _ = try await ModelUtils.resolveOrDownloadModel(
            client: HubClient(cache: cache),
            cache: cache,
            repoID: id,
            requiredExtension: "safetensors",
            progressHandler: { progress($0.fractionCompleted) }
        )
    }
}
