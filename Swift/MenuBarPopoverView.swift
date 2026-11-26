import SwiftUI

// MARK: - View model (owned by AppDelegate, observed by the view)

class PopoverViewModel: ObservableObject {
    @Published var readAloudPlayback: ReadAloudPlayback?
    var onStopReadAloud: (() -> Void)?
    var onSkipReadAloud: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?
}

// MARK: - View

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            if let playback = viewModel.readAloudPlayback {
                playbackControls(for: playback)
                Divider()
            }
            toolbar
        }
        .frame(width: viewModel.readAloudPlayback == nil ? 140 : 224)
    }

    private func playbackControls(for playback: ReadAloudPlayback) -> some View {
        HStack(spacing: 4) {
            if case .playing = playback {
                Image(systemName: "speaker.wave.2")
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            Text(playback.title)
                .font(.system(size: 12))
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 4)
            if playback.canSkip {
                ToolButton(
                    icon: "forward.end",
                    tint: Color.textPrimary(for: scheme),
                    tooltip: "Skip section",
                    scheme: scheme,
                    action: { viewModel.onSkipReadAloud?() }
                )
            }
            ToolButton(
                icon: "stop.fill",
                tint: Color.textPrimary(for: scheme),
                tooltip: "Stop reading",
                scheme: scheme,
                action: { viewModel.onStopReadAloud?() }
            )
        }
        .foregroundStyle(Color.textPrimary(for: scheme))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
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
}

private struct ToolButton: View {
    let icon: String
    let tint: Color
    let tooltip: String
    let scheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.textPrimary(for: scheme).opacity(0.08) : Color.clear)
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
    return MenuBarPopoverView(viewModel: vm)
}
