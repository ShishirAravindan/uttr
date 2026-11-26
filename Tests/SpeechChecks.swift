import Foundation

/// Sentence chunking and voice switching, with fake voices. Plays no audio and
/// never reads the selection.
@main
struct SpeechChecks {
    @MainActor
    static func main() async {
        checkChunks()
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

    static let logger = Logger(writer: LogWriter(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("uttr-speech-checks-\(UUID().uuidString).log")))

    @MainActor
    static func checkVoiceSwitching() async {
        // Not speaking: the new voice takes over at once.
        let system = FakeVoice()
        let readAloud = ReadAloud(engine: system, logger: logger)
        var finished = 0
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
        stopping.speak("first") { _ in finished += 1 }
        stopping.useEngine(second)
        await settle()
        precondition(first.teardowns == 0 && first.stops == 0, "speech in progress keeps its voice")
        stopping.stop()
        await settle()
        precondition(first.stops == 1 && first.teardowns == 1)
        precondition(finished == 0)
        precondition(!stopping.isSpeaking)
        second.speaking = true
        precondition(stopping.isSpeaking)

        // Speaking: or until it finishes on its own.
        let third = FakeVoice()
        let fourth = FakeVoice()
        let finishing = ReadAloud(engine: third, logger: logger)
        finishing.speak("third") { _ in finished += 1 }
        finishing.useEngine(fourth)
        third.speaking = false
        third.completion?(.finished)
        precondition(finished == 1)
        await settle()
        precondition(third.teardowns == 1 && third.stops == 0)
        fourth.speaking = true
        precondition(finishing.isSpeaking)

        // Teardown also releases a voice still waiting to take over.
        let fifth = FakeVoice()
        let sixth = FakeVoice()
        let quitting = ReadAloud(engine: fifth, logger: logger)
        quitting.speak("fifth") { _ in preconditionFailure("quit must invalidate completion") }
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
    var completion: ((SpeechCompletion) -> Void)?
    var isSpeaking: Bool { speaking }
    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void) {
        speaking = true
        self.completion = completion
    }
    func stop() { speaking = false; stops += 1 }
    func teardown() async { teardowns += 1 }
}
