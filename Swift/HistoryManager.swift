import Foundation
import SwiftUI

/// What produced a history entry.
enum HistoryEntryKind: String, Codable {
    case dictation

    var title: String {
        switch self {
        case .dictation: return "Dictation"
        }
    }
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

    /// Entries saved before `kind` existed were all dictation. An unknown kind, written
    /// by a newer version, also loads as dictation rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        kind = (try? container.decodeIfPresent(HistoryEntryKind.self, forKey: .kind)) ?? .dictation
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
    private let maxEntries = 5
    private let historyFileURL: URL
    /// Where AudioRecorder writes recordings. An entry's recording is deleted when
    /// the entry leaves history.
    private let recordingsDirectory: URL
    private let logger = Logger()
    
    // MARK: - Initialization
    init(historyFileURL: URL? = nil, recordingsDirectory: URL = FileManager.default.temporaryDirectory) {
        // Set up history file URL
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.historyFileURL = historyFileURL
            ?? documentsDir.appendingPathComponent("History").appendingPathComponent("transcription_history.json")
        self.recordingsDirectory = recordingsDirectory
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: self.historyFileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        
        loadHistory()
    }
    
    // MARK: - Public Methods
    func addTranscription(_ text: String, audioFileName: String? = nil) {
        let entry = TranscriptionEntry(text: text, audioFileName: audioFileName)
        
        DispatchQueue.main.async {
            // Add to beginning of array
            self.transcriptions.insert(entry, at: 0)
            
            // Keep only the last N entries
            if self.transcriptions.count > self.maxEntries {
                self.deleteRecordings(of: self.transcriptions[self.maxEntries...])
                self.transcriptions = Array(self.transcriptions.prefix(self.maxEntries))
            }
            
            self.saveHistory()
        }
        
        logger.log("Added transcription to history: \(text.prefix(30))...", level: .info)
    }
    
    func copyToClipboard(_ entry: TranscriptionEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        
        logger.log("Copied transcription to clipboard: \(entry.id)", level: .info)
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.deleteRecordings(of: self.transcriptions)
            self.transcriptions.removeAll()
            self.saveHistory()
        }
        
        logger.log("Cleared transcription history", level: .info)
    }
    
    func getRecentTranscriptions(limit: Int = 5) -> [TranscriptionEntry] {
        return Array(transcriptions.prefix(limit))
    }
    
    // MARK: - Private Methods
    private func deleteRecordings<S: Sequence>(of entries: S) where S.Element == TranscriptionEntry {
        for name in entries.compactMap(\.audioFileName) {
            // Only a bare file name, so an edited history file can't point elsewhere.
            guard !name.isEmpty, URL(fileURLWithPath: name).lastPathComponent == name else { continue }
            let url = recordingsDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                logger.log("Deleted recording \(name)", level: .debug)
            } catch {
                logger.logError(error, context: "Failed to delete recording \(name)")
            }
        }
    }

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