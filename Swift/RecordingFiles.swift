import Darwin
import Foundation

struct RecordingFiles {
    let directory: URL
    init(paths: AppPaths = AppPaths()) { directory = paths.recordings.standardizedFileURL }

    func makeURL() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory.appendingPathComponent("recording_\(UUID().uuidString).wav")
    }

    func remove(_ url: URL) throws {
        let url = url.standardizedFileURL
        guard url.deletingLastPathComponent().path == directory.path,
              url.pathExtension == "wav",
              url.deletingPathExtension().lastPathComponent.hasPrefix("recording_"),
              UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.dropFirst(10))) != nil
        else { return }
        // unlink cannot recursively remove a directory, even if its name looks owned.
        if url.path.withCString({ Darwin.unlink($0) }) != 0, errno != ENOENT {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
