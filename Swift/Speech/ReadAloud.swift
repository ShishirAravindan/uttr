import Foundation

/// Owns the voice that reads text aloud and switches voices between reads.
@MainActor
final class ReadAloud {
    private var engine: SpeechEngine
    private var nextEngine: SpeechEngine?
    private var generation = 0
    private var retiringEngines: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let logger: Logger

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
        engine.speak(text) { [weak self] outcome in
            guard let self, self.generation == generation else { return }
            self.generation += 1
            self.adoptNextEngine()
            completion(outcome)
        }
    }

    func stop() {
        generation += 1
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
