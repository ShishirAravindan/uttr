import SwiftUI

struct HomeTabView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if historyManager.transcriptions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(historyManager.transcriptions) { transcription in
                            TranscriptionCard(transcription: transcription, scheme: scheme)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground(for: scheme))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transcription History")
                .font(.system(size: 22, weight: .medium))
                .tracking(-0.88)
                .foregroundColor(.textPrimary(for: scheme))

            Text("Your recent speech-to-text transcriptions")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary(for: scheme))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary(for: scheme))

            Text("No transcriptions yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary(for: scheme))

            Text("Start recording to see your transcriptions here")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary(for: scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TranscriptionCard: View {
    let transcription: TranscriptionEntry
    let scheme: ColorScheme
    @State private var isCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.dateFormatter.string(from: transcription.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary(for: scheme))

                Text(transcription.text)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: copyToClipboard) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isCopied ? .accentLink(for: scheme) : .textSecondary(for: scheme))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription.text, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) { isCopied = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { isCopied = false }
        }
    }
}

#Preview {
    HomeTabView()
}
