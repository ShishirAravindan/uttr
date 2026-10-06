import AppKit
import Combine
import Foundation

@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    @Published private(set) var transcriptions: [TranscriptionEntry] = []
    private let store: HistoryStore
    private let logger: Logger

    init() {
        let logger = Logger()
        self.logger = logger
        store = HistoryStore(report: { logger.logError($0, context: "Failed to migrate legacy history; legacy file preserved") })
        do { transcriptions = try store.load() }
        catch { logger.logError(error, context: "Failed to load transcription history; existing files preserved") }
    }

    func addTranscription(_ text: String, audioFileName: String? = nil, rawText: String? = nil) {
        let entry = TranscriptionEntry(text: text, audioFileName: audioFileName, rawText: rawText)
        do { transcriptions = try store.add(entry) }
        catch {
            transcriptions = Array(([entry] + transcriptions).prefix(5))
            logger.logError(error, context: "Failed to save transcription history; existing files preserved")
        }
    }

    func copyToClipboard(_ entry: TranscriptionEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        logger.log("Copied transcription to clipboard: \(entry.id)", level: .info)
    }

    func clearHistory() {
        do {
            try store.clear()
            transcriptions.removeAll()
        } catch { logger.logError(error, context: "Failed to clear transcription history; existing files preserved") }
    }

    func getRecentTranscriptions(limit: Int = 5) -> [TranscriptionEntry] {
        Array(transcriptions.prefix(limit))
    }
}
