import Combine
import Foundation
import XCTest

final class StorageLifecycleTests: XCTestCase {
    func testMigrationKeepsUnrelatedDocumentsAndNewestUniqueHistory() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let old = TranscriptionEntry(text: "Legacy")
        let newest = TranscriptionEntry(text: "Current")
        try fixture.write([old], at: fixture.paths.legacyHistory)
        try fixture.write([newest, old], at: fixture.paths.history)
        let userFile = fixture.paths.legacyHistory.deletingLastPathComponent().appendingPathComponent("notes.txt")
        try Data("User document".utf8).write(to: userFile)

        let entries = try HistoryStore(paths: fixture.paths).load()
        XCTAssertEqual(entries.map(\.id), [newest.id, old.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.legacyHistory.path))
        XCTAssertEqual(try Data(contentsOf: userFile), Data("User document".utf8))
        XCTAssertEqual(try HistoryStore(paths: fixture.paths).load().map(\.id), entries.map(\.id))
    }

    func testMigrationRemovesOnlyEmptyLegacyDirectory() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        try fixture.write([TranscriptionEntry(text: "Keep")], at: fixture.paths.legacyHistory)
        XCTAssertEqual(try HistoryStore(paths: fixture.paths).load().first?.text, "Keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.legacyHistory.deletingLastPathComponent().path))
    }

    func testCorruptDestinationPreservesBothFilesEvenOnAddAndClear() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        try fixture.write([TranscriptionEntry(text: "Legacy")], at: fixture.paths.legacyHistory)
        let legacy = try Data(contentsOf: fixture.paths.legacyHistory)
        try FileManager.default.createDirectory(at: fixture.paths.history.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: fixture.paths.history)
        let store = HistoryStore(paths: fixture.paths)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.add(TranscriptionEntry(text: "New")))
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try Data(contentsOf: fixture.paths.legacyHistory), legacy)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.history), corrupt)
    }

    func testCorruptLegacyLeavesValidDestinationUsable() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        try fixture.write([TranscriptionEntry(text: "Current")], at: fixture.paths.history)
        let current = try Data(contentsOf: fixture.paths.history)
        try FileManager.default.createDirectory(at: fixture.paths.legacyHistory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("bad legacy".utf8)
        try corrupt.write(to: fixture.paths.legacyHistory)
        var failures = 0
        let store = HistoryStore(paths: fixture.paths, report: { _ in failures += 1 })
        XCTAssertEqual(try store.load().first?.text, "Current")
        XCTAssertEqual(try Data(contentsOf: fixture.paths.history), current)
        let added = try store.add(TranscriptionEntry(text: "New"))
        XCTAssertEqual(added.map(\.text), ["New", "Current"])
        XCTAssertEqual(try Data(contentsOf: fixture.paths.legacyHistory), corrupt)
        XCTAssertEqual(failures, 2)
        try store.clear()
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.legacyHistory), corrupt)
    }

    func testCorruptLegacyWithoutDestinationRemainsPreserved() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.paths.legacyHistory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("bad legacy".utf8)
        try corrupt.write(to: fixture.paths.legacyHistory)
        let store = HistoryStore(paths: fixture.paths)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.add(TranscriptionEntry(text: "New")))
        XCTAssertEqual(try Data(contentsOf: fixture.paths.legacyHistory), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.history.path))
    }

    func testMigrationReceiptDoesNotResurrectClearedHistory() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let entry = TranscriptionEntry(text: "Legacy")
        try fixture.write([entry], at: fixture.paths.legacyHistory)
        let legacy = try Data(contentsOf: fixture.paths.legacyHistory)
        let store = HistoryStore(paths: fixture.paths)
        _ = try store.load()
        // Recreate the identical source, simulating a legacy file retained after failed deletion.
        try FileManager.default.createDirectory(at: fixture.paths.legacyHistory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacy.write(to: fixture.paths.legacyHistory)
        try store.clear()
        XCTAssertTrue(try HistoryStore(paths: fixture.paths).load().isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.legacyHistory), legacy)
    }

    func testFailedDestinationWritePreservesLegacy() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        try fixture.write([TranscriptionEntry(text: "Legacy")], at: fixture.paths.legacyHistory)
        let legacy = try Data(contentsOf: fixture.paths.legacyHistory)
        try FileManager.default.createDirectory(at: fixture.paths.applicationSupport, withIntermediateDirectories: true)
        try Data("blocks History directory".utf8).write(to: fixture.paths.history.deletingLastPathComponent())
        XCTAssertThrowsError(try HistoryStore(paths: fixture.paths).load())
        XCTAssertEqual(try Data(contentsOf: fixture.paths.legacyHistory), legacy)
    }

    func testIndependentStoresDoNotLoseConcurrentEntries() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let entries = (0..<5).map { TranscriptionEntry(text: "Entry \($0)") }
        let errors = LockedErrors()
        DispatchQueue.concurrentPerform(iterations: entries.count) { index in
            do { _ = try HistoryStore(paths: fixture.paths).add(entries[index]) }
            catch { errors.append(error) }
        }
        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertEqual(Set(try HistoryStore(paths: fixture.paths).load().map(\.id)), Set(entries.map(\.id)))
        _ = try HistoryStore(paths: fixture.paths).add(TranscriptionEntry(text: "Newest"))
        XCTAssertEqual(try HistoryStore(paths: fixture.paths).load().count, 5)
        try HistoryStore(paths: fixture.paths).clear()
        XCTAssertTrue(try HistoryStore(paths: fixture.paths).load().isEmpty)
    }

    func testRecordingNamesAreUniqueAndDeletionStaysWithinOwnedFiles() throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let files = RecordingFiles(paths: fixture.paths)
        let urls = try (0..<100).map { _ in try files.makeURL() }
        XCTAssertEqual(Set(urls).count, 100)
        let userFile = files.directory.appendingPathComponent("notes.wav")
        try Data("Keep".utf8).write(to: userFile)
        let outside = fixture.root.appendingPathComponent(urls[0].lastPathComponent)
        try Data("Keep".utf8).write(to: outside)
        try Data("Audio".utf8).write(to: urls[0])
        try files.remove(userFile)
        try files.remove(outside)
        try files.remove(urls[0])
        try files.remove(urls[0])
        let misleadingDirectory = urls[1]
        try FileManager.default.createDirectory(at: misleadingDirectory, withIntermediateDirectories: true)
        let nestedUserFile = misleadingDirectory.appendingPathComponent("notes.txt")
        try Data("Keep nested".utf8).write(to: nestedUserFile)
        XCTAssertThrowsError(try files.remove(misleadingDirectory))
        XCTAssertEqual(try Data(contentsOf: nestedUserFile), Data("Keep nested".utf8))
        XCTAssertEqual(try Data(contentsOf: userFile), Data("Keep".utf8))
        XCTAssertEqual(try Data(contentsOf: outside), Data("Keep".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
    }

    @MainActor
    func testCancelledInferenceKeepsAudioUntilReaderReturns() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let files = RecordingFiles(paths: fixture.paths)
        let recorder = StorageRecorder(url: try files.makeURL())
        let provider = StorageProvider()
        let paste = StoragePaste()
        let session = TranscriptionSession(recorder: recorder, provider: provider, pasteManager: paste, removeRecording: files.remove)
        session.prepare()
        await ready(session)
        session.startRecording()
        session.stopRecording()
        await fulfillment(of: [provider.started], timeout: 3)
        let shutdown = session.shutDown()
        XCTAssertTrue(FileManager.default.fileExists(atPath: recorder.url.path))
        provider.complete(.success("Late text"))
        await shutdown.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.url.path))
        XCTAssertEqual(paste.texts, [])
    }

    @MainActor
    func testSuccessfulAndFailedInferenceReleaseAudio() async throws {
        for succeeds in [true, false] {
            let fixture = try StorageFixture()
            defer { fixture.remove() }
            let files = RecordingFiles(paths: fixture.paths)
            let recorder = StorageRecorder(url: try files.makeURL())
            let provider = StorageProvider()
            let paste = StoragePaste()
            let session = TranscriptionSession(recorder: recorder, provider: provider, pasteManager: paste, removeRecording: files.remove)
            session.prepare()
            await ready(session)
            session.startRecording()
            session.stopRecording()
            await fulfillment(of: [provider.started], timeout: 3)
            XCTAssertTrue(FileManager.default.fileExists(atPath: recorder.url.path))
            provider.complete(succeeds ? .success("Text") : .failure(StorageFailure.expected))
            await ready(session)
            XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.url.path))
            XCTAssertEqual(paste.texts, succeeds ? ["Text"] : [])
            await session.shutDown().value
        }
    }

    @MainActor
    func testShutdownCaptureAndStartFailureReleaseAudio() async throws {
        for fails in [false, true] {
            let fixture = try StorageFixture()
            defer { fixture.remove() }
            let files = RecordingFiles(paths: fixture.paths)
            let recorder = StorageRecorder(url: try files.makeURL())
            recorder.failStart = fails
            let session = TranscriptionSession(recorder: recorder, provider: StorageProvider(), pasteManager: StoragePaste(), removeRecording: files.remove)
            session.prepare()
            await ready(session)
            session.startRecording()
            await session.shutDown().value
            XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.url.path))
        }
    }

    @MainActor
    private func ready(_ session: TranscriptionSession) async {
        if session.state == .idle { return }
        let reached = expectation(description: "Idle")
        let observation = session.$state.filter { $0 == .idle }.sink { _ in reached.fulfill() }
        await fulfillment(of: [reached], timeout: 3)
        observation.cancel()
        // Drain queued state/event effects and task defers on the main actor.
        await Task { @MainActor in }.value
        XCTAssertEqual(session.state, .idle)
    }
}

private struct StorageFixture {
    let root: URL
    let paths: AppPaths
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("uttr-storage-test-\(UUID().uuidString)")
        paths = AppPaths(applicationSupport: root.appendingPathComponent("Support"), documents: root.appendingPathComponent("Documents"), temporary: root.appendingPathComponent("Temporary"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func write(_ entries: [TranscriptionEntry], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class LockedErrors {
    private let lock = NSLock()
    private(set) var values: [Error] = []
    func append(_ error: Error) { lock.lock(); defer { lock.unlock() }; values.append(error) }
}
private enum StorageFailure: Error { case expected }
private final class StorageRecorder: SessionRecording {
    var preferredInputDeviceUID: String?
    var onInterrupted: (() -> Void)?
    let url: URL
    var failStart = false
    init(url: URL) { self.url = url }
    func startRecording() throws {
        try Data("Audio".utf8).write(to: url)
        if failStart { throw StorageFailure.expected }
    }
    func stopRecording() -> URL? { url }
}
@MainActor
private final class StorageProvider: TranscriptionProvider {
    let id = "storage-test"
    let displayName = "Storage test"
    let started = XCTestExpectation(description: "Reader suspended")
    private var continuation: CheckedContinuation<String, Error>?
    func prepare() async throws { }
    func transcribe(audioFileURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func complete(_ result: Result<String, Error>) { continuation?.resume(with: result); continuation = nil }
    func teardown() async { }
}
private final class StoragePaste: SessionPasting {
    var texts: [String] = []
    func pasteText(_ text: String, completion: @escaping (Bool) -> Void) { texts.append(text); completion(true) }
}
