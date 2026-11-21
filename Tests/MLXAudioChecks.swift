import Foundation

/// The mlx-audio runtime's lifecycle with a fake worker process and HTTP client,
/// plus WAV decoding, presets, the model cache check, and an end-to-end read
/// through MLXSpeechEngine. Starts no Python, loads no model, plays no audio.
@main
struct MLXAudioChecks {
    @MainActor
    static func main() async {
        checkWAV()
        checkPresets()
        checkModelCache()
        await checkLazyStartAndWarmReuse()
        await checkIdleShutdown()
        await checkWorkerExitAndRelaunch()
        await checkShutdownOnQuit()
        await checkCancellation()
        await checkNotInstalledAndTimeout()
        await checkModelSwitch()
        await checkEngine()
        print("mlx-audio checks passed")
    }

    static let logger = Logger(writer: LogWriter(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("uttr-mlx-checks-\(UUID().uuidString).log")))

    // MARK: - WAV

    static func checkWAV() {
        let mono = try! WAVDecoder.decode(wav(samples: [0, 16_384, -32_768], channels: 1, rate: 24_000))
        precondition(mono.sampleRate == 24_000 && mono.samples == [0, 0.5, -1])

        let stereo = try! WAVDecoder.decode(wav(samples: [16_384, 0, -16_384, -16_384], channels: 2, rate: 44_100))
        precondition(stereo.samples == [0.25, -0.5], "channels are averaged")

        var float = Data()
        for value: Float in [0.25, -0.75] { withUnsafeBytes(of: value.bitPattern.littleEndian) { float.append(contentsOf: $0) } }
        let decoded = try! WAVDecoder.decode(riff(format: 3, channels: 1, rate: 22_050, bits: 32, data: float))
        precondition(decoded.samples == [0.25, -0.75] && decoded.sampleRate == 22_050)

        let pcm24 = Data([0x00, 0x00, 0x40, 0x00, 0x00, 0xC0])
        precondition(try! WAVDecoder.decode(riff(format: 1, channels: 1, rate: 8_000, bits: 24, data: pcm24)).samples == [0.5, -0.5])

        precondition((try? WAVDecoder.decode(Data("not audio".utf8))) == nil)
        precondition((try? WAVDecoder.decode(riff(format: 2, channels: 1, rate: 8_000, bits: 4, data: Data([1])))) == nil)
    }

    // MARK: - Presets

    static func checkPresets() {
        let presets = MLXSpeechModel.presets
        precondition(Set(presets.map(\.id)).count == presets.count && Set(presets.map(\.repo)).count == presets.count)
        precondition(Set(presets.map(\.family)) == [.chatterbox, .qwen3, .orpheus, .csm, .miso], "every requested family")
        precondition(presets.allSatisfy { $0.id.hasPrefix("mlx.") && $0.repo.hasPrefix("mlx-community/") })
        precondition(ReadAloudVoice(id: "mlx.orpheus") == .mlx(MLXSpeechModel.preset(id: "mlx.orpheus")!))
        precondition(ReadAloudVoice(id: "gone") == .kokoro, "an unknown voice falls back to Kokoro")
        precondition(ReadAloudVoice(id: "system").id == "system")

        let chatterbox = MLXSpeechModel.preset(id: "mlx.chatterbox")!
        let request = MLXModelOptions(style: "ignored", exaggeration: 0.9).request(for: chatterbox, text: "Hi.")
        precondition(request.exaggeration == 0.9 && request.cfgWeight == MLXModelOptions.defaultCFGWeight)
        precondition(request.instruct == nil, "style is only sent to models that take it")
        precondition(request.model == chatterbox.repo && request.input == "Hi.")

        let qwen = MLXSpeechModel.preset(id: "mlx.qwen3-customvoice")!
        let defaults = MLXModelOptions(voice: "Nobody", style: "  ").request(for: qwen, text: "Hi.")
        precondition(defaults.voice == "Ryan", "an unknown voice falls back to the preset's")
        precondition(defaults.instruct == qwen.defaultStyle && defaults.mode == "custom_voice")
        precondition(defaults.exaggeration == nil && defaults.temperature == qwen.defaultTemperature)
        precondition(MLXModelOptions(voice: "Serena", style: "Excited").request(for: qwen, text: "Hi.").voice == "Serena")

        let json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        precondition(json["cfg_weight"] as? Double == 0.5 && json["instruct"] == nil, "snake_case keys, nils omitted")
    }

    // MARK: - Model cache

    static func checkModelCache() {
        let hub = FileManager.default.temporaryDirectory.appendingPathComponent("uttr-hub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: hub) }
        let repo = "mlx-community/csm-1b"
        precondition(!MLXAudioEnvironment.isModelDownloaded(repo: repo, hubCache: hub))
        let folder = MLXAudioEnvironment.modelFolder(repo: repo, hubCache: hub)
        precondition(folder.lastPathComponent == "models--mlx-community--csm-1b")
        let snapshot = folder.appendingPathComponent("snapshots/abc")
        let blobs = folder.appendingPathComponent("blobs")
        try! FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        precondition(!MLXAudioEnvironment.isModelDownloaded(repo: repo, hubCache: hub), "an empty snapshot isn't a model")
        FileManager.default.createFile(atPath: snapshot.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: blobs.appendingPathComponent("x.incomplete").path, contents: Data())
        precondition(!MLXAudioEnvironment.isModelDownloaded(repo: repo, hubCache: hub), "a partial download isn't a model")
        try! FileManager.default.removeItem(at: blobs.appendingPathComponent("x.incomplete"))
        precondition(MLXAudioEnvironment.isModelDownloaded(repo: repo, hubCache: hub))

        precondition(MLXAudioEnvironment.hubCache(environment: ["HF_HUB_CACHE": "/tmp/a"]).path == "/tmp/a")
        precondition(MLXAudioEnvironment.hubCache(environment: ["HF_HOME": "/tmp/h"]).path == "/tmp/h/hub")
        precondition(MLXAudioEnvironment.hubCache(environment: [:]).path.hasSuffix(".cache/huggingface/hub"))
        let path = MLXAudioEnvironment.workerEnvironment(base: ["PATH": "/usr/bin"])["PATH"]!
        precondition(path.hasPrefix("/usr/bin") && path.contains("/opt/homebrew/bin"))
        precondition(path.components(separatedBy: "/usr/bin:").count == 2, "no duplicate entries")
    }

    // MARK: - Runtime lifecycle

    @MainActor
    static func makeRuntime(installed: Bool = true) -> (MLXAudioRuntime, FakeLauncher, FakeClient, ManualClock) {
        let launcher = FakeLauncher()
        let client = FakeClient()
        let clock = ManualClock()
        let runtime = MLXAudioRuntime(
            launcher: launcher, client: client,
            idleTimeout: .seconds(300), startupTimeout: .seconds(90),
            isInstalled: { installed },
            sleep: { try await clock.sleep($0) },
            logger: logger
        )
        return (runtime, launcher, client, clock)
    }

    static let request = MLXSpeechRequest(model: "repo/a", input: "Hello.")

    @MainActor
    static func checkLazyStartAndWarmReuse() async {
        let (runtime, launcher, client, clock) = makeRuntime()
        await settle()
        precondition(launcher.launches == 0 && runtime.state == .stopped, "nothing starts until the first read")

        var results = 0
        let first = Task { _ = try await runtime.synthesize(request); results += 1 }
        let second = Task { _ = try await runtime.synthesize(request); results += 1 }
        await settle()
        precondition(launcher.launches == 1, "concurrent sentences share one worker")
        precondition(runtime.state == .starting && client.loads.isEmpty)

        launcher.current!.listen(port: 4100)
        await settle()
        _ = try? await first.value
        _ = try? await second.value
        precondition(results == 2)
        precondition(client.loads == ["repo/a"], "the model loads once")
        precondition(client.speeches.map(\.port) == [4100, 4100])
        precondition(Set(client.speeches.compactMap(\.request.requestID)).count == 2, "each request has its own ID")
        precondition(runtime.state == .ready("repo/a"))
        precondition(clock.waiting(for: .seconds(300)) == 1, "the idle timer starts once requests finish")
        precondition(launcher.current!.terminations == 0, "the worker stays warm")

        // The next read reuses the warm worker and restarts the idle timer.
        _ = try? await runtime.synthesize(request)
        await settle()
        precondition(launcher.launches == 1 && client.loads == ["repo/a"])
        precondition(clock.waiting(for: .seconds(300)) == 1, "activity replaces the pending idle timer")
        runtime.shutdown()
    }

    @MainActor
    static func checkIdleShutdown() async {
        let (runtime, launcher, client, clock) = makeRuntime()
        let read = Task { _ = try? await runtime.synthesize(request) }
        await settle()
        launcher.current!.listen(port: 4200)
        await read.value
        await settle()

        // No shutdown while a request is running, even if an old timer fires.
        client.holdSpeech = true
        let busy = Task { _ = try? await runtime.synthesize(request) }
        await settle()
        clock.fire(.seconds(300))
        await settle()
        precondition(launcher.current!.terminations == 0)
        client.releaseSpeech()
        await busy.value
        await settle()

        clock.fire(.seconds(300))
        await settle()
        precondition(launcher.current!.terminations == 1, "an idle worker exits, returning its memory")
        precondition(runtime.state == .stopped && !runtime.isRunning)

        // The next read starts a fresh worker and loads the model again.
        let again = Task { _ = try? await runtime.synthesize(request) }
        await settle()
        precondition(launcher.launches == 2)
        launcher.current!.listen(port: 4201)
        await again.value
        precondition(client.loads == ["repo/a", "repo/a"])
        runtime.shutdown()
    }

    @MainActor
    static func checkWorkerExitAndRelaunch() async {
        let (runtime, launcher, _, _) = makeRuntime()
        var failure: Error?
        let read = Task { do { _ = try await runtime.synthesize(request) } catch { failure = error } }
        await settle()
        launcher.current!.exit(status: 1)
        await read.value
        precondition(failure as? MLXAudioRuntimeError == .workerExited(1))
        if case .failed = runtime.state {} else { preconditionFailure("an exit is reported") }

        let retry = Task { _ = try? await runtime.synthesize(request) }
        await settle()
        precondition(launcher.launches == 2, "the next read relaunches")
        launcher.current!.listen(port: 4300)
        await retry.value
        precondition(runtime.state == .ready("repo/a"))
        runtime.shutdown()
    }

    @MainActor
    static func checkShutdownOnQuit() async {
        let (runtime, launcher, _, clock) = makeRuntime()
        var failure: Error?
        let read = Task { do { _ = try await runtime.synthesize(request) } catch { failure = error } }
        await settle()
        runtime.shutdown()
        precondition(launcher.current!.terminations == 1, "quit signals the worker synchronously")
        await read.value
        precondition(failure as? MLXAudioRuntimeError == .shutDown, "waiting reads are released")
        precondition(runtime.state == .stopped)

        // A late line or exit from the old worker changes nothing.
        launcher.current!.listen(port: 4400)
        launcher.current!.exit(status: 15)
        await settle()
        precondition(runtime.state == .stopped && clock.waiting(for: .seconds(300)) == 0)
    }

    @MainActor
    static func checkCancellation() async {
        let (runtime, launcher, client, _) = makeRuntime()
        client.holdSpeech = true
        let read = Task { _ = try await runtime.synthesize(request) }
        await settle()
        launcher.current!.listen(port: 4500)
        await settle()
        precondition(client.speeches.count == 1)
        let started = Date()
        read.cancel()
        let result = await read.result
        precondition(Date().timeIntervalSince(started) < 0.5, "cancellation returns promptly")
        if case .success = result { preconditionFailure("a cancelled read doesn't return audio") }
        await settle()
        precondition(client.cancels == [client.speeches[0].request.requestID!], "the worker is told which request to stop")
        runtime.shutdown()
    }

    @MainActor
    static func checkNotInstalledAndTimeout() async {
        let (missing, missingLauncher, _, _) = makeRuntime(installed: false)
        do {
            _ = try await missing.synthesize(request)
            preconditionFailure("no runtime, no audio")
        } catch {
            precondition(error as? MLXAudioRuntimeError == .notInstalled)
        }
        precondition(missingLauncher.launches == 0)

        let (runtime, launcher, _, clock) = makeRuntime()
        var failure: Error?
        let read = Task { do { _ = try await runtime.synthesize(request) } catch { failure = error } }
        await settle()
        clock.fire(.seconds(90))
        await read.value
        precondition(failure as? MLXAudioRuntimeError == .startupTimedOut)
        precondition(launcher.current!.terminations == 1, "a worker that never listens is stopped")
    }

    @MainActor
    static func checkModelSwitch() async {
        let (runtime, launcher, client, _) = makeRuntime()
        let read = Task { _ = try? await runtime.synthesize(request) }
        await settle()
        launcher.current!.listen(port: 4600)
        await read.value
        var other = request
        other.model = "repo/b"
        _ = try? await runtime.synthesize(other)
        precondition(client.loads == ["repo/a", "repo/b"] && launcher.launches == 1, "the warm worker loads the new model")
        precondition(runtime.state == .ready("repo/b"))
        runtime.shutdown()
    }

    // MARK: - Engine

    @MainActor
    static func checkEngine() async {
        let (runtime, launcher, client, _) = makeRuntime()
        let player = RecordingPlayer()
        let model = MLXSpeechModel.preset(id: "mlx.qwen3-voicedesign")!
        var style = "A calm narrator."
        let engine = MLXSpeechEngine(model: model, runtime: runtime, player: player) {
            MLXModelOptions(style: style)
        }
        var finished = 0
        engine.onFinished = { finished += 1 }

        let text = "First. " + (1...8).map {
            "Sentence \($0) is long enough that only two of these sentences fit together in one chunk."
        }.joined(separator: " ")
        engine.speak(text)
        await settle()
        launcher.current!.listen(port: 4700)
        await settle()
        style = "An excited narrator."
        for _ in 0..<10 {
            await settle()
            player.finishAll()
        }
        await settle()
        precondition(finished == 1)
        precondition(client.speeches.first?.request.input == "First.")
        precondition(client.speeches.count == SpeechChunks.groups(text).count && client.speeches.count > 3)
        precondition(client.speeches.map(\.request.input).joined(separator: " ") == text, "chunks are read in order")
        precondition(client.speeches.first?.request.instruct == "A calm narrator.")
        precondition(client.speeches.last?.request.instruct == "An excited narrator.", "option edits apply from the next chunk")
        precondition(client.speeches.allSatisfy { $0.request.mode == "voice_design" && $0.request.model == model.repo })

        // Stopping mid-chunk cancels the worker's request too.
        client.holdSpeech = true
        engine.speak("Another read. And more.")
        await settle()
        engine.stop()
        await settle()
        precondition(!engine.isSpeaking && client.cancels.count == 1)
        precondition(finished == 1, "stopping isn't finishing")
        runtime.shutdown()
    }

    // MARK: - Helpers

    @MainActor
    static func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    static func wav(samples: [Int16], channels: Int, rate: Int) -> Data {
        var data = Data()
        for sample in samples { withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) } }
        return riff(format: 1, channels: channels, rate: rate, bits: 16, data: data)
    }

    static func riff(format: UInt16, channels: Int, rate: Int, bits: Int, data: Data) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var out = Data("RIFF".utf8) + le(UInt32(36 + data.count)) + Data("WAVE".utf8)
        out += Data("fmt ".utf8) + le(UInt32(16)) + le(format) + le(UInt16(channels)) + le(UInt32(rate))
        out += le(UInt32(rate * channels * bits / 8)) + le(UInt16(channels * bits / 8)) + le(UInt16(bits))
        out += Data("data".utf8) + le(UInt32(data.count)) + data
        return out
    }
}

// MARK: - Fakes

@MainActor
final class FakeProcess: MLXWorkerProcess {
    let onLine: @MainActor (String) -> Void
    let onExit: @MainActor (Int32) -> Void
    var terminations = 0
    var isRunning = true

    init(onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) {
        self.onLine = onLine
        self.onExit = onExit
    }

    func terminate() {
        terminations += 1
        isRunning = false
    }

    func listen(port: Int) {
        onLine("{\"event\": \"other\"}")
        onLine("{\"event\": \"listening\", \"port\": \(port)}")
    }

    func exit(status: Int32) {
        isRunning = false
        onExit(status)
    }
}

@MainActor
final class FakeLauncher: MLXWorkerLauncher {
    var launches = 0
    var current: FakeProcess?

    func launch(onLine: @escaping @MainActor (String) -> Void,
                onExit: @escaping @MainActor (Int32) -> Void) throws -> MLXWorkerProcess {
        launches += 1
        let process = FakeProcess(onLine: onLine, onExit: onExit)
        current = process
        return process
    }
}

/// Answers every speech request with a short WAV, or holds requests until released.
final class FakeClient: MLXWorkerClient, @unchecked Sendable {
    @MainActor var loads: [String] = []
    @MainActor var speeches: [(request: MLXSpeechRequest, port: Int)] = []
    @MainActor var cancels: [String] = []
    @MainActor var holdSpeech = false
    @MainActor private var held: [CheckedContinuation<Void, Error>] = []

    func loadModel(_ repo: String, port: Int) async throws {
        await MainActor.run { loads.append(repo) }
    }

    func speak(_ request: MLXSpeechRequest, port: Int) async throws -> Data {
        try await hold(request, port: port)
        return MLXAudioChecks.wav(samples: [100, 200], channels: 1, rate: 24_000)
    }

    @MainActor
    private func hold(_ request: MLXSpeechRequest, port: Int) async throws {
        speeches.append((request, port))
        guard holdSpeech else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { held.append($0) }
        } onCancel: {
            Task { @MainActor in self.releaseSpeech(throwing: CancellationError()) }
        }
    }

    @MainActor
    func releaseSpeech(throwing error: Error? = nil) {
        holdSpeech = false
        let waiting = held
        held = []
        for continuation in waiting {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }

    func cancel(requestID: String, port: Int) async {
        await MainActor.run { cancels.append(requestID) }
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
