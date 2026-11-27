import MLX
import MLXAudioTTS

/// Wraps the upstream model without exposing MLX types to the app's speech pipeline.
struct MLXAudioModelLoader: SpeechModelLoader {
    func load(_ preset: ExpressiveSpeechModel) async throws -> LoadedSpeechModel {
        MLXLoadedSpeechModel(model: try await TTS.loadModel(modelRepo: preset.repository))
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
