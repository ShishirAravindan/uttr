/// Provides expressive model synthesis and chunking to the shared PCM player.
@MainActor
enum MLXSpeechSource {
    static func makeEngine(model: ExpressiveSpeechModel, host: TTSModelHost) -> BufferedSpeechEngine {
        BufferedSpeechEngine(chunks: chunks, synthesize: { chunk in
            try await host.synthesize(chunk, with: model)
        })
    }

    /// Start on one sentence so the first audio arrives earlier, then keep a
    /// little more context in each chunk for expressive delivery.
    private static func chunks(from text: String) -> [String] {
        let sentences = SpeechChunks.split(text, maxCharacters: 400)
        guard let first = sentences.first else { return [] }
        var chunks = [first]
        var group: [String] = []
        var length = 0
        for sentence in sentences.dropFirst() {
            if !group.isEmpty, group.count == 3 || length + 1 + sentence.count > 240 {
                chunks.append(group.joined(separator: " "))
                group.removeAll(keepingCapacity: true)
                length = 0
            }
            length += group.isEmpty ? sentence.count : sentence.count + 1
            group.append(sentence)
        }
        if !group.isEmpty { chunks.append(group.joined(separator: " ")) }
        return chunks
    }
}
