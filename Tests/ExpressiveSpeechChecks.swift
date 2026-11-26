import Foundation

@main
struct ExpressiveSpeechChecks {
    @MainActor
    static func main() async throws {
        checkPresets()
        try checkRequiredAssets()
        try checkStoredVoices()
        try await checkGuardedUnload()
        try await checkSharedPreparationCancellation()
        try await checkSerializedUse()
        try await checkPreparationCancellationAndRetry()
        print("Expressive speech checks passed")
    }

    private static func checkPresets() {
        let presets = ExpressiveSpeechModel.allCases
        precondition(presets.map(\.repository) == [
            "mlx-community/chatterbox-turbo-8bit",
            "mlx-community/chatterbox-fp16",
            "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
            "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16",
            "mlx-community/orpheus-3b-0.1-ft-4bit",
            "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
        ])
        precondition(presets.map(\.defaultVoice) == [
            nil, nil,
            "A warm, articulate audiobook narrator with a calm, measured pace who lets emotion come through in dialogue.",
            "Ryan", "tara", "conversational_a"
        ])
    }

    private static func checkRequiredAssets() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = VoiceModelFiles(root: folder)
        defer { try? manager.removeItem(at: folder) }

        for preset in [ExpressiveSpeechModel.chatterbox, .marvis] {
            let presetDirectory = files.directory(for: preset)
            let primary = files.payload(preset.repository, in: presetDirectory)
            try manager.createDirectory(at: primary, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: primary.appendingPathComponent("config.json"))
            try Data([1]).write(to: primary.appendingPathComponent("model.safetensors"))
            do {
                try files.markDownloaded(preset)
                preconditionFailure("main weights must not make an incomplete voice ready")
            } catch let error as CocoaError {
                precondition(error.code == .fileReadNoSuchFile)
            }
            let required = preset == .chatterbox
                ? primary.appendingPathComponent("conds.safetensors")
                : files.payload(VoiceModelFiles.marvisCodec, in: presetDirectory)
                    .appendingPathComponent(VoiceModelFiles.marvisCodecWeights)
            try manager.createDirectory(at: required.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: required)
            try files.markDownloaded(preset)
            precondition(files.isDownloaded(preset))
            try manager.removeItem(at: required)
            precondition(!files.isDownloaded(preset), "readiness must notice missing model files")
        }
    }

    @MainActor
    private static func checkSharedPreparationCancellation() async throws {
        var hold: CheckedContinuation<Int, Never>?
        var completed = false
        let preparation = SharedVoicePreparation {
            let value = await withCheckedContinuation { hold = $0 }
            completed = true
            return value
        }
        await waitUntil { hold != nil }

        var entered = false
        let cancelled = Task {
            entered = true
            return try await preparation.value()
        }
        await waitUntil { entered }
        cancelled.cancel()
        await expectCancellation(from: cancelled)
        precondition(!completed, "cancelling a read must detach before the download finishes")

        let stillWaiting = Task { try await preparation.value() }
        hold?.resume(returning: 42)
        let value = try await stillWaiting.value
        precondition(completed && value == 42, "other reads still get the prepared voice")

        var finishCancelledTransfer: CheckedContinuation<Void, Never>?
        let transfer = SharedVoicePreparation {
            await withCheckedContinuation { finishCancelledTransfer = $0 }
        }
        await waitUntil { finishCancelledTransfer != nil }
        let read = Task { try await transfer.value() }
        transfer.cancel()
        await expectCancellation(from: read)
        finishCancelledTransfer?.resume()
    }

    private static func checkStoredVoices() throws {
        let manager = FileManager.default
        let scratch = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = VoiceModelFiles(root: scratch.appendingPathComponent("models"))
        let outside = scratch.appendingPathComponent("shared")
        defer { try? manager.removeItem(at: scratch) }
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        let unrelated = outside.appendingPathComponent("weights")
        try Data([1]).write(to: unrelated)

        let installed = files.directory(for: .marvis)
        let payload = files.payload(ExpressiveSpeechModel.marvis.repository, in: installed)
        try manager.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: payload.appendingPathComponent("config.json"))
        try Data(repeating: 1, count: 4_096).write(to: payload.appendingPathComponent("model.safetensors"))
        let codec = files.payload(VoiceModelFiles.marvisCodec, in: installed)
        try manager.createDirectory(at: codec, withIntermediateDirectories: true)
        try Data([1]).write(to: codec.appendingPathComponent(VoiceModelFiles.marvisCodecWeights))
        try files.markDownloaded(.marvis)
        try manager.createSymbolicLink(at: installed.appendingPathComponent("shared"), withDestinationURL: outside)
        try manager.createSymbolicLink(at: files.directory(for: .orpheus), withDestinationURL: outside)

        let partial = files.directory(for: .chatterbox)
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data([1]).write(to: partial.appendingPathComponent("partial"))
        let inventory = files.storedVoices()
        precondition(inventory.map(\.model) == [.chatterbox, .marvis])
        precondition(inventory[0].downloaded == false && inventory[1].downloaded && inventory[1].bytes > 0)
        do {
            try files.remove(.orpheus)
            preconditionFailure("a linked preset directory must not be removable")
        } catch let error as CocoaError {
            precondition(error.code == .fileNoSuchFile)
        }
        try files.remove(.marvis)
        precondition(files.storedDirectory(for: .marvis) == nil && !files.isDownloaded(.marvis))
        precondition(manager.fileExists(atPath: unrelated.path), "removal must preserve shared files")
        precondition(files.storedVoices().map(\.model) == [.chatterbox])
    }

    @MainActor
    private static func checkGuardedUnload() async throws {
        let loader = FakeLoader()
        let host = TTSModelHost(loader: loader)
        let preparation = Task { try await host.prepare(.marvis) }
        await waitUntil { loader.loading != nil }
        loader.completeLoad()
        try await preparation.value
        try await host.unload(.orpheus)
        precondition(host.state == .ready(.marvis))

        let synthesis = Task { try await host.synthesize("speech", with: .marvis) }
        await waitUntil { loader.model.generation != nil }
        var removalQueued = false
        var allowed = true
        let removal = Task {
            removalQueued = true
            try await host.unload(.marvis, whileAllowed: { allowed })
        }
        await waitUntil { removalQueued }
        allowed = false
        loader.model.completeGeneration()
        _ = try await synthesis.value
        await expectCancellation(from: removal)
        precondition(host.state == .ready(.marvis) && loader.clears == 0)
        try await host.unload(.marvis)
        precondition(host.state == .unloaded)
    }

    @MainActor
    private static func checkSerializedUse() async throws {
        let loader = FakeLoader()
        let host = TTSModelHost(loader: loader)
        let preparation = Task { try await host.prepare(.marvis) }
        await waitUntil { loader.loading != nil }
        precondition(host.state == .loading(.marvis))

        var synthesisRequested = false
        let synthesis = Task {
            synthesisRequested = true
            return try await host.synthesize("one", with: .marvis)
        }
        await waitUntil { synthesisRequested }
        precondition(loader.model.generation == nil, "synthesis waits for model preparation")
        loader.completeLoad()
        try await preparation.value
        await waitUntil { loader.model.generation != nil }
        precondition(host.state == .ready(.marvis))
        precondition(loader.model.voice == "conversational_a")

        var entered = false
        let cancelled = Task {
            entered = true
            try await host.prepare(.orpheus)
        }
        await waitUntil { entered }
        cancelled.cancel()
        await expectCancellation(from: cancelled)
        precondition(loader.requests == [.marvis], "a cancelled waiter never loads another voice")

        var unloadRequested = false
        let unload = Task {
            unloadRequested = true
            try await host.unload()
        }
        await waitUntil { unloadRequested }
        precondition(loader.clears == 0, "unload waits for synthesis")
        loader.model.completeGeneration()
        let clip = try await synthesis.value
        precondition(clip.samples == [0.25] && clip.sampleRate == 24_000)
        try await unload.value
        precondition(host.state == .unloaded && loader.clears == 1)
    }

    @MainActor
    private static func checkPreparationCancellationAndRetry() async throws {
        let loader = FakeLoader()
        let host = TTSModelHost(loader: loader)
        let preparation = Task { try await host.prepare(.chatterbox) }
        await waitUntil { loader.loading != nil }
        preparation.cancel()
        loader.completeLoad()
        await expectCancellation(from: preparation)
        precondition(host.state == .unloaded, "an uncooperative cancelled loader cannot adopt a model")

        let failed = Task { try await host.prepare(.chatterbox) }
        await waitUntil { loader.loading != nil }
        loader.failLoad()
        do {
            try await failed.value
            preconditionFailure("unexpected backend cancellation must not look like caller cancellation")
        } catch is CancellationError {
            preconditionFailure("the caller did not cancel")
        } catch {
            if case .failed(.chatterbox, _) = host.state {} else {
                preconditionFailure("a load failure must be visible")
            }
        }

        let retry = Task { try await host.prepare(.chatterbox) }
        await waitUntil { loader.loading != nil }
        loader.completeLoad()
        try await retry.value
        try await host.prepare(.chatterbox)
        precondition(host.state == .ready(.chatterbox) && loader.requests.count == 3, "retry can load and reuse the model")

        let synthesis = Task { try await host.synthesize("two", with: .chatterbox) }
        await waitUntil { loader.model.generation != nil }
        synthesis.cancel()
        loader.model.completeGeneration()
        await expectCancellation(from: synthesis)
        precondition(host.state == .ready(.chatterbox), "stopping playback keeps the prepared model available")
        try await host.unload()
    }

    @MainActor
    private static func expectCancellation<T>(from task: Task<T, Error>) async {
        do {
            _ = try await task.value
            preconditionFailure("the operation should be cancelled")
        } catch is CancellationError {
        } catch {
            preconditionFailure("expected CancellationError, got \(error)")
        }
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("the fake didn't reach its suspension point")
    }
}

@MainActor
private final class FakeLoader: SpeechModelLoader {
    let model = FakeModel()
    var loading: CheckedContinuation<LoadedSpeechModel, Error>?
    private(set) var requests: [ExpressiveSpeechModel] = []
    private(set) var clears = 0

    func load(_ preset: ExpressiveSpeechModel) async throws -> LoadedSpeechModel {
        precondition(loading == nil)
        requests.append(preset)
        return try await withCheckedThrowingContinuation { loading = $0 }
    }

    func completeLoad() {
        let pending = loading
        loading = nil
        pending?.resume(returning: model)
    }

    func failLoad() {
        let pending = loading
        loading = nil
        pending?.resume(throwing: CancellationError())
    }

    func clearCache() { clears += 1 }
}

@MainActor
private final class FakeModel: LoadedSpeechModel {
    var generation: CheckedContinuation<SpeechClip, Never>?
    private(set) var voice: String?

    func synthesize(_ text: String, voice: String?) async throws -> SpeechClip {
        precondition(generation == nil)
        self.voice = voice
        return await withCheckedContinuation { generation = $0 }
    }

    func completeGeneration() {
        let pending = generation
        generation = nil
        pending?.resume(returning: SpeechClip(samples: [0.25], sampleRate: 24_000))
    }
}
