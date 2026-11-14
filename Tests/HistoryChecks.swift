import Foundation

@main
struct HistoryChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recordings = directory.appendingPathComponent("recordings")
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = Logger(writer: LogWriter(fileURL: directory.appendingPathComponent("test.log")))

        try checkDecoding()
        try checkLimits(directory: directory, recordings: recordings, logger: logger)
        print("History checks passed")
    }

    static func checkDecoding() throws {
        let legacy = """
            [{"id":"\(UUID().uuidString)","text":"old","timestamp":700000000,"audioFileName":"recording_1.wav"},
             {"id":"\(UUID().uuidString)","text":"newer","timestamp":700000001,"kind":"read_aloud"}]
            """
        let decoded = try JSONDecoder().decode([TranscriptionEntry].self, from: Data(legacy.utf8))
        precondition(decoded.map(\.kind) == [.dictation, .dictation])
        precondition(decoded[0].audioFileName == "recording_1.wav")
        precondition(decoded[1].audioFileName == nil)

        let entry = TranscriptionEntry(text: "round trip", kind: .dictation, audioFileName: "recording_2.wav")
        let data = try JSONEncoder().encode([entry])
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        precondition(json[0]["kind"] as? String == "dictation")
        let reloaded = try JSONDecoder().decode([TranscriptionEntry].self, from: data)[0]
        precondition(reloaded.id == entry.id && reloaded.text == entry.text)
        precondition(reloaded.kind == entry.kind && reloaded.audioFileName == entry.audioFileName)
        precondition(reloaded.timestamp == entry.timestamp)
    }

    static func checkLimits(directory: URL, recordings: URL, logger: Logger) throws {
        let historyFile = directory.appendingPathComponent("history.json")
        let history = HistoryManager(historyFileURL: historyFile, recordingsDirectory: recordings, logger: logger)
        drain()
        precondition(history.transcriptions.isEmpty)

        for index in 1...4 {
            try makeRecording("recording_\(index).wav", in: recordings)
            history.addTranscription("entry \(index)", audioFileName: "recording_\(index).wav")
        }
        drain()
        precondition(history.transcriptions.map(\.text) == ["entry 4", "entry 3", "entry 2", "entry 1"])

        history.setMaxEntries(2)
        drain()
        precondition(history.transcriptions.map(\.text) == ["entry 4", "entry 3"])
        precondition(recordingNames(in: recordings) == ["recording_3.wav", "recording_4.wav"])
        let saved = try savedTexts(historyFile)
        precondition(saved == ["entry 4", "entry 3"])

        history.setMaxEntries(3)
        try makeRecording("recording_5.wav", in: recordings)
        history.addTranscription("entry 5", audioFileName: "recording_5.wav")
        drain()
        precondition(history.transcriptions.map(\.text) == ["entry 5", "entry 4", "entry 3"])
        precondition(recordingNames(in: recordings) == ["recording_3.wav", "recording_4.wav", "recording_5.wav"])

        try makeRecording("recording_6.wav", in: recordings)
        history.addTranscription("entry 6", audioFileName: "recording_6.wav")
        drain()
        precondition(history.transcriptions.map(\.text) == ["entry 6", "entry 5", "entry 4"])
        precondition(recordingNames(in: recordings) == ["recording_4.wav", "recording_5.wav", "recording_6.wav"])

        // A reload keeps every saved entry until the configured limit arrives.
        let reloaded = HistoryManager(historyFileURL: historyFile, recordingsDirectory: recordings, logger: logger)
        drain()
        precondition(reloaded.transcriptions.count == 3)
        reloaded.setMaxEntries(0)
        drain()
        precondition(reloaded.transcriptions.map(\.text) == ["entry 6"])
        precondition(recordingNames(in: recordings) == ["recording_6.wav"])

        // A name that points outside the recordings folder is never deleted.
        let outside = directory.appendingPathComponent("outside.wav")
        try Data("keep".utf8).write(to: outside)
        reloaded.addTranscription("escape", audioFileName: "../outside.wav")
        drain()
        reloaded.clearHistory()
        drain()
        precondition(reloaded.transcriptions.isEmpty)
        precondition(recordingNames(in: recordings).isEmpty)
        precondition(FileManager.default.fileExists(atPath: outside.path))
        let cleared = try savedTexts(historyFile)
        precondition(cleared.isEmpty)
    }

    static func drain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    static func makeRecording(_ name: String, in directory: URL) throws {
        try Data("wav".utf8).write(to: directory.appendingPathComponent(name))
    }

    static func recordingNames(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    static func savedTexts(_ file: URL) throws -> [String] {
        try JSONDecoder().decode([TranscriptionEntry].self, from: Data(contentsOf: file)).map(\.text)
    }
}
