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

// MARK: - Parameters

/// A stored parameter value. Settings keeps only values the reader changed.
enum TTSValue: Codable, Equatable, Hashable {
    case number(Double)
    case text(String)
    case flag(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .flag(let value): try container.encode(value)
        }
    }

    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var text: String? { if case .text(let value) = self { return value }; return nil }
    var flag: Bool? { if case .flag(let value) = self { return value }; return nil }
}

/// The values a reader set for one model, keyed by parameter ID.
typealias TTSParameterValues = [String: TTSValue]

/// One dial a model exposes. Settings draws controls from these, so choosing
/// defaults or hiding a dial later is a change here, not new UI.
struct TTSParameter: Identifiable, Hashable {
    enum Kind: Hashable {
        /// `typical` is shown when the value is left to the model's own default.
        case slider(range: ClosedRange<Double>, step: Double, typical: Double)
        case choice([String])
        case text(placeholder: String)
        case toggle
    }

    enum Tier: Hashable {
        /// Shapes how the voice sounds; shown with the voice.
        case character
        /// Sampling and consistency; collapsed under Advanced.
        case advanced
    }

    let id: String
    let label: String
    let caption: String?
    let kind: Kind
    let tier: Tier
    /// `nil` leaves the value to the model.
    let defaultValue: TTSValue?

    // Shared dials.
    static func speaker(_ speakers: [String], default speaker: String) -> TTSParameter {
        TTSParameter(id: "speaker", label: "Speaker", caption: nil, kind: .choice(speakers),
                     tier: .character, defaultValue: .text(speaker))
    }

    static func temperature(typical: Double) -> TTSParameter {
        TTSParameter(id: "temperature", label: "Variation",
                     caption: "Sampling temperature. Higher varies delivery more, and can garble words.",
                     kind: .slider(range: 0.1...1.3, step: 0.05, typical: typical), tier: .advanced, defaultValue: nil)
    }

    static func topP(typical: Double) -> TTSParameter {
        TTSParameter(id: "top_p", label: "Top-p",
                     caption: "Keeps the most likely choices that add up to this share. Lower is steadier.",
                     kind: .slider(range: 0.5...1.0, step: 0.01, typical: typical), tier: .advanced, defaultValue: nil)
    }

    static func repetitionPenalty(typical: Double) -> TTSParameter {
        TTSParameter(id: "repetition_penalty", label: "Repetition penalty",
                     caption: "Discourages repeated sounds; raise it if the voice loops or stutters.",
                     kind: .slider(range: 1.0...2.0, step: 0.05, typical: typical), tier: .advanced, defaultValue: nil)
    }

    static let consistentVoice = TTSParameter(
        id: "consistent_voice", label: "Keep the voice consistent",
        caption: "Uses the same random seed for every sentence, so the voice doesn't drift between them.",
        kind: .toggle, tier: .advanced, defaultValue: .flag(true))
}

// MARK: - Models

/// A speech-LLM preset run in-process on the Apple Silicon GPU by mlx-audio-swift.
struct MLXSpeechModel: Identifiable, Hashable {
    /// How the preset's parameters map onto a request.
    enum Family: String, Hashable {
        case chatterboxTurbo, chatterbox, qwen3VoiceDesign, qwen3CustomVoice, orpheus, marvis
    }

    let id: String
    let family: Family
    let name: String
    let summary: String
    /// Hugging Face repository the weights are downloaded from.
    let repo: String
    /// Approximate download size, for Settings.
    let approximateBytes: Int64
    let parameters: [TTSParameter]

    var approximateSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    func parameters(in tier: TTSParameter.Tier) -> [TTSParameter] {
        parameters.filter { $0.tier == tier }
    }

    func parameter(_ id: String) -> TTSParameter? {
        parameters.first { $0.id == id }
    }

    /// The reader's value, or the parameter's default. A stored choice that is no
    /// longer offered falls back to the default.
    func value(_ id: String, in values: TTSParameterValues) -> TTSValue? {
        guard let parameter = parameter(id) else { return nil }
        if let stored = values[id] {
            if case .choice(let options) = parameter.kind {
                if let text = stored.text, options.contains(text) { return stored }
            } else {
                return stored
            }
        }
        return parameter.defaultValue
    }

    static func preset(id: String) -> MLXSpeechModel? {
        presets.first { $0.id == id }
    }

    static let qwenSpeakers = ["Ryan", "Aiden", "Vivian", "Serena", "Uncle_Fu", "Dylan", "Eric"]
    static let orpheusSpeakers = ["tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe"]
    static let marvisSpeakers = ["conversational_a", "conversational_b", "conversational_fr", "conversational_de"]

    static let presets: [MLXSpeechModel] = [
        MLXSpeechModel(
            id: "mlx.chatterbox-turbo", family: .chatterboxTurbo, name: "Chatterbox Turbo",
            summary: "Fast, with lively, dramatic pacing",
            repo: "mlx-community/chatterbox-turbo-8bit", approximateBytes: 600_000_000,
            parameters: [.temperature(typical: 0.8), .consistentVoice]
        ),
        MLXSpeechModel(
            id: "mlx.chatterbox", family: .chatterbox, name: "Chatterbox",
            summary: "Dramatic delivery with tunable emotion",
            repo: "mlx-community/Chatterbox-TTS-fp16", approximateBytes: 1_600_000_000,
            parameters: [
                TTSParameter(id: "exaggeration", label: "Emotion", caption: "Higher is more dramatic and emotional.",
                             kind: .slider(range: 0...1, step: 0.05, typical: 0.5), tier: .character, defaultValue: .number(0.5)),
                TTSParameter(id: "cfg_weight", label: "Pace guidance", caption: "Lower is slower and more deliberate.",
                             kind: .slider(range: 0...1, step: 0.05, typical: 0.5), tier: .character, defaultValue: .number(0.5)),
                .temperature(typical: 0.8), .consistentVoice,
            ]
        ),
        MLXSpeechModel(
            id: "mlx.qwen3-voicedesign", family: .qwen3VoiceDesign, name: "Qwen3-TTS 1.7B VoiceDesign",
            summary: "A narrator you describe in words",
            repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16", approximateBytes: 4_300_000_000,
            parameters: [
                TTSParameter(id: "description", label: "Voice description",
                             caption: "Describe the narrator in plain words: age, warmth, pace, accent. The model builds the voice from it.",
                             kind: .text(placeholder: "A warm, articulate audiobook narrator…"), tier: .character,
                             defaultValue: .text("A warm, articulate audiobook narrator with a calm, measured pace who lets emotion come through in dialogue.")),
                .temperature(typical: 0.9), .topP(typical: 1.0), .repetitionPenalty(typical: 1.05), .consistentVoice,
            ]
        ),
        MLXSpeechModel(
            id: "mlx.qwen3-customvoice", family: .qwen3CustomVoice, name: "Qwen3-TTS 0.6B CustomVoice",
            summary: "Preset speakers with style direction; lighter",
            repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16", approximateBytes: 1_800_000_000,
            parameters: [
                .speaker(qwenSpeakers, default: "Ryan"),
                TTSParameter(id: "style", label: "Style direction",
                             caption: "How the speaker should read, for example \"calm and thoughtful\" or \"bright and playful\". Leave empty for a neutral read.",
                             kind: .text(placeholder: "calm and thoughtful"), tier: .character, defaultValue: nil),
                .temperature(typical: 0.9), .topP(typical: 1.0), .repetitionPenalty(typical: 1.05), .consistentVoice,
            ]
        ),
        MLXSpeechModel(
            id: "mlx.orpheus", family: .orpheus, name: "Orpheus 3B (4-bit)",
            summary: "Empathetic range; tags like <laugh> in the text work",
            repo: "mlx-community/orpheus-3b-0.1-ft-4bit", approximateBytes: 2_100_000_000,
            parameters: [
                .speaker(orpheusSpeakers, default: "tara"),
                .temperature(typical: 0.6), .topP(typical: 0.8), .repetitionPenalty(typical: 1.3), .consistentVoice,
            ]
        ),
        MLXSpeechModel(
            id: "mlx.marvis", family: .marvis, name: "Marvis 250M",
            summary: "Small and quick, with conversational cadence",
            repo: "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit", approximateBytes: 600_000_000,
            parameters: [
                .speaker(marvisSpeakers, default: "conversational_a"),
                .temperature(typical: 0.9), .consistentVoice,
            ]
        ),
    ]

    /// The request for one chunk, with the reader's values and the preset's
    /// defaults. Sampling values left unset use the model's own defaults.
    func request(text: String, values: TTSParameterValues) -> TTSRequest {
        func number(_ id: String) -> Float? { value(id, in: values)?.number.map(Float.init) }
        func string(_ id: String) -> String? {
            value(id, in: values)?.text?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }

        var voice: String?
        switch family {
        case .qwen3VoiceDesign:
            voice = string("description")
        case .qwen3CustomVoice:
            // mlx-audio-swift reads CustomVoice prompts as "speaker, instruction".
            let speaker = string("speaker") ?? "Ryan"
            voice = string("style").map { "\(speaker), \($0)" } ?? speaker
        case .orpheus, .marvis:
            voice = string("speaker")
        case .chatterbox, .chatterboxTurbo:
            voice = nil
        }

        return TTSRequest(
            repo: repo,
            text: text,
            voice: voice,
            temperature: number("temperature"),
            topP: number("top_p"),
            repetitionPenalty: number("repetition_penalty"),
            seed: value("consistent_voice", in: values)?.flag == true ? TTSRequest.consistentSeed : nil,
            exaggeration: number("exaggeration"),
            cfgWeight: number("cfg_weight")
        )
    }
}

/// One chunk to synthesize.
struct TTSRequest: Equatable, Sendable {
    /// The seed used for every chunk when the voice is kept consistent.
    static let consistentSeed: UInt64 = 0x75747472

    var repo: String
    var text: String
    var voice: String?
    var temperature: Float?
    var topP: Float?
    var repetitionPenalty: Float?
    var seed: UInt64?
    var exaggeration: Float?
    var cfgWeight: Float?
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
