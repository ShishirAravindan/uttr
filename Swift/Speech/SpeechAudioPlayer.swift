import AVFoundation

@MainActor
final class SpeechAudioPlayer: SpeechClipPlayer {
    private enum OutputError: LocalizedError {
        case invalidAudio
        case formatChanged

        var errorDescription: String? {
            switch self {
            case .invalidAudio: return "The voice produced invalid audio"
            case .formatChanged: return "The audio format changed during playback"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var sampleRate: Double?
    private var observer: NSObjectProtocol?
    private var generation = 0
    private var pending = 0

    var onInterrupted: (() -> Void)?
    var playbackRate: Double = 1.0 {
        didSet {
            guard sampleRate != nil else { return }
            timePitch.rate = Float(playbackRate)
        }
    }

    func play(_ clip: SpeechClip, completion: @escaping @MainActor () -> Void) throws {
        guard !clip.samples.isEmpty, clip.samples.count <= UInt32.max,
              clip.sampleRate.isFinite, clip.sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: clip.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)),
              let destination = buffer.floatChannelData?[0] else { throw OutputError.invalidAudio }
        if sampleRate != clip.sampleRate {
            guard pending == 0 else { throw OutputError.formatChanged }
            configure(format)
        }
        buffer.frameLength = buffer.frameCapacity
        clip.samples.withUnsafeBufferPointer { destination.update(from: $0.baseAddress!, count: $0.count) }
        if !engine.isRunning { try engine.start() }

        pending += 1
        let generation = self.generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.pending -= 1
                completion()
            }
        }
        if !node.isPlaying { node.play() }
    }

    func stop() {
        generation += 1
        if pending > 0 || node.isPlaying { node.stop() }
        pending = 0
    }

    func shutDown() {
        stop()
        engine.stop()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func configure(_ format: AVAudioFormat) {
        if sampleRate == nil {
            engine.attach(node)
            engine.attach(timePitch)
            timePitch.rate = Float(playbackRate)
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onInterrupted?() }
            }
        } else {
            engine.stop()
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(timePitch)
        }
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        sampleRate = format.sampleRate
    }
}
