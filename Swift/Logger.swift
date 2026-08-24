import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

class Logger {

    // MARK: - Properties
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?
    private let componentName: String?
    
    // MARK: - Initialization
    init(componentName: String? = nil) {
        self.componentName = componentName

        // Use proper macOS logs directory: ~/Library/Logs/<AppName>/
        let logsDir = AppPaths.logsDirectory
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("transcriptions.log")

        // Set up date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Every component (AudioRecorder, AudioDeviceManager, ...) creates its
        // own Logger onto this same file. A plain FileHandle caches its write
        // offset from a single seekToEndOfFile() at construction, so concurrent
        // writers race and clobber each other's lines. Opening with O_APPEND
        // makes the kernel atomically seek to EOF on every write(2), so
        // interleaved writers never overlap regardless of when each was opened.
        let fd = open(logFileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if fd != -1 {
            fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        } else {
            print("Failed to open log file: \(String(cString: strerror(errno)))")
            fileHandle = nil
        }
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    // MARK: - Public Methods
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = dateFormatter.string(from: Date())
        let prefix = componentName != nil ? "[\(componentName!)] " : ""
        let logEntry = "[\(timestamp)] [\(level.rawValue)] \(prefix)\(message)\n"
        
        // No fsync: O_APPEND already orders the write, and page-cached data
        // survives an app crash. Syncing every line only buys durability
        // against a kernel panic, at the cost of a disk round-trip per line.
        if let data = logEntry.data(using: .utf8) {
            fileHandle?.write(data)
        }
        
        // Also print to console for debugging
        print(logEntry.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    func logTranscription(_ text: String, audioFile: String) {
        let message = "Transcription completed - Audio: \(audioFile), Text: \"\(text)\""
        log(message, level: .info)
    }
    
    func logError(_ error: Error, context: String = "") {
        let message = "\(context.isEmpty ? "" : "\(context): ")\(error.localizedDescription)"
        log(message, level: .error)
    }
    
    // MARK: - Utility Methods
    func getLogContents() -> String? {
        do {
            return try String(contentsOf: logFileURL, encoding: .utf8)
        } catch {
            print("Failed to read log file: \(error)")
            return nil
        }
    }
    
    func clearLogs() {
        do {
            try "".write(to: logFileURL, atomically: true, encoding: .utf8)
            fileHandle?.seekToEndOfFile()
        } catch {
            print("Failed to clear log file: \(error)")
        }
    }
    
    func rotateLogs() {
        // Simple log rotation - keep only last 1000 lines
        guard let contents = getLogContents() else { return }
        
        let lines = contents.components(separatedBy: .newlines)
        if lines.count > 1000 {
            let recentLines = Array(lines.suffix(1000))
            let newContents = recentLines.joined(separator: "\n")
            
            do {
                try newContents.write(to: logFileURL, atomically: true, encoding: .utf8)
                fileHandle?.seekToEndOfFile()
            } catch {
                print("Failed to rotate log file: \(error)")
            }
        }
    }
} 