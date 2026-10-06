import Foundation
import Darwin

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

final class Logger {
    private let sink: LogSink
    private let componentName: String?

    // The injected path keeps tests away from the user's log directory.
    init(componentName: String? = nil, logFileURL: URL? = nil) {
        self.componentName = componentName
        sink = LogSink.shared(at: logFileURL ?? Self.defaultLogFileURL)
    }

    private static var defaultLogFileURL: URL {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "uttr"
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Logs").appendingPathComponent(appName)
        return (directory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("transcriptions.log")
    }

    func log(_ message: String, level: LogLevel = .info) {
        sink.log(message, level: level, componentName: componentName)
    }

    func logTranscription(_ text: String, audioFile: String) {
        log("Transcription completed - Audio: \(audioFile), Text: \"\(text)\"")
    }

    func logError(_ error: Error, context: String = "") {
        log("\(context.isEmpty ? "" : "\(context): ")\(error.localizedDescription)", level: .error)
    }
}

/// All components share one formatter and append handle per path. The process
/// lock protects both; flock coordinates cooperating app processes on that file.
private final class LogSink {
    private static let registryLock = NSLock()
    private static var sinks: [URL: LogSink] = [:]
    private static let retainedLines = 1000

    static func shared(at url: URL) -> LogSink {
        let path = url.standardizedFileURL.resolvingSymlinksInPath()
        registryLock.lock()
        defer { registryLock.unlock() }
        if let sink = sinks[path] { return sink }
        let sink = LogSink(url: path)
        sinks[path] = sink
        return sink
    }

    private let url: URL
    private let lock = NSLock()
    private let formatter: DateFormatter
    private var handle: FileHandle?

    private init(url: URL) {
        self.url = url
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func log(_ message: String, level: LogLevel, componentName: String?) {
        lock.lock()
        defer { lock.unlock() }
        let prefix = componentName.map { "[\($0)] " } ?? ""
        let entry = "[\(formatter.string(from: Date()))] [\(level.rawValue)] \(prefix)\(message)\n"
        do {
            let file = try openIfNeeded()
            try withFileLock(file) {
                // A previous interrupted write must not absorb the next entry.
                let end = try file.seekToEnd()
                if end > 0 {
                    try file.seek(toOffset: end - 1)
                    if try file.read(upToCount: 1)?.first != 0x0A {
                        try file.write(contentsOf: Data([0x0A]))
                    }
                }
                try file.write(contentsOf: Data(entry.utf8))
            }
        } catch {
            print("Failed to write log file: \(error)")
        }
        print(entry.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func openIfNeeded() throws -> FileHandle {
        if let handle = handle { return handle }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let descriptor = open(url.path, O_RDWR | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try withFileLock(file) { try trim(file) }
        } catch {
            try? file.close()
            throw error
        }
        handle = file
        return file
    }

    private func withFileLock<T>(_ file: FileHandle, _ body: () throws -> T) throws -> T {
        while flock(file.fileDescriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw posixError() }
        }
        defer { _ = flock(file.fileDescriptor, LOCK_UN) }
        return try body()
    }

    /// Trim once when this process opens the sink. Scan backwards in chunks so
    /// old logs do not all have to fit in memory. Keep the inode: other processes
    /// may already have an append handle open on it.
    private func trim(_ file: FileHandle) throws {
        let size = try file.seekToEnd()
        var offset = size
        var separators = 0
        while offset > 0 {
            let start = offset > 65536 ? offset - 65536 : 0
            try file.seek(toOffset: start)
            let chunk = try file.read(upToCount: Int(offset - start)) ?? Data()
            for index in chunk.indices.reversed() where chunk[index] == 0x0A {
                let position = start + UInt64(index)
                if position == size - 1 { continue } // Trailing newline is not a line.
                separators += 1
                if separators == Self.retainedLines {
                    try file.seek(toOffset: position + 1)
                    let recent = try file.readToEnd() ?? Data()
                    try file.truncate(atOffset: 0)
                    try file.write(contentsOf: recent)
                    return
                }
            }
            offset = start
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
