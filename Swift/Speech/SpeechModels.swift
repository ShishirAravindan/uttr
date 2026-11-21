import Foundation

/// The read-aloud voices uttr offers. Settings stores `id`.
enum ReadAloudVoice: Equatable, Hashable {
    case system
    case kokoro
    case mlx(MLXSpeechModel)

    static let defaultID = "kokoro"

    init(id: String) {
        switch id {
        case "system": self = .system
        case "kokoro": self = .kokoro
        default:
            if let model = MLXSpeechModel.preset(id: id) {
                self = .mlx(model)
            } else {
                self = .kokoro
            }
        }
    }

    var id: String {
        switch self {
        case .system: return "system"
        case .kokoro: return "kokoro"
        case .mlx(let model): return model.id
        }
    }

    var displayName: String {
        switch self {
        case .system: return "System voice"
        case .kokoro: return "Kokoro"
        case .mlx(let model): return model.name
        }
    }
}

/// A speech-LLM preset run by the local mlx-audio worker on the Apple Silicon GPU.
struct MLXSpeechModel: Identifiable, Hashable {
    enum Family: String {
        case chatterbox, qwen3, orpheus, csm, miso
    }

    /// Model-specific controls Settings shows for this preset.
    enum Control: Hashable {
        /// A natural-language description of the voice, sent as `instruct`.
        case style
        /// Chatterbox's emotion intensity.
        case exaggeration
        /// Chatterbox's classifier-free guidance weight: lower is slower and more deliberate.
        case cfgWeight
    }

    /// How a style prompt is applied, for models that take one.
    enum StyleMode: String {
        /// The prompt designs the voice itself.
        case voiceDesign = "voice_design"
        /// The prompt directs one of the preset speakers.
        case customVoice = "custom_voice"
    }

    let id: String
    let family: Family
    let name: String
    let summary: String
    /// Hugging Face repository the weights are downloaded from.
    let repo: String
    /// Approximate download size, for Settings.
    let approximateBytes: Int64
    let voices: [String]
    let defaultVoice: String?
    let controls: Set<Control>
    let styleMode: StyleMode?
    let defaultStyle: String?
    let defaultTemperature: Double
    let langCode: String?

    var approximateSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    static func preset(id: String) -> MLXSpeechModel? {
        presets.first { $0.id == id }
    }

    static let presets: [MLXSpeechModel] = [
        MLXSpeechModel(
            id: "mlx.chatterbox-turbo", family: .chatterbox, name: "Chatterbox Turbo",
            summary: "Fast, with lively, dramatic pacing",
            repo: "mlx-community/chatterbox-turbo-fp16", approximateBytes: 900_000_000,
            voices: [], defaultVoice: nil, controls: [], styleMode: nil, defaultStyle: nil,
            defaultTemperature: 0.8, langCode: nil
        ),
        MLXSpeechModel(
            id: "mlx.chatterbox", family: .chatterbox, name: "Chatterbox",
            summary: "Dramatic delivery with tunable intensity",
            repo: "mlx-community/chatterbox-fp16", approximateBytes: 1_600_000_000,
            voices: [], defaultVoice: nil, controls: [.exaggeration, .cfgWeight], styleMode: nil,
            defaultStyle: nil, defaultTemperature: 0.8, langCode: nil
        ),
        MLXSpeechModel(
            id: "mlx.qwen3-voicedesign", family: .qwen3, name: "Qwen3-TTS 1.7B VoiceDesign",
            summary: "A narrator you describe in words",
            repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16", approximateBytes: 4_300_000_000,
            voices: [], defaultVoice: nil, controls: [.style], styleMode: .voiceDesign,
            defaultStyle: "A warm, articulate audiobook narrator with a calm, measured pace who lets emotion come through in dialogue.",
            defaultTemperature: 0.9, langCode: nil
        ),
        MLXSpeechModel(
            id: "mlx.qwen3-customvoice", family: .qwen3, name: "Qwen3-TTS 0.6B CustomVoice",
            summary: "Preset speakers with style direction; lighter",
            repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16", approximateBytes: 1_800_000_000,
            voices: ["Ryan", "Aiden", "Vivian", "Serena", "Uncle_Fu", "Dylan", "Eric"], defaultVoice: "Ryan",
            controls: [.style], styleMode: .customVoice,
            defaultStyle: "Read naturally, like a thoughtful narrator.",
            defaultTemperature: 0.9, langCode: nil
        ),
        MLXSpeechModel(
            id: "mlx.orpheus", family: .orpheus, name: "Orpheus 3B (4-bit)",
            summary: "Empathetic range and subtle inflection",
            repo: "mlx-community/orpheus-3b-0.1-ft-4bit", approximateBytes: 2_100_000_000,
            voices: ["tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe"], defaultVoice: "tara",
            controls: [], styleMode: nil, defaultStyle: nil, defaultTemperature: 0.6, langCode: nil
        ),
        MLXSpeechModel(
            id: "mlx.csm", family: .csm, name: "Sesame CSM 1B",
            summary: "Conversational cadence, breaths, and pauses",
            repo: "mlx-community/csm-1b", approximateBytes: 3_000_000_000,
            voices: [], defaultVoice: nil, controls: [], styleMode: nil, defaultStyle: nil,
            defaultTemperature: 0.9, langCode: nil
        ),
        MLXSpeechModel(
            id: "mlx.miso", family: .miso, name: "MisoTTS (8-bit)",
            summary: "Conversational flow; the largest download",
            repo: "mlx-community/MisoLabs-MisoTTS-8bit", approximateBytes: 9_000_000_000,
            voices: [], defaultVoice: nil, controls: [], styleMode: nil, defaultStyle: nil,
            defaultTemperature: 0.9, langCode: nil
        ),
    ]
}

/// The choices a reader makes for one mlx-audio preset. Missing values use the
/// preset's defaults, so improvements to them reach anyone who hasn't edited them.
struct MLXModelOptions: Codable, Equatable {
    var voice: String?
    var style: String?
    var exaggeration: Double?
    var cfgWeight: Double?
    var temperature: Double?

    enum CodingKeys: String, CodingKey {
        case voice, style, exaggeration
        case cfgWeight = "cfg_weight"
        case temperature
    }

    init(voice: String? = nil, style: String? = nil, exaggeration: Double? = nil,
         cfgWeight: Double? = nil, temperature: Double? = nil) {
        self.voice = voice
        self.style = style
        self.exaggeration = exaggeration
        self.cfgWeight = cfgWeight
        self.temperature = temperature
    }

    static let defaultExaggeration = 0.5
    static let defaultCFGWeight = 0.5

    /// The request fields for one chunk, with defaults filled in and controls the
    /// preset doesn't have left out.
    func request(for model: MLXSpeechModel, text: String) -> MLXSpeechRequest {
        let voice = voice.flatMap { model.voices.contains($0) ? $0 : nil } ?? model.defaultVoice
        let style = model.controls.contains(.style)
            ? (style?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? model.defaultStyle
            : nil
        return MLXSpeechRequest(
            model: model.repo,
            input: text,
            voice: voice,
            instruct: style,
            mode: model.styleMode?.rawValue,
            langCode: model.langCode,
            temperature: temperature ?? model.defaultTemperature,
            exaggeration: model.controls.contains(.exaggeration) ? (exaggeration ?? Self.defaultExaggeration) : nil,
            cfgWeight: model.controls.contains(.cfgWeight) ? (cfgWeight ?? Self.defaultCFGWeight) : nil
        )
    }
}

/// The body of the worker's `/v1/audio/speech` request.
struct MLXSpeechRequest: Codable, Equatable {
    var model: String
    var input: String
    var voice: String?
    var instruct: String?
    var mode: String?
    var langCode: String?
    var temperature: Double?
    var exaggeration: Double?
    var cfgWeight: Double?
    var requestID: String?

    enum CodingKeys: String, CodingKey {
        case model, input, voice, instruct, mode
        case langCode = "lang_code"
        case temperature, exaggeration
        case cfgWeight = "cfg_weight"
        case requestID = "request_id"
    }
}
