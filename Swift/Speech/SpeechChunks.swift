import NaturalLanguage

enum SpeechChunks {
    /// Sentences, with long ones split at word boundaries, so synthesis can start on
    /// the first sentence and stay under Kokoro's 510-phoneme input limit.
    static func split(_ text: String, maxCharacters: Int = 300) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }

        var chunks: [String] = []
        for sentence in sentences {
            var current = ""
            for word in sentence.split(whereSeparator: \.isWhitespace) {
                if !current.isEmpty, current.count + word.count + 1 > maxCharacters {
                    chunks.append(current)
                    current = ""
                }
                current += current.isEmpty ? String(word) : " " + String(word)
            }
            if !current.isEmpty { chunks.append(current) }
        }
        return chunks
    }
}
