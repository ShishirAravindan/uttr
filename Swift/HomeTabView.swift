import SwiftUI

struct HomeTabView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Transcription history")
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

                Text("Your latest transcriptions, ready to copy.")
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

                        Text("No transcriptions yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary(for: scheme))

                        Text("Record with your shortcut to see recent transcriptions here.")
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
                // Timestamp
                Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary(for: scheme))
                
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
            .help(isCopied ? "Copied" : "Copy transcription")
            .accessibilityLabel(isCopied ? "Transcription copied" : "Copy transcription")
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

#Preview {
    HomeTabView()
}

