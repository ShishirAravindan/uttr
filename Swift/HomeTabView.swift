import SwiftUI

struct HomeTabView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History")
                        .font(.system(size: 22, weight: .medium))
                        .tracking(-0.88)
                        .foregroundColor(.textPrimary(for: scheme))
                    Spacer()
                    if !historyManager.transcriptions.isEmpty {
                        Text("\(historyManager.transcriptions.count) recent")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary(for: scheme))
                    }
                }

                Text("Your latest dictations, cleanups, and read-alouds, ready to copy.")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary(for: scheme))
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            // Transcriptions List
            if historyManager.transcriptions.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 24))
                            .foregroundColor(.textTertiary(for: scheme))
                            .accessibilityHidden(true)

                        Text("No history yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary(for: scheme))

                        Text("Dictate, clean up, or read text aloud with your shortcuts to see it here.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary(for: scheme))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.cardBackground(for: scheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.cardBorder(for: scheme), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 28)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(historyManager.transcriptions.prefix(20)) { transcription in
                            TranscriptionCard(transcription: transcription)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground(for: scheme))
    }
}

struct TranscriptionCard: View {
    let transcription: TranscriptionEntry
    @State private var isCopied = false
    @State private var isHovered = false
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Main Content
            VStack(alignment: .leading, spacing: 8) {
                // Kind and timestamp
                HStack(spacing: 6) {
                    Label(transcription.kind.displayName, systemImage: transcription.kind.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary(for: scheme))
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary(for: scheme))
                        .accessibilityHidden(true)
                    Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary(for: scheme))
                }
                
                // Transcription Text
                Text(transcription.text)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Clipboard Icon Button
            Button(action: copyToClipboard) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(isCopied ? Color(nsColor: .systemGreen) : .accentLink(for: scheme))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered ? Color.accentLink(for: scheme).opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCopied ? "Copied" : "Copy text")
            .accessibilityLabel(isCopied ? "Text copied" : "Copy text")
            .onHover { isHovered = $0 }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cardBackground(for: scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.cardBorder(for: scheme), lineWidth: 0.5)
                )
        )
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription.text, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
    
}

private extension HistoryEntryKind {
    var displayName: String {
        switch self {
        case .dictation: return "Dictation"
        case .cleanup: return "Cleanup"
        case .speech: return "Read aloud"
        }
    }

    var symbolName: String {
        switch self {
        case .dictation: return "mic"
        case .cleanup: return "wand.and.stars"
        case .speech: return "speaker.wave.2"
        }
    }
}

#Preview {
    HomeTabView()
}

