import Foundation
import SwiftUI

/// What produced a history entry.
enum HistoryEntryKind: String, Codable {
    /// Speech transcribed with the recording shortcut.
    case dictation
    /// Text cleaned by the cleanup shortcut, or dictation cleaned after transcription.
    case cleanup
    /// Selected text read aloud.
    case speech
}

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let audioFileName: String?
    let kind: HistoryEntryKind

    init(text: String, kind: HistoryEntryKind = .dictation, audioFileName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.audioFileName = audioFileName
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, audioFileName, kind
    }

    /// Entries saved before `kind` existed were all dictation.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        kind = try container.decodeIfPresent(HistoryEntryKind.self, forKey: .kind) ?? .dictation
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var shortText: String {
        if text.count > 50 {
            return String(text.prefix(50)) + "..."
        }
        return text
    }
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    // MARK: - Published Properties
    @Published var transcriptions: [TranscriptionEntry] = []
    
    // MARK: - Properties
    // A cleaned dictation writes two entries, so keep room for five of those.
    private let maxEntries = 10
    private let historyFileURL: URL
    private let logger = Logger()
    
    // MARK: - Initialization
    init() {
        // Set up history file URL
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let historyDir = documentsDir.appendingPathComponent("History")
        historyFileURL = historyDir.appendingPathComponent("transcription_history.json")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        
        loadHistory()
    }
    
    // MARK: - Public Methods
    func addTranscription(_ text: String, audioFileName: String? = nil) {
        add(text, kind: .dictation, audioFileName: audioFileName)
    }

    func add(_ text: String, kind: HistoryEntryKind, audioFileName: String? = nil) {
        let entry = TranscriptionEntry(text: text, kind: kind, audioFileName: audioFileName)
        
        DispatchQueue.main.async {
            // Add to beginning of array
            self.transcriptions.insert(entry, at: 0)
            
            // Keep only the last N entries
            if self.transcriptions.count > self.maxEntries {
                self.transcriptions = Array(self.transcriptions.prefix(self.maxEntries))
            }
            
            self.saveHistory()
        }
        
        logger.log("Added \(kind.rawValue) to history: \(text.prefix(30))...", level: .info)
    }
    
    func copyToClipboard(_ entry: TranscriptionEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        
        logger.log("Copied transcription to clipboard: \(entry.id)", level: .info)
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.transcriptions.removeAll()
            self.saveHistory()
        }
        
        logger.log("Cleared transcription history", level: .info)
    }
    
    func getRecentTranscriptions(limit: Int = 5) -> [TranscriptionEntry] {
        return Array(transcriptions.prefix(limit))
    }
    
    // MARK: - Private Methods
    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            logger.log("No history file found, starting with empty history", level: .debug)
            return
        }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let loadedTranscriptions = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
            
            DispatchQueue.main.async {
                self.transcriptions = Array(loadedTranscriptions.prefix(self.maxEntries))
            }
            
            logger.log("Loaded \(loadedTranscriptions.count) transcriptions from history", level: .info)
        } catch {
            logger.logError(error, context: "Failed to load transcription history")
        }
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(transcriptions)
            try data.write(to: historyFileURL)
            logger.log("Saved transcription history with \(transcriptions.count) entries", level: .debug)
        } catch {
            logger.logError(error, context: "Failed to save transcription history")
        }
    }
}