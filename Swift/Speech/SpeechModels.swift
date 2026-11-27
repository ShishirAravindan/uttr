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
    /// Full transfer on an empty cache, including required codec and tokenizer files.
    /// Totals come from the selected files in the Hub manifests used for download.
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
        let sharedChatterboxTokenizerBytes: Int64 = 494_869_110
        switch self {
        case .chatterboxTurbo:
            return ("Chatterbox Turbo", "mlx-community/chatterbox-turbo-8bit", 708_113_148 + sharedChatterboxTokenizerBytes)
        case .chatterbox:
            return ("Chatterbox", "mlx-community/chatterbox-fp16", 2_576_563_671 + sharedChatterboxTokenizerBytes)
        case .qwenVoiceDesign:
            return ("Qwen3-TTS 1.7B VoiceDesign", "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16", 4_520_192_405)
        case .qwenCustomVoice:
            return ("Qwen3-TTS 0.6B CustomVoice", "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16", 2_498_416_818)
        case .orpheus:
            return ("Orpheus 3B (4-bit)", "mlx-community/orpheus-3b-0.1-ft-4bit", 1_885_366_468 + 79_405_251)
        case .marvis:
            return ("Marvis 250M", "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit", 672_145_980 + 384_644_900)
        }
    }
}
