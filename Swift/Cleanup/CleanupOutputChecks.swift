import Foundation

/// Conservative rejections of edits seen to go wrong in evaluation. They catch lost
/// content, not changed meaning, so they're not a semantic verifier.
struct CleanupChecks: OptionSet {
    let rawValue: Int

    /// Holds whatever the prompt asks: no runaway length, questions stay questions, and
    /// no lost numbers, negations, writing scripts, or technical literals.
    static let general = CleanupChecks(rawValue: 1 << 0)
    /// For transcribed speech: a spoken correction keeps its later alternative, and
    /// hedges and deliberate emphasis survive.
    static let speech = CleanupChecks(rawValue: 1 << 1)

    func accepts(_ output: String, for input: String) -> Bool {
        if contains(.general), !Self.passesGeneral(output, for: input) { return false }
        if contains(.speech), !Self.passesSpeech(output, for: input) { return false }
        return true
    }

    private static let scripts = ["Devanagari", "Tamil", "Bengali", "Arabic", "Hebrew", "Han", "Hiragana",
                                  "Katakana", "Hangul", "Cyrillic", "Greek", "Thai"]
    private static let negation = #"\b(?:not|never|cannot|without|don't|doesn't|can't|won't|isn't|aren't|wasn't|weren't|shouldn't|wouldn't|couldn't|mustn't)\b"#
    private static let number = #"\d+(?:[.,]\d+)*"#
    private static let literal = #"https?://[^\s]+|(?:~?/)[^\s,;]+|\b\w+_\w+\b|\b[a-z]+[A-Z]\w*\b|\b\d+\.\d+(?:\.\d+)*\b"#
    private static let correction = #"\bno[\s,–—-]+([\p{L}\p{N}_]+)"#
    private static let emphasis = ["very very", "really really", "so so", "never never"]
    private static let hedge = #"\b(?:maybe|might|perhaps|probably|possibly)\b"#

    private static func passesGeneral(_ output: String, for input: String) -> Bool {
        guard !output.isEmpty, output.count <= max(80, input.count * 2) else { return false }
        // A lost question mark usually means the model answered or rewrote the question.
        if input.contains("?"), !output.contains("?") { return false }
        // A numeric edit is too costly to guess at, even a spoken "15 no 50".
        guard matches(number, in: input).sorted() == matches(number, in: output).sorted() else { return false }
        guard negations(in: input) == negations(in: output) else { return false }
        // Never erase a script present in the original, including mixed-language text.
        for script in scripts {
            let pattern = "\\p{script=\(script)}"
            if input.range(of: pattern, options: .regularExpression) != nil,
               output.range(of: pattern, options: .regularExpression) == nil { return false }
        }
        for literal in matches(literal, in: input) {
            if !output.contains(literal.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))) { return false }
        }
        return true
    }

    private static func passesSpeech(_ output: String, for input: String) -> Bool {
        guard matches(hedge, in: input.lowercased()).count <= matches(hedge, in: output.lowercased()).count else {
            return false
        }
        for phrase in emphasis where input.localizedCaseInsensitiveContains(phrase) {
            if !output.localizedCaseInsensitiveContains(phrase) { return false }
        }
        // The model can reverse a correction even with examples in its prompt.
        for alternative in matches(correction, in: input, group: 1) {
            let token = NSRegularExpression.escapedPattern(for: alternative)
            if output.range(of: "\\b\(token)\\b", options: [.regularExpression, .caseInsensitive]) == nil {
                return false
            }
        }
        return true
    }

    /// "do not" and "don't" are the same negation; "never" and "without" stay distinct.
    private static func negations(in text: String) -> [String] {
        matches(negation, in: text.lowercased().replacingOccurrences(of: "’", with: "'"))
            .map { $0 == "never" || $0 == "without" ? $0 : "not" }
            .sorted()
    }

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: group > 0 ? .caseInsensitive : []) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: group), in: text).map { String(text[$0]) }
        }
    }
}
