import Foundation

/// Where read-aloud is within the text it was given.
struct SpeechProgress: Equatable {
    /// The chunk playing, or about to play once it is synthesized.
    var index: Int
    var count: Int
    var text: String
    /// True while the chunk at `index` is still being synthesized.
    var isBuffering: Bool
}

/// Reads text aloud. Read-aloud only talks to this protocol, so the voice can change
/// without touching selection, history, or status feedback.
@MainActor
protocol SpeechEngine: AnyObject {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    /// Called when speech ends on its own; not after `stop()`.
    var onFinished: (() -> Void)? { get set }
    /// Called when speech can't continue. Speech has stopped; `onFinished` is not called.
    var onFailed: ((String) -> Void)? { get set }
    var onProgress: ((SpeechProgress) -> Void)? { get set }
    func speak(_ text: String)
    func pause()
    func resume()
    /// Moves on to the next chunk; at the last chunk, speech finishes.
    func skip()
    func stop()
    func teardown() async
}

/// Defaults for voices that can't pause, skip, report progress, or fail mid-speech.
extension SpeechEngine {
    var isPaused: Bool { false }
    var onFailed: ((String) -> Void)? { get { nil } set {} }
    var onProgress: ((SpeechProgress) -> Void)? { get { nil } set {} }
    func pause() {}
    func resume() {}
    func skip() {}
}
