import XCTest
import Foundation
import Darwin

final class LoggerReliabilityTests: XCTestCase {
    private var directory: URL!
    private var logURL: URL { directory.appendingPathComponent("transcriptions.log") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uttr-logger-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testComponentsOpenedBeforeWritingDoNotOverwriteEachOther() throws {
        let first = Logger(componentName: "Capture", logFileURL: logURL)
        let second = Logger(componentName: "Delivery", logFileURL: logURL)
        first.log("first", level: .debug)
        second.log("second", level: .warning)
        first.log("third", level: .error)
        let lines = try contents().split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("[DEBUG] [Capture] first"))
        XCTAssertTrue(lines[1].hasSuffix("[WARNING] [Delivery] second"))
        XCTAssertTrue(lines[2].hasSuffix("[ERROR] [Capture] third"))
    }

    func testConcurrentConstructionAndWritesKeepEveryCompleteEntry() throws {
        let path = logURL
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            let logger = Logger(componentName: "Worker\(index)", logFileURL: path)
            logger.log("entry-\(index)-🗣️")
        }
        let lines = try contents().split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 200)
        XCTAssertEqual(Set(lines).count, 200)
        for index in 0..<200 {
            XCTAssertEqual(lines.filter { $0.hasSuffix("[Worker\(index)] entry-\(index)-🗣️") }.count, 1)
        }
        XCTAssertTrue(lines.allSatisfy {
            $0.range(of: #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] "#,
                     options: .regularExpression) != nil
        })
    }

    func testStartupKeepsExactlyLastThousandTerminatedLines() throws {
        try seed(lines: 1005, trailingNewline: true)
        Logger(logFileURL: logURL).log("new")
        let lines = try contents().split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(lines.dropLast()), (5..<1005).map { "old-\($0)" })
        XCTAssertTrue(lines.last?.hasSuffix("[INFO] new") == true)
    }

    func testUnterminatedTailIsRetainedAndSeparatedFromNextEntry() throws {
        try seed(lines: 1005, trailingNewline: false)
        Logger(logFileURL: logURL).log("new")
        let lines = try contents().split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(lines.dropLast()), (5..<1005).map { "old-\($0)" })
        XCTAssertTrue(lines.last?.hasSuffix("[INFO] new") == true)
    }

    func testExactlyThousandLinesAreNotTrimmedAgainDuringSession() throws {
        try seed(lines: 1000, trailingNewline: true)
        let logger = Logger(logFileURL: logURL)
        logger.log("one")
        Logger(logFileURL: logURL).log("two")
        let lines = try contents().split(separator: "\n")
        XCTAssertEqual(lines.count, 1002)
        XCTAssertEqual(lines.first, "old-0")
    }

    func testRetentionAcrossReadChunksPreservesUnicodeAndBlankLines() throws {
        let lines = (0..<1200).map { index in
            index % 20 == 0 ? "" : "old-\(index)-" + String(repeating: "🗣️", count: 30)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        Logger(logFileURL: logURL).log("new")
        let output = try contents().components(separatedBy: "\n")
        XCTAssertEqual(Array(output.prefix(1000)), Array(lines.suffix(1000)))
        XCTAssertTrue(output[1000].hasSuffix("[INFO] new"))
        XCTAssertEqual(output.last, "")
    }

    func testFailedOpenCanRecoverWithoutCreatingNewLogger() throws {
        let blockedDirectory = directory.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blockedDirectory)
        let path = blockedDirectory.appendingPathComponent("transcriptions.log")
        let logger = Logger(logFileURL: path)
        logger.log("cannot write yet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        try FileManager.default.removeItem(at: blockedDirectory)
        logger.log("recovered")
        let output = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(output.hasSuffix("[INFO] recovered\n"))
        XCTAssertFalse(output.contains("cannot write yet"))
    }

    func testIndependentProcessesAppendWhileRetainingTheSameOpenFile() throws {
        try seed(lines: 1100, trailingNewline: true)
        let existingDescriptor = open(logURL.path, O_RDWR | O_APPEND)
        XCTAssertGreaterThanOrEqual(existingDescriptor, 0)
        defer { close(existingDescriptor) }
        var processes: [Process] = []
        var outputs: [Pipe] = []
        for name in ["A", "B"] {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xctest", "-XCTest", "LoggerReliabilityTests/testProcessWriterHelper",
                                 Bundle(for: Self.self).bundlePath]
            process.environment = ["PATH": "/usr/bin:/bin",
                                   "UTTR_LOGGER_CHILD_PATH": logURL.path,
                                   "UTTR_LOGGER_CHILD_NAME": name]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            processes.append(process)
            outputs.append(output)
        }
        for (index, process) in processes.enumerated() {
            process.waitUntilExit()
            let output = String(data: outputs[index].fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            XCTAssertEqual(process.terminationStatus, 0, output)
        }
        // A handle that predates retention must still address the visible file.
        let sentinel = Data("existing-handle\n".utf8)
        XCTAssertEqual(sentinel.withUnsafeBytes { write(existingDescriptor, $0.baseAddress, $0.count) }, sentinel.count)
        let lines = try contents().split(separator: "\n").map(String.init)
        for name in ["A", "B"] {
            for index in 0..<40 {
                XCTAssertEqual(lines.filter { $0.hasSuffix("[\(name)] child-\(index)") }.count, 1)
            }
        }
        XCTAssertFalse(lines.contains("old-0"))
        XCTAssertTrue(lines.contains("old-1099"))
        XCTAssertEqual(lines.last, "existing-handle")
    }

    // Runs in child xctest processes with the real Logger implementation.
    func testProcessWriterHelper() throws {
        guard let path = ProcessInfo.processInfo.environment["UTTR_LOGGER_CHILD_PATH"],
              let name = ProcessInfo.processInfo.environment["UTTR_LOGGER_CHILD_NAME"] else {
            throw XCTSkip("Only invoked by the cross-process logging test")
        }
        let logger = Logger(componentName: name, logFileURL: URL(fileURLWithPath: path))
        for index in 0..<40 { logger.log("child-\(index)") }
    }

    private func seed(lines: Int, trailingNewline: Bool) throws {
        let data = (0..<lines).map { "old-\($0)" }.joined(separator: "\n")
            + (trailingNewline ? "\n" : "")
        try data.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func contents() throws -> String {
        try String(contentsOf: logURL, encoding: .utf8)
    }
}
