import Foundation

/// Where uttr keeps its on-disk state.
///
/// Debug and Release are separate apps as far as macOS is concerned (distinct
/// bundle IDs — see `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project), but
/// `SettingsManager`, `Logger`, and `HistoryManager` used to all resolve the
/// same hardcoded "uttr" folder name regardless of build. A debug build run
/// from Xcode would silently read and overwrite the installed release app's
/// settings, history, and logs. `appFolderName` keys every on-disk location
/// off the actual compiled build, so the two never collide.
enum AppPaths {

    static let appFolderName: String = {
        #if DEBUG
        return "uttr-dev"
        #else
        return "uttr"
        #endif
    }()

    /// `~/Library/Application Support/<appFolderName>` — settings and history
    /// live here per Apple's guidance: app-generated state that isn't a user
    /// document the person manages directly belongs in Application Support,
    /// not Documents.
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
