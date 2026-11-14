import Foundation
#if canImport(FoundationModels)
import FoundationModels
import NaturalLanguage
#endif

@MainActor
enum CleanupBackendFactory {
    static func make() -> CleanupGenerating {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleCleanupBackend() }
        #endif
        return UnavailableCleanupBackend()
    }

    static var isModelAvailable: Bool { make().isAvailable }
}

@MainActor
private final class UnavailableCleanupBackend: CleanupGenerating {
    var isAvailable: Bool { false }
    func generate(_ text: String, instructions: String) async throws -> String { throw CancellationError() }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct CleanedText {
    @Guide(description: "Only the edited text, in its original language. No preamble or commentary.")
    var text: String
}

/// Apple's on-device Foundation Models. The OS supplies the model, so uttr downloads
/// nothing; it needs Apple Intelligence on macOS 26 or later.
@available(macOS 26.0, *)
@MainActor
private final class AppleCleanupBackend: CleanupGenerating {
    var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// Short text with names is often misread (an English sentence scored as Indonesian),
    /// so any reasonably likely supported language is enough.
    func supports(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard !hypotheses.isEmpty else { return true }
        return hypotheses.contains { language, probability in
            probability >= 0.2 && SystemLanguageModel.default.supportsLocale(Locale(identifier: language.rawValue))
        }
    }

    func generate(_ text: String, instructions: String) async throws -> String {
        // A fresh session per request: nothing from an earlier cleanup carries over,
        // and only the text itself is sent.
        let session = LanguageModelSession(instructions: "\(instructions)\n\n\(CleanupPrompt.framing)")
        let response = try await session.respond(to: text, generating: CleanedText.self,
                                                options: GenerationOptions(temperature: 0, maximumResponseTokens: 1800))
        return response.content.text
    }
}
#endif
