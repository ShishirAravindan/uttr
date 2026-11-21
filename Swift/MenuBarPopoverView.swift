import SwiftUI

// MARK: - View model (owned by AppDelegate, observed by the view)

class PopoverViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var hotkeyDisplay: String = "⌥L"

    // Read-aloud
    @Published var readAloudState: ReadAloudState = .idle
    @Published var readAloudHotkeyDisplay: String = "⌥R"
    /// The voice reading, e.g. "Kokoro" or "Chatterbox Turbo".
    @Published var voiceName: String = "System voice"
    /// What the voice is doing when it isn't simply speaking ("Loading model…"),
    /// or why the selected voice isn't reading yet.
    @Published var voiceStatus: String?

    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onReadAloud: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onSkip: (() -> Void)?
    var onStopReading: (() -> Void)?

    func toggleRecording() {
        if isRecording { onStopRecording?() } else { onStartRecording?() }
    }
}

// MARK: - View

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if viewModel.readAloudState.isActive {
                NowReadingCard(viewModel: viewModel, scheme: scheme)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let status = viewModel.voiceStatus {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 268)
        .animation(.easeInOut(duration: 0.18), value: viewModel.readAloudState.isActive)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ToolButton(
                icon: viewModel.isRecording ? "stop.fill" : "mic",
                tint: viewModel.isRecording ? recordingTint : Color.textPrimary(for: scheme),
                tooltip: viewModel.isRecording
                    ? "Stop recording  \(viewModel.hotkeyDisplay)"
                    : "Start recording  \(viewModel.hotkeyDisplay)",
                scheme: scheme,
                action: viewModel.toggleRecording
            )
            ToolButton(
                icon: viewModel.readAloudState.isActive ? "speaker.slash" : "speaker.wave.2",
                tint: viewModel.readAloudState.isActive ? Color.accentLink(for: scheme) : Color.textPrimary(for: scheme),
                tooltip: viewModel.readAloudState.isActive
                    ? "Stop reading  \(viewModel.readAloudHotkeyDisplay)"
                    : "Read selection aloud with \(viewModel.voiceName)  \(viewModel.readAloudHotkeyDisplay)",
                scheme: scheme,
                action: {
                    if viewModel.readAloudState.isActive { viewModel.onStopReading?() } else { viewModel.onReadAloud?() }
                }
            )
            .disabled(viewModel.isRecording)
            divider
            ToolButton(
                icon: "list.bullet.rectangle",
                tint: Color.textPrimary(for: scheme),
                tooltip: "History",
                scheme: scheme,
                action: { viewModel.onOpenHistory?() }
            )
            ToolButton(
                icon: "gearshape",
                tint: Color.textPrimary(for: scheme),
                tooltip: "Settings  ⌘,",
                scheme: scheme,
                action: { viewModel.onOpenSettings?() }
            )
            divider
            ToolButton(
                icon: "power",
                tint: Color.textPrimary(for: scheme),
                tooltip: "Quit uttr  ⌘Q",
                scheme: scheme,
                action: { NSApplication.shared.terminate(nil) }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.rowSeparator(for: scheme))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var recordingTint: Color {
        scheme == .dark ? Color(hex: 0xE07060) : Color(hex: 0xB94A3D)
    }
}

// MARK: - Now reading

private struct NowReadingCard: View {
    @ObservedObject var viewModel: PopoverViewModel
    let scheme: ColorScheme

    private var progress: SpeechProgress? {
        if case .speaking(let progress, _) = viewModel.readAloudState { return progress }
        return nil
    }

    private var isPaused: Bool {
        if case .speaking(_, let paused) = viewModel.readAloudState { return paused }
        return false
    }

    /// Waiting for the selection, the worker, the model, or the next sentence.
    private var isWaiting: Bool {
        switch viewModel.readAloudState {
        case .readingSelection: return true
        case .speaking(let progress, _): return progress?.isBuffering ?? true
        case .idle: return false
        }
    }

    private var statusLine: String {
        if case .readingSelection = viewModel.readAloudState { return "Reading selection…" }
        if isPaused { return "Paused" }
        if isWaiting { return viewModel.voiceStatus ?? "Preparing voice…" }
        return "Reading"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VoiceLevel(isActive: !isWaiting && !isPaused, scheme: scheme)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.voiceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textPrimary(for: scheme))
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary(for: scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let progress, progress.count > 1 {
                    Text("\(progress.index + 1) of \(progress.count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.textTertiary(for: scheme))
                }
            }

            if let text = progress?.text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary(for: scheme))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(progress?.index)
                    .transition(.opacity)
            }

            if let progress, progress.count > 1 {
                ProgressView(value: Double(progress.index), total: Double(progress.count))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(Color.accentLink(for: scheme))
            }

            HStack(spacing: 2) {
                ToolButton(
                    icon: isPaused ? "play.fill" : "pause.fill",
                    tint: Color.textPrimary(for: scheme),
                    tooltip: isPaused ? "Resume" : "Pause",
                    scheme: scheme,
                    action: { viewModel.onTogglePause?() }
                )
                .disabled(progress == nil)
                ToolButton(
                    icon: "forward.fill",
                    tint: Color.textPrimary(for: scheme),
                    tooltip: "Skip to the next sentence",
                    scheme: scheme,
                    action: { viewModel.onSkip?() }
                )
                .disabled(progress == nil)
                Spacer()
                ToolButton(
                    icon: "stop.fill",
                    tint: Color.textPrimary(for: scheme),
                    tooltip: "Stop  \(viewModel.readAloudHotkeyDisplay)",
                    scheme: scheme,
                    action: { viewModel.onStopReading?() }
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cardBackground(for: scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.cardBorder(for: scheme), lineWidth: 0.5)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: progress?.index)
    }
}

/// Four bars that move while the voice speaks and settle while it waits.
private struct VoiceLevel: View {
    let isActive: Bool
    let scheme: ColorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    let phase = time * (3.1 + Double(bar) * 0.7) + Double(bar) * 1.3
                    let level = isActive ? 0.35 + 0.65 * abs(sin(phase)) : 0.25
                    Capsule()
                        .fill(Color.accentLink(for: scheme).opacity(isActive ? 0.9 : 0.45))
                        .frame(width: 3, height: 18 * level)
                }
            }
            .frame(width: 20, height: 18)
        }
        .accessibilityHidden(true)
    }
}

private struct ToolButton: View {
    let icon: String
    let tint: Color
    let tooltip: String
    let scheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered && isEnabled ? Color.textPrimary(for: scheme).opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    let vm = PopoverViewModel()
    vm.voiceName = "Qwen3-TTS 1.7B VoiceDesign"
    vm.readAloudState = .speaking(
        SpeechProgress(index: 1, count: 4, text: "\"Yes,\" she whispered, \"I heard it too.\"", isBuffering: false),
        isPaused: false
    )
    return MenuBarPopoverView(viewModel: vm)
}
