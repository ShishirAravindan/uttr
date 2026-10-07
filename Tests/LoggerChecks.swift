import Foundation

@main
struct LoggerChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("test.log")
        let writer = LogWriter(fileURL: file)
        let first = Logger(componentName: "Capture", writer: writer)
        let second = Logger(componentName: "Delivery", writer: writer)
        first.log("first", level: .debug)
        second.log("second", level: .warning)
        first.log("third", level: .error)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        precondition(lines.count == 3)
        precondition(lines[0].hasSuffix("[DEBUG] [Capture] first"))
        precondition(lines[1].hasSuffix("[WARNING] [Delivery] second"))
        precondition(lines[2].hasSuffix("[ERROR] [Capture] third"))

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            Logger(componentName: "Worker", writer: writer).log("entry-\(index)-🗣️")
        }
        let output = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        precondition(output.count == 203)
        for index in 0..<200 {
            precondition(output.filter { $0.hasSuffix("[Worker] entry-\(index)-🗣️") }.count == 1)
        }

        let blocked = directory.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocked)
        let recoverableFile = blocked.appendingPathComponent("test.log")
        let recoverable = Logger(writer: LogWriter(fileURL: recoverableFile))
        recoverable.log("cannot write yet")
        precondition(!FileManager.default.fileExists(atPath: recoverableFile.path))
        try FileManager.default.removeItem(at: blocked)
        recoverable.log("recovered")
        let recovered = try String(contentsOf: recoverableFile, encoding: .utf8)
        precondition(recovered.hasSuffix("[INFO] recovered\n"))
        print("3 logging checks passed")
    }
}
