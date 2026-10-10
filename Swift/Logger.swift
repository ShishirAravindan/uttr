import Foundation
import Darwin

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

final class Logger {
    private let componentName: String?
    private let writer: LogWriter

    init(componentName: String? = nil, writer: LogWriter = .shared) {
        self.componentName = componentName
        self.writer = writer
    }

    func log(_ message: String, level: LogLevel = .info) {
        writer.log(message, level: level, componentName: componentName)
    }

    func logTranscription(_ text: String, audioFile: String) {
        log("Transcription completed - Audio: \(audioFile), Text: \"\(text)\"")
    }

    func logError(_ error: Error, context: String = "") {
        log("\(context.isEmpty ? "" : "\(context): ")\(error.localizedDescription)", level: .error)
    }
}

/// Component loggers share one handle and formatter, protected by one lock.
final class LogWriter {
    static let shared: LogWriter = {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "uttr"
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Logs").appendingPathComponent(appName)
        return LogWriter(fileURL: (directory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("transcriptions.log"))
    }()

    private let fileURL: URL
    private let lock = NSLock()
    private let formatter = DateFormatter()
    private var handle: FileHandle?

    init(fileURL: URL) {
        self.fileURL = fileURL
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func log(_ message: String, level: LogLevel, componentName: String?) {
        lock.lock()
        defer { lock.unlock() }
        let prefix = componentName.map { "[\($0)] " } ?? ""
        let entry = "[\(formatter.string(from: Date()))] [\(level.rawValue)] \(prefix)\(message)\n"
        do {
            if handle == nil {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let descriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            }
            try handle?.write(contentsOf: Data(entry.utf8))
        } catch {
            print("Failed to write log file: \(error)")
        }
        print(entry.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
