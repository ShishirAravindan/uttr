import Foundation

enum ReadAloudVoice: Hashable, Identifiable {
    case kokoro
    case system
    case expressive(ExpressiveSpeechModel)

    static let all = [Self.kokoro, .system] + ExpressiveSpeechModel.allCases.map(Self.expressive)

    init(id: String?) {
        if id == "system" { self = .system }
        else if let id, let model = ExpressiveSpeechModel(rawValue: id) { self = .expressive(model) }
        else { self = .kokoro }
    }

    var id: String {
        switch self {
        case .kokoro: return "kokoro"
        case .system: return "system"
        case .expressive(let model): return model.rawValue
        }
    }

    var title: String {
        switch self {
        case .kokoro: return "Kokoro"
        case .system: return "System"
        case .expressive(let model): return model.name
        }
    }
}
