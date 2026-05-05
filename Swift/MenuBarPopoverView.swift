import SwiftUI

// MARK: - View model (owned by AppDelegate, observed by the view)

class PopoverViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var hotkeyDisplay: String = "⌥L"

    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    func toggleRecording() {
        if isRecording { onStopRecording?() } else { onStartRecording?() }
        isRecording.toggle()
    }
}

// MARK: - View

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            PopoverRow(
                icon: viewModel.isRecording ? "stop.fill" : "mic",
                label: viewModel.isRecording ? "Stop recording" : "Start recording",
                shortcut: viewModel.hotkeyDisplay,
                scheme: scheme,
                action: viewModel.toggleRecording
            )

            popoverSeparator

            PopoverRow(
                icon: "list.bullet.rectangle",
                label: "History…",
                shortcut: nil,
                scheme: scheme,
                dimmed: viewModel.isRecording,
                action: { viewModel.onOpenHistory?() }
            )

            PopoverRow(
                icon: "gearshape",
                label: "Settings…",
                shortcut: "⌘,",
                scheme: scheme,
                dimmed: viewModel.isRecording,
                action: { viewModel.onOpenSettings?() }
            )

            popoverSeparator

            PopoverRow(
                icon: nil,
                label: "Quit uttr",
                shortcut: "⌘Q",
                scheme: scheme,
                action: { NSApplication.shared.terminate(nil) }
            )
        }
        .padding(4)
        .frame(width: 220)
    }

    private var popoverSeparator: some View {
        Rectangle()
            .fill(Color(hex: 0x1F1D1A, opacity: 0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: - Row

private struct PopoverRow: View {
    let icon: String?
    let label: String
    let shortcut: String?
    let scheme: ColorScheme
    var dimmed: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { if !dimmed { action() } }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 13, height: 13)
                        .foregroundColor(.textPrimary(for: scheme))
                } else {
                    Spacer().frame(width: 13)
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(.textPrimary(for: scheme).opacity(0.55))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && !dimmed ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.4 : 1.0)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    let vm = PopoverViewModel()
    return MenuBarPopoverView(viewModel: vm)
        .frame(width: 220)
        .padding(8)
}
