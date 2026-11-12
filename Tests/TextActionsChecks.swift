import Foundation

@main
struct TextActionsChecks {
    static func main() throws {
        // Selection rules
        precondition(SelectionReader.isSelectedText("hello"))
        precondition(SelectionReader.isSelectedText("first line\nsecond line\n"))
        precondition(SelectionReader.isSelectedText("first line\r\nsecond line"))
        precondition(!SelectionReader.isSelectedText(""))
        precondition(!SelectionReader.isSelectedText("\n"))
        precondition(!SelectionReader.isSelectedText("  \t\n"))
        precondition(!SelectionReader.isSelectedText("let x = 1\n"), "editor line copy")
        precondition(!SelectionReader.isSelectedText("let x = 1\r\n"), "editor line copy with CRLF")

        // History saved before entries had a kind decodes as dictation.
        let legacy = """
            [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"hello","timestamp":700000000}]
            """
        let decoded = try JSONDecoder().decode([TranscriptionEntry].self, from: Data(legacy.utf8))
        precondition(decoded.count == 1 && decoded[0].kind == .dictation && decoded[0].audioFileName == nil)

        let entries = [
            TranscriptionEntry(text: "um so hello", kind: .dictation, audioFileName: "a.wav"),
            TranscriptionEntry(text: "So, hello.", kind: .cleanup),
            TranscriptionEntry(text: "Read this.", kind: .speech),
        ]
        let roundTrip = try JSONDecoder().decode([TranscriptionEntry].self, from: JSONEncoder().encode(entries))
        precondition(roundTrip.map(\.kind) == [.dictation, .cleanup, .speech])
        precondition(roundTrip.map(\.text) == entries.map(\.text))
        precondition(roundTrip[0].audioFileName == "a.wav")

        print("TextActionsChecks passed")
    }
}
