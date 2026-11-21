import NaturalLanguage

enum SpeechChunks {
    /// Sentences, with long ones split at clause and then word boundaries, so synthesis
    /// can start on the first sentence and stay under Kokoro's 510-phoneme input limit.
    static func split(_ text: String, maxCharacters: Int = 300) -> [String] {
        sentences(text).flatMap { wrap($0, maxCharacters: maxCharacters) }
    }

    /// Chunks for speech-LLM voices, which infer tone from the surrounding words and
    /// punctuation and work best on one to three sentences at a time.
    ///
    /// The first chunk is a single sentence, so the first audio arrives quickly. Later
    /// chunks join up to `maxSentences` sentences while they stay within
    /// `targetCharacters`. A sentence longer than `maxCharacters` is split at clause
    /// punctuation, then at words. Punctuation is always kept with its words.
    static func groups(
        _ text: String,
        targetCharacters: Int = 240,
        maxSentences: Int = 3,
        maxCharacters: Int = 400
    ) -> [String] {
        let pieces = sentences(text).flatMap { wrap($0, maxCharacters: maxCharacters) }
        var chunks: [String] = []
        var current = ""
        var count = 0
        for piece in pieces {
            let isFirstChunk = chunks.isEmpty
            let joined = current.isEmpty ? piece : current + " " + piece
            if !current.isEmpty, isFirstChunk || count >= maxSentences || joined.count > targetCharacters {
                chunks.append(current)
                current = piece
                count = 1
            } else {
                current = joined
                count += 1
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Sentences with runs of whitespace, including line breaks, collapsed to one space.
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let words = text[range].split(whereSeparator: \.isWhitespace)
            if !words.isEmpty { sentences.append(words.joined(separator: " ")) }
            return true
        }
        return sentences
    }

    /// Splits a sentence longer than `maxCharacters` after clause punctuation where it
    /// can, and between words where it can't. A single word longer than the limit is
    /// kept whole.
    static func wrap(_ sentence: String, maxCharacters: Int) -> [String] {
        guard sentence.count > maxCharacters else { return [sentence] }
        let words = sentence.split(separator: " ").map(String.init)
        var clauses: [[String]] = [[]]
        for word in words {
            clauses[clauses.count - 1].append(word)
            if let last = word.last, clauseEnds.contains(last) { clauses.append([]) }
        }
        clauses.removeAll { $0.isEmpty }

        var chunks: [String] = []
        var current = ""
        func add(_ piece: String) {
            if !current.isEmpty, current.count + piece.count + 1 > maxCharacters {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? piece : " " + piece
        }
        for clause in clauses {
            let text = clause.joined(separator: " ")
            if text.count <= maxCharacters {
                add(text)
            } else {
                clause.forEach(add)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static let clauseEnds: Set<Character> = [",", ";", ":", "—", "–"]
}
