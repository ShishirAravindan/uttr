import Foundation

/// Owns the voice that reads text aloud and switches voices between reads.
@MainActor
final class ReadAloud {
    private var engine: SpeechEngine
    private var nextEngine: SpeechEngine?
    private var generation = 0
    private var retiringEngines: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let logger: Logger

    var onPlaybackChanged: ((_ isBuffering: Bool, _ canSkip: Bool) -> Void)?
    var playbackRate = ReadAloudSettings.defaultPlaybackRate {
        didSet { engine.playbackRate = playbackRate }
    }

    init(engine: SpeechEngine? = nil, logger: Logger = Logger(componentName: "ReadAloud")) {
        self.engine = engine ?? SystemSpeechEngine()
        self.logger = logger
    }

    func useEngine(_ newEngine: SpeechEngine) {
        guard newEngine !== nextEngine else { return }
        if let nextEngine { retire(nextEngine) }
        nextEngine = nil
        guard newEngine !== engine, retiringEngines[ObjectIdentifier(newEngine)] == nil else { return }
        if engine.isSpeaking {
            nextEngine = newEngine
        } else {
            replaceEngine(with: newEngine)
        }
    }

    var isSpeaking: Bool { engine.isSpeaking }

    func speak(_ text: String, completion: @escaping (SpeechCompletion) -> Void) {
        stop()
        let generation = self.generation
        let engine = self.engine
        engine.onPlaybackChanged = { [weak self, weak engine] in
            guard let self, let engine, self.generation == generation else { return }
            self.onPlaybackChanged?(engine.isBuffering, engine.canSkip)
        }
        engine.speak(text) { [weak self] outcome in
            guard let self, self.generation == generation else { return }
            self.generation += 1
            self.engine.onPlaybackChanged = nil
            self.adoptNextEngine()
            completion(outcome)
        }
        if self.generation == generation {
            onPlaybackChanged?(engine.isBuffering, engine.canSkip)
        }
    }

    func skip() {
        if engine.canSkip { engine.skip() }
    }

    func stop() {
        generation += 1
        engine.onPlaybackChanged = nil
        if engine.isSpeaking { engine.stop() }
        adoptNextEngine()
    }

    func teardown() async {
        stop()
        await engine.teardown()
        for task in Array(retiringEngines.values) { await task.value }
    }

    private func adoptNextEngine() {
        guard let nextEngine else { return }
        self.nextEngine = nil
        replaceEngine(with: nextEngine)
    }

    private func replaceEngine(with newEngine: SpeechEngine) {
        let old = engine
        engine = newEngine
        engine.playbackRate = playbackRate
        logger.log("Read-aloud voice switched to \(type(of: newEngine))", level: .info)
        retire(old)
    }

    private func retire(_ old: SpeechEngine) {
        let id = ObjectIdentifier(old)
        retiringEngines[id] = Task { [weak self] in
            await old.teardown()
            self?.retiringEngines[id] = nil
        }
    }
}

/// Shared settings for all read-aloud voices.
struct ReadAloudSettings: Codable {
    static let playbackRateRange = 0.75...1.50
    static let defaultPlaybackRate = 1.0

    let playbackRate: Double

    enum CodingKeys: String, CodingKey {
        case playbackRate = "playback_rate"
    }

    init(playbackRate: Double = Self.defaultPlaybackRate) {
        self.playbackRate = Self.normalizedPlaybackRate(playbackRate)
    }

    init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        let rate = try? values?.decode(Double.self, forKey: .playbackRate)
        self.init(playbackRate: rate ?? Self.defaultPlaybackRate)
    }

    private static func normalizedPlaybackRate(_ rate: Double) -> Double {
        guard rate.isFinite else { return defaultPlaybackRate }
        return min(max(rate, playbackRateRange.lowerBound), playbackRateRange.upperBound)
    }
}
