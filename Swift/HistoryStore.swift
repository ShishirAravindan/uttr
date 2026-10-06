import CryptoKit
import Darwin
import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let audioFileName: String?

    init(text: String, audioFileName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.audioFileName = audioFileName
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

/// Disk transactions are locked across app instances; migration and writes are atomic.
final class HistoryStore {
    private let paths: AppPaths
    private let fileManager = FileManager.default
    private let maxEntries = 5
    private let report: (Error) -> Void

    init(paths: AppPaths = AppPaths(), report: @escaping (Error) -> Void = { _ in }) {
        self.paths = paths
        self.report = report
    }

    func load() throws -> [TranscriptionEntry] {
        try transaction { try loadAndMigrate() }
    }

    func add(_ entry: TranscriptionEntry) throws -> [TranscriptionEntry] {
        try transaction {
            let entries = Array(([entry] + (try loadAndMigrate())).prefix(maxEntries))
            try write(entries)
            return entries
        }
    }

    func clear() throws {
        try transaction {
            // Validate existing files before replacing them, including on failed migration.
            _ = try loadAndMigrate()
            try write([])
        }
    }

    private func loadAndMigrate() throws -> [TranscriptionEntry] {
        let current = try read(paths.history)
        let legacy: [TranscriptionEntry]
        let fingerprint: Data
        do {
            guard let data = try readData(paths.legacyHistory) else { return Array((current ?? []).prefix(maxEntries)) }
            legacy = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
            fingerprint = Data(SHA256.hash(data: data))
        } catch {
            guard let current else { throw error }
            // A broken legacy file must not disable an already valid destination.
            report(error)
            return Array(current.prefix(maxEntries))
        }
        let receipt = paths.history.deletingLastPathComponent().appendingPathComponent(".legacy-migration")
        if let current, (try? Data(contentsOf: receipt)) == fingerprint {
            return Array(current.prefix(maxEntries))
        }
        var seen = Set<UUID>()
        let merged = (current ?? []).filter { seen.insert($0.id).inserted }
            + legacy.filter { seen.insert($0.id).inserted }
        let entries = Array(merged.sorted { $0.timestamp > $1.timestamp }.prefix(maxEntries))
        try write(entries)
        // A receipt prevents re-import after clear if the old file cannot be removed.
        // It stores a fingerprint only, never a second copy of transcript contents.
        try fingerprint.write(to: receipt, options: .atomic)
        // Delete only the known history file after the destination was safely written.
        // rmdir removes an empty directory atomically, never its unrelated contents.
        do {
            // Older versions do not take this lock. Preserve a source changed since our snapshot.
            if let data = try readData(paths.legacyHistory), Data(SHA256.hash(data: data)) == fingerprint {
                try fileManager.removeItem(at: paths.legacyHistory)
            }
        } catch { report(error) }
        _ = paths.legacyHistory.deletingLastPathComponent().path.withCString { Darwin.rmdir($0) }
        return entries
    }

    private func read(_ url: URL) throws -> [TranscriptionEntry]? {
        guard let data = try readData(url) else { return nil }
        return try JSONDecoder().decode([TranscriptionEntry].self, from: data)
    }

    private func readData(_ url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return try Data(contentsOf: url)
    }

    private func write(_ entries: [TranscriptionEntry]) throws {
        try fileManager.createDirectory(at: paths.history.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: paths.history, options: .atomic)
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: paths.applicationSupport, withIntermediateDirectories: true)
        let lockURL = paths.applicationSupport.appendingPathComponent(".history.lock")
        let descriptor = lockURL.path.withCString { Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC, 0o600) }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
