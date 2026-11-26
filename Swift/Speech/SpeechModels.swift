import Foundation

/// The stable identifiers and model inputs used by the expressive voice catalog.
enum ExpressiveSpeechModel: String, CaseIterable, Sendable {
    case chatterboxTurbo = "mlx.chatterbox-turbo"
    case chatterbox = "mlx.chatterbox"
    case qwenVoiceDesign = "mlx.qwen3-voicedesign"
    case qwenCustomVoice = "mlx.qwen3-customvoice"
    case orpheus = "mlx.orpheus"
    case marvis = "mlx.marvis"

    var name: String { details.name }
    var repository: String { details.repository }
    var estimatedDownloadBytes: Int64 { details.bytes }

    /// VoiceDesign describes a voice, and the other presets with a voice argument
    /// use the reference preset's default speaker. Sampling remains at model defaults.
    var defaultVoice: String? {
        switch self {
        case .chatterboxTurbo, .chatterbox: return nil
        case .qwenVoiceDesign:
            return "A warm, articulate audiobook narrator with a calm, measured pace who lets emotion come through in dialogue."
        case .qwenCustomVoice: return "Ryan"
        case .orpheus: return "tara"
        case .marvis: return "conversational_a"
        }
    }

    private var details: (name: String, repository: String, bytes: Int64) {
        switch self {
        case .chatterboxTurbo:
            return ("Chatterbox Turbo", "mlx-community/chatterbox-turbo-8bit", 600_000_000)
        case .chatterbox:
            return ("Chatterbox", "mlx-community/Chatterbox-TTS-fp16", 1_600_000_000)
        case .qwenVoiceDesign:
            return ("Qwen3-TTS 1.7B VoiceDesign", "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16", 4_300_000_000)
        case .qwenCustomVoice:
            return ("Qwen3-TTS 0.6B CustomVoice", "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16", 1_800_000_000)
        case .orpheus:
            return ("Orpheus 3B (4-bit)", "mlx-community/orpheus-3b-0.1-ft-4bit", 2_100_000_000)
        case .marvis:
            return ("Marvis 250M", "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit", 600_000_000)
        }
    }
}
