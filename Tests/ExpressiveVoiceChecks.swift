import Foundation

/// The in-process model host with a fake loader and model, plus the preset
/// catalog, parameter storage, the downloaded-model check, and a read through
/// MLXSpeechEngine. Loads no model, uses no GPU, plays no audio.
@main
struct ExpressiveVoiceChecks {
    @MainActor
    static func main() async {
        checkPresets()
        checkRequests()
        checkValueCoding()
        checkModelFiles()
        await checkLazyLoadAndSerializing()
        await checkIdleUnload()
        await checkModelSwitch()
        await checkLoadFailure()
        await checkUnloadDuringLoad()
        await checkCancellation()
        await checkEngine()
        print("Expressive voice checks passed")
    }

    static let logger = Logger(writer: LogWriter(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("uttr-expressive-checks-\(UUID().uuidString).log")))

    // MARK: - Catalog

    static func checkPresets() {
        let presets = MLXSpeechModel.presets
        precondition(Set(presets.map(\.id)).count == presets.count && Set(presets.map(\.repo)).count == presets.count)
        precondition(Set(presets.map(\.family)) == [.chatterboxTurbo, .chatterbox, .qwen3VoiceDesign, .qwen3CustomVoice, .orpheus, .marvis])
        for model in presets {
            precondition(model.id.hasPrefix("mlx."))
            precondition(Set(model.parameters.map(\.id)).count == model.parameters.count, "\(model.id): parameter IDs are unique")
            precondition(model.parameter("consistent_voice") != nil, "every expressive model can keep its voice consistent")
            for parameter in model.parameters {
                switch parameter.kind {
                case .slider(let range, _, let typical):
                    precondition(range.contains(typical))
                    if let value = parameter.defaultValue?.number { precondition(range.contains(value)) }
                case .choice(let options):
                    precondition(options.contains(parameter.defaultValue?.text ?? ""), "\(model.id): default speaker is offered")
                case .text, .toggle:
                    break
                }
            }
        }
        precondition(ReadAloudVoice(id: "mlx.orpheus") == .mlx(MLXSpeechModel.preset(id: "mlx.orpheus")!))
        precondition(ReadAloudVoice(id: "mlx.csm") == .kokoro, "a dropped preset falls back to Kokoro")
        precondition(ReadAloudVoice(id: "system").id == "system")
    }

    static func checkRequests() {
        let qwen = MLXSpeechModel.preset(id: "mlx.qwen3-customvoice")!
        precondition(qwen.request(text: "Hi.", values: [:]).voice == "Ryan")
        let styled = qwen.request(text: "Hi.", values: ["speaker": .text("Serena"), "style": .text(" calm and thoughtful ")])
        precondition(styled.voice == "Serena, calm and thoughtful", "CustomVoice gets \"speaker, instruction\"")
        precondition(qwen.request(text: "Hi.", values: ["speaker": .text("Nobody")]).voice == "Ryan", "an unknown speaker falls back")
        precondition(styled.temperature == nil && styled.topP == nil, "untouched sampling uses the model's defaults")
        precondition(styled.seed == TTSRequest.consistentSeed, "the voice is kept consistent by default")
        precondition(qwen.request(text: "Hi.", values: ["consistent_voice": .flag(false)]).seed == nil)
        precondition(qwen.request(text: "Hi.", values: ["temperature": .number(0.7)]).temperature == 0.7)

        let design = MLXSpeechModel.preset(id: "mlx.qwen3-voicedesign")!
        precondition(design.request(text: "Hi.", values: [:]).voice == design.parameter("description")?.defaultValue?.text)
        precondition(design.request(text: "Hi.", values: ["description": .text("A pirate.")]).voice == "A pirate.")

        let chatterbox = MLXSpeechModel.preset(id: "mlx.chatterbox")!
        let request = chatterbox.request(text: "Hi.", values: ["exaggeration": .number(0.9)])
        precondition(request.exaggeration == 0.9 && request.cfgWeight == 0.5 && request.voice == nil)
        precondition(request.repo == chatterbox.repo && request.text == "Hi.")
        let turbo = MLXSpeechModel.preset(id: "mlx.chatterbox-turbo")!
        precondition(turbo.request(text: "Hi.", values: ["exaggeration": .number(0.9)]).exaggeration == nil,
                     "values for dials a model doesn't have are ignored")

        let orpheus = MLXSpeechModel.preset(id: "mlx.orpheus")!
        precondition(orpheus.request(text: "Hi.", values: ["speaker": .text("leo")]).voice == "leo")
    }

    static func checkValueCoding() {
        let stored: [String: TTSParameterValues] = [
            "mlx.chatterbox": ["exaggeration": .number(0.8), "consistent_voice": .flag(false)],
            "mlx.qwen3-voicedesign": ["description": .text("A gravelly sea captain.")],
        ]
        let data = try! JSONEncoder().encode(stored)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: [String: Any]]
        precondition(json["mlx.chatterbox"]?["exaggeration"] as? Double == 0.8, "values are stored flat")
        precondition(try! JSONDecoder().decode([String: TTSParameterValues].self, from: data) == stored)
    }

    static func checkModelFiles() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uttr-models-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = "mlx-community/chatterbox-turbo-8bit"
        let folder = TTSModelFiles.folder(repo: repo, root: root)
        precondition(folder.lastPathComponent == "mlx-community_chatterbox-turbo-8bit")
        precondition(!TTSModelFiles.isDownloaded(repo: repo, root: root))
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: folder.appendingPathComponent("model.safetensors").path, contents: Data())
        precondition(!TTSModelFiles.isDownloaded(repo: repo, root: root), "empty weights aren't a model")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("model.safetensors").path, contents: Data([1, 2, 3]))
        precondition(TTSModelFiles.isDownloaded(repo: repo, root: root))
        precondition(TTSModelFiles.size(of: folder) == 5)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("config.json").path, contents: Data("{".utf8))
        precondition(!TTSModelFiles.isDownloaded(repo: repo, root: root), "a broken config isn't a model")

        precondition(TTSModelFiles.hubCache(environment: ["HF_HUB_CACHE": "/tmp/a"]).path == "/tmp/a")
        precondition(TTSModelFiles.hubCache(environment: ["HF_HOME": "/tmp/h"]).path == "/tmp/h/hub")
        precondition(TTSModelFiles.modelsRoot(hubCache: URL(fileURLWithPath: "/tmp/a")).path == "/tmp/a/mlx-audio")
    }

    // MARK: - Host lifecycle

    @MainActor
    static func makeHost() -> (TTSModelHost, FakeLoader, ManualClock) {
        let loader = FakeLoader()
        let clock = ManualClock()
        let host = TTSModelHost(loader: loader, idleTimeout: .seconds(300),
                                sleep: { try await clock.sleep($0) }, logger: logger)
        return (host, loader, clock)
    }

    static func request(_ repo: String = "repo/a", _ text: String = "Hello.") -> TTSRequest {
        TTSRequest(repo: repo, text: text)
    }

    @MainActor
    static func checkLazyLoadAndSerializing() async {
        let (host, loader, clock) = makeHost()
        await settle()
        precondition(loader.loads.isEmpty && host.state == .unloaded, "nothing loads until the first read")

        loader.holdLoads = true
        var clips: [SpeechClip] = []
        let reads = (0..<3).map { index in Task { clips.append(try await host.synthesize(request("repo/a", "chunk \(index)"))) } }
        await settle()
        precondition(loader.loads == ["repo/a"] && host.state == .loading("repo/a"), "concurrent chunks share one load")
        loader.releaseLoads()
        for read in reads { _ = try? await read.value }
        precondition(clips.count == 3 && clips.allSatisfy { $0.sampleRate == 24_000 && !$0.samples.isEmpty })
        precondition(loader.loads == ["repo/a"])
        let model = loader.models[0]
        precondition(model.texts.sorted() == ["chunk 0", "chunk 1", "chunk 2"])
        precondition(model.maxConcurrent == 1, "generation never overlaps on one model")
        precondition(host.state == .ready("repo/a"))
        precondition(clock.waiting(for: .seconds(300)) == 1, "the idle timer starts once requests finish")

        _ = try? await host.synthesize(request())
        await settle()
        precondition(loader.loads == ["repo/a"], "the warm model is reused")
        precondition(clock.waiting(for: .seconds(300)) == 1, "activity replaces the pending idle timer")
        host.unload()
    }

    @MainActor
    static func checkIdleUnload() async {
        let (host, loader, clock) = makeHost()
        _ = try? await host.synthesize(request())
        await settle()

        // No unload while a chunk is generating, even if an old timer fires.
        loader.models[0].holdGeneration = true
        let busy = Task { _ = try? await host.synthesize(request()) }
        await settle()
        clock.fire(.seconds(300))
        await settle()
        precondition(host.isLoaded && loader.unloads == 0)
        loader.models[0].releaseGeneration()
        await busy.value
        await settle()

        clock.fire(.seconds(300))
        await settle()
        precondition(!host.isLoaded && host.state == .unloaded, "an idle model is dropped, returning its memory")
        precondition(loader.unloads == 1)

        _ = try? await host.synthesize(request())
        precondition(loader.loads == ["repo/a", "repo/a"], "the next read loads it again")
        host.unload()
        precondition(loader.unloads == 2 && clock.waiting(for: .seconds(300)) == 0)
    }

    @MainActor
    static func checkModelSwitch() async {
        let (host, loader, _) = makeHost()
        _ = try? await host.synthesize(request("repo/a"))
        _ = try? await host.synthesize(request("repo/b"))
        precondition(loader.loads == ["repo/a", "repo/b"] && loader.unloads == 1, "the previous model is dropped first")
        precondition(host.state == .ready("repo/b"))
        host.unload()
    }

    @MainActor
    static func checkLoadFailure() async {
        let (host, loader, _) = makeHost()
        loader.failNextLoad = true
        do {
            _ = try await host.synthesize(request())
            preconditionFailure("a model that doesn't load gives no audio")
        } catch {
            precondition(error is TTSModelLoadError && error is FatalSpeechError, "a load failure stops the read at once")
        }
        if case .failed = host.state {} else { preconditionFailure("the failure is reported") }
        _ = try? await host.synthesize(request())
        precondition(host.state == .ready("repo/a"), "the next read tries again")
        host.unload()
    }

    @MainActor
    static func checkUnloadDuringLoad() async {
        let (host, loader, _) = makeHost()
        loader.holdLoads = true
        var failure: Error?
        let read = Task { do { _ = try await host.synthesize(request()) } catch { failure = error } }
        await settle()
        host.unload()
        loader.releaseLoads()
        await read.value
        precondition(failure is CancellationError && !host.isLoaded, "a load finishing after unload is discarded")
        precondition(host.state == .unloaded)
    }

    @MainActor
    static func checkCancellation() async {
        let (host, loader, _) = makeHost()
        _ = try? await host.synthesize(request())
        let model = loader.models[0]
        model.holdGeneration = true
        let first = Task { _ = try await host.synthesize(request("repo/a", "first")) }
        await settle()
        let queued = Task { _ = try await host.synthesize(request("repo/a", "queued")) }
        await settle()

        // A chunk waiting its turn is cancelled without ever generating.
        let started = Date()
        queued.cancel()
        let queuedResult = await queued.result
        precondition(Date().timeIntervalSince(started) < 0.5, "cancellation returns promptly")
        if case .success = queuedResult { preconditionFailure("a cancelled chunk gives no audio") }

        // A generating chunk is cancelled through its task.
        first.cancel()
        if case .success = await first.result { preconditionFailure("a cancelled chunk gives no audio") }
        await settle()
        precondition(model.cancelled == ["first"] && !model.texts.contains("queued"))

        model.holdGeneration = false
        let clip = try? await host.synthesize(request("repo/a", "after"))
        precondition(clip != nil, "the host is usable after cancellations")
        host.unload()
    }

    // MARK: - Engine

    @MainActor
    static func checkEngine() async {
        let (host, loader, _) = makeHost()
        let player = RecordingPlayer()
        let model = MLXSpeechModel.preset(id: "mlx.qwen3-voicedesign")!
        var values: TTSParameterValues = ["description": .text("A calm narrator.")]
        var sentences = 3
        let engine = MLXSpeechEngine(model: model, host: host, player: player,
                                     sentencesPerChunk: { sentences }, values: { values })
        var finished = 0
        engine.onFinished = { finished += 1 }

        let text = "First. " + (1...8).map {
            "Sentence \($0) is long enough that only two of these sentences fit together in one chunk."
        }.joined(separator: " ")
        loader.holdLoads = true
        engine.speak(text)
        await settle()
        loader.releaseLoads()
        await settle()
        values["description"] = .text("An excited narrator.")
        for _ in 0..<12 {
            await settle()
            player.finishAll()
        }
        await settle()
        let requests = loader.models[0].requests
        precondition(finished == 1)
        precondition(requests.first?.text == "First.")
        precondition(requests.count == SpeechChunks.groups(text).count && requests.count > 3)
        precondition(requests.map(\.text).joined(separator: " ") == text, "chunks are read in order")
        precondition(requests.first?.voice == "A calm narrator.")
        precondition(requests.last?.voice == "An excited narrator.", "edits apply from the next chunk")
        precondition(requests.allSatisfy { $0.repo == model.repo })

        // One sentence per chunk.
        sentences = 1
        engine.speak("One. Two. Three.")
        for _ in 0..<6 {
            await settle()
            player.finishAll()
        }
        precondition(loader.models[0].requests.suffix(3).map(\.text) == ["One.", "Two.", "Three."])

        // Stopping mid-chunk cancels the generation.
        loader.models[0].holdGeneration = true
        engine.speak("Another read. And more.")
        await settle()
        engine.stop()
        await settle()
        precondition(!engine.isSpeaking && loader.models[0].cancelled.count == 1)
        precondition(finished == 2, "stopping isn't finishing")
        host.unload()
    }

    @MainActor
    static func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }
}

// MARK: - Fakes

@MainActor
final class FakeLoader: SpeechModelLoader {
    var loads: [String] = []
    var unloads = 0
    var models: [FakeModel] = []
    var holdLoads = false
    var failNextLoad = false
    private var held: [CheckedContinuation<Void, Never>] = []

    func load(repo: String) async throws -> LoadedSpeechModel {
        loads.append(repo)
        if holdLoads { await withCheckedContinuation { held.append($0) } }
        if failNextLoad {
            failNextLoad = false
            throw LoadFailed()
        }
        let model = FakeModel()
        models.append(model)
        return model
    }

    func releaseLoads() {
        holdLoads = false
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func didUnload() { unloads += 1 }
}

struct LoadFailed: LocalizedError {
    var errorDescription: String? { "weights missing" }
}

/// Returns a short clip for each request, or holds generation until released.
@MainActor
final class FakeModel: LoadedSpeechModel {
    nonisolated var sampleRate: Int { 24_000 }
    var requests: [TTSRequest] = []
    var texts: [String] { requests.map(\.text) }
    var cancelled: [String] = []
    var holdGeneration = false
    var maxConcurrent = 0
    private var running = 0
    private var held: [(text: String, continuation: CheckedContinuation<Void, Error>)] = []

    func synthesize(_ request: TTSRequest) async throws -> [Float] {
        requests.append(request)
        running += 1
        maxConcurrent = max(maxConcurrent, running)
        defer { running -= 1 }
        await Task.yield()
        if holdGeneration {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { held.append((request.text, $0)) }
            } onCancel: {
                Task { @MainActor in self.cancel(request.text) }
            }
        }
        return [0.1, 0.2]
    }

    func releaseGeneration() {
        holdGeneration = false
        let waiting = held
        held = []
        waiting.forEach { $0.continuation.resume() }
    }

    private func cancel(_ text: String) {
        guard let index = held.firstIndex(where: { $0.text == text }) else { return }
        cancelled.append(text)
        held.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// A sleep that only ends when the check fires its duration.
@MainActor
final class ManualClock {
    private var sleepers: [(id: UUID, duration: Duration, continuation: CheckedContinuation<Void, Error>)] = []

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { sleepers.append((id, duration, $0)) }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func waiting(for duration: Duration) -> Int {
        sleepers.filter { $0.duration == duration }.count
    }

    func fire(_ duration: Duration) {
        let due = sleepers.filter { $0.duration == duration }
        sleepers.removeAll { $0.duration == duration }
        due.forEach { $0.continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

@MainActor
final class RecordingPlayer: SpeechClipPlayer {
    private var queue: [@MainActor () -> Void] = []

    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void) { queue.append(completion) }
    func finishAll() {
        let waiting = queue
        queue = []
        waiting.forEach { $0() }
    }
    func pause() {}
    func resume() {}
    func stop() { queue = [] }
}
