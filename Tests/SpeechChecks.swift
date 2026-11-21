import Foundation

/// Sentence chunking, grouping for speech-LLMs, and voice switching, with fake voices. Plays no audio and
/// never reads the selection.
@main
struct SpeechChecks {
    @MainActor
    static func main() async {
        checkChunks()
        checkGroups()
        await checkVoiceSwitching()
        print("Speech checks passed")
    }

    static func checkChunks() {
        precondition(SpeechChunks.split("") == [])
        precondition(SpeechChunks.split("  \n ") == [])
        precondition(SpeechChunks.split("One sentence. Another one! A third?") == ["One sentence.", "Another one!", "A third?"])
        precondition(SpeechChunks.split("Line one\nline two.").joined(separator: " ") == "Line one line two.")

        let long = Array(repeating: "word", count: 200).joined(separator: " ") + "."
        let chunks = SpeechChunks.split(long, maxCharacters: 50)
        precondition(chunks.count > 1)
        precondition(chunks.allSatisfy { $0.count <= 50 })
        precondition(chunks.joined(separator: " ") == long, "no words lost or reordered")

        let unbroken = String(repeating: "x", count: 80)
        precondition(SpeechChunks.split(unbroken, maxCharacters: 50) == [unbroken], "a single long word is kept whole")
    }

    static func checkGroups() {
        precondition(SpeechChunks.groups("") == [])
        let text = "Wait. Did you hear that? \"Yes,\" she whispered, \"I did.\" We ran! The door slammed. Silence."
        let groups = SpeechChunks.groups(text)
        precondition(groups.first == "Wait.", "the first chunk is one sentence, for fast first audio")
        precondition(groups.joined(separator: " ") == text, "punctuation and quotes are kept, nothing lost or reordered")
        let later = groups.dropFirst().map { SpeechChunks.sentences($0).count }
        precondition(later.allSatisfy { $0 >= 1 && $0 <= 3 }, "later chunks hold one to three sentences")
        precondition(groups.count < SpeechChunks.sentences(text).count, "short sentences are joined")

        // Sentences are kept whole while they fit the target.
        let medium = Array(repeating: "This sentence is about fifty characters in all.", count: 6).joined(separator: " ")
        for group in SpeechChunks.groups(medium, targetCharacters: 120).dropFirst() {
            precondition(group.count <= 120 && group.hasSuffix("."))
        }

        // A long sentence splits after clause punctuation before it splits words.
        let clauses = "When the storm finally broke over the valley, the villagers ran for shelter; "
            + "the old miller, who had seen worse, simply closed his shutters and waited."
        let pieces = SpeechChunks.groups(clauses, maxCharacters: 80)
        precondition(pieces.count > 1 && pieces.allSatisfy { $0.count <= 80 })
        precondition(pieces.dropLast().allSatisfy { [",", ";"].contains($0.last!) }, "splits land on clause punctuation")
        precondition(pieces.joined(separator: " ") == clauses)
    }

    static let logger = Logger(writer: LogWriter(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("uttr-speech-checks-\(UUID().uuidString).log")))

    @MainActor
    static func checkVoiceSwitching() async {
        // Not speaking: the new voice takes over at once.
        let system = FakeVoice()
        let readAloud = ReadAloud(engine: system, logger: logger)
        var idle = 0
        readAloud.onIdle = { idle += 1 }
        let kokoro = FakeVoice()
        readAloud.useEngine(kokoro)
        await settle()
        precondition(system.teardowns == 1)
        kokoro.speaking = true
        precondition(readAloud.isSpeaking)

        // Speaking: the switch waits until speech is stopped.
        let first = FakeVoice()
        let second = FakeVoice()
        let stopping = ReadAloud(engine: first, logger: logger)
        stopping.onIdle = { idle += 1 }
        first.speaking = true
        stopping.useEngine(second)
        await settle()
        precondition(first.teardowns == 0 && first.stops == 0, "speech in progress keeps its voice")
        let idleBefore = idle
        stopping.stop()
        await settle()
        precondition(first.stops == 1 && first.teardowns == 1)
        precondition(idle == idleBefore + 1)
        precondition(!stopping.isSpeaking)
        second.speaking = true
        precondition(stopping.isSpeaking)

        // Speaking: or until it finishes on its own.
        let third = FakeVoice()
        let fourth = FakeVoice()
        let finishing = ReadAloud(engine: third, logger: logger)
        finishing.onIdle = { idle += 1 }
        third.speaking = true
        finishing.useEngine(fourth)
        third.speaking = false
        third.onFinished?()
        await settle()
        precondition(third.teardowns == 1 && third.stops == 0)
        fourth.speaking = true
        precondition(finishing.isSpeaking)

        // Teardown also releases a voice still waiting to take over.
        let fifth = FakeVoice()
        let sixth = FakeVoice()
        let quitting = ReadAloud(engine: fifth, logger: logger)
        fifth.speaking = true
        quitting.useEngine(sixth)
        await quitting.teardown()
        precondition(fifth.teardowns == 1 && sixth.teardowns == 1)
    }

    @MainActor
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
final class FakeVoice: SpeechEngine {
    var speaking = false
    var stops = 0
    var teardowns = 0
    var onFinished: (() -> Void)?
    var isSpeaking: Bool { speaking }
    func speak(_ text: String) { speaking = true }
    func stop() { speaking = false; stops += 1 }
    func teardown() async { teardowns += 1 }
}
