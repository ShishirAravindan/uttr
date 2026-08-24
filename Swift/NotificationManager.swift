import Foundation
import AppKit

/// Sound-only feedback for the app's lifecycle and transcribe events.
class NotificationManager: ObservableObject {

    /// The events that get an audible cue, each mapped to its system sound.
    private enum Event: String {
        case appInitialized      = "Ping"
        case appInitializationFailed = "Frog"
        case recordingStarted    = "Glass"
        case recordingStopped    = "Bottle"
        case transcriptionSucceeded = "Submarine"
        case transcriptionFailed = "Sosumi"

        var soundName: String { rawValue }
    }

    // MARK: - Properties
    private let logger = Logger(componentName: "NotificationManager")

    // MARK: - Initialization
    init() {
        logger.log("Initialized with sound-only notifications", level: .debug)
    }

    // MARK: - Public Methods
    func showAppInitializationSuccess()             { play(.appInitialized) }
    func showAppInitializationError(_ message: String) { play(.appInitializationFailed, message) }
    func showRecordingStarted()                     { play(.recordingStarted) }
    func showRecordingStopped()                     { play(.recordingStopped) }
    func showTranscriptionSuccess()                 { play(.transcriptionSucceeded) }
    func showTranscriptionError(_ message: String)  { play(.transcriptionFailed, message) }

    // MARK: - Private Methods
    private func play(_ event: Event, _ message: String? = nil) {
        DispatchQueue.main.async {
            let detail = message.map { ": \($0)" } ?? ""
            self.logger.log("\(event)\(detail)", level: .debug)

            if let sound = NSSound(named: event.soundName) {
                sound.play()
            } else {
                NSSound.beep()
                self.logger.log("'\(event.soundName)' sound not found, using beep fallback", level: .debug)
            }
        }
    }
}
