import Foundation

/// Shared app state stays shared between Debug and Release, as before.
struct AppPaths {
    let applicationSupport: URL
    let legacyHistory: URL
    let recordings: URL

    init(applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("uttr"),
         documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
         temporary: URL = FileManager.default.temporaryDirectory) {
        self.applicationSupport = applicationSupport
        legacyHistory = documents.appendingPathComponent("History/transcription_history.json")
        recordings = temporary.appendingPathComponent("uttr/recordings")
    }

    var settings: URL { applicationSupport.appendingPathComponent("settings.yaml") }
    var history: URL { applicationSupport.appendingPathComponent("History/transcription_history.json") }
}
