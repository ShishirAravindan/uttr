import Foundation

/// Shows coordinator state in the menu-bar icon and plays the matching sounds.
@MainActor
final class MenuBarFeedback: ActionFeedback {
    private let icon: MenuBarIconManager
    private let notifications: NotificationManager
    private let currentPhase: () -> StatusPhase
    private let isModelReady: () -> Bool
    private let onModelLoading: () -> Void

    init(icon: MenuBarIconManager,
         notifications: NotificationManager,
         currentPhase: @escaping () -> StatusPhase,
         isModelReady: @escaping () -> Bool,
         onModelLoading: @escaping () -> Void) {
        self.icon = icon
        self.notifications = notifications
        self.currentPhase = currentPhase
        self.isModelReady = isModelReady
        self.onModelLoading = onModelLoading
    }

    func render(_ phase: StatusPhase) {
        switch phase {
        case .ready: isModelReady() ? icon.setReadyState() : icon.setLoadingState()
        case .recording: icon.setRecordingState()
        case .processing: icon.setProcessingState()
        case .transforming: icon.setTransformingState()
        case .loadingVoice: icon.setLoadingState()
        case .speaking: icon.setSpeakingState()
        }
    }

    func recordingStarted() { notifications.showRecordingStarted() }
    func recordingStopped() { notifications.showRecordingStopped() }

    func modelLoading() {
        onModelLoading()
        notifications.showTranscriptionError("Model still loading")
        if currentPhase() == .ready { icon.setLoadingState() }
    }

    func ignored() { icon.nudge() }

    func report(_ outcome: ActionOutcome, flash: Bool) {
        let restore = { [weak self] in
            guard let self else { return }
            self.render(self.currentPhase())
        }
        switch outcome {
        case .success:
            notifications.showTranscriptionSuccess()
            if flash { icon.showSuccessState(then: restore) }
        case .leftOnClipboard:
            notifications.showTranscriptionSuccess()
            if flash { icon.showClipboardState(then: restore) }
        case .failure(let message):
            notifications.showTranscriptionError(message)
            if flash { icon.showErrorState(then: restore) }
        }
    }
}
