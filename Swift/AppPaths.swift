import Foundation

/// Where uttr keeps its on-disk state.
///
/// Debug and Release are separate apps to macOS (distinct bundle IDs), so they
/// get distinct folders too — otherwise a build run from Xcode reads and
/// overwrites the installed app's settings, history, and logs.
enum AppPaths {

    #if DEBUG
    static let appFolderName = "uttr-dev"
    #else
    static let appFolderName = "uttr"
    #endif

    /// `~/Library/Application Support/<appFolderName>`
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent(appFolderName)
    }

    /// `~/Library/Logs/<appFolderName>`
    static var logsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs").appendingPathComponent(appFolderName)
    }
}
