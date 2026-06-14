import Foundation
import AVFoundation
import ApplicationServices
import AppKit

// MARK: - Permission Notifications

extension Notification.Name {
    /// Posted on the main queue the moment Accessibility flips from denied/not-determined
    /// to authorized, so the app can re-register global hotkeys without a restart.
    static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
}

/// Single source of truth for the app's permission state.
///
/// Owns checking, requesting and prompting for both Microphone and Accessibility,
/// and keeps `@Published` status in sync so any SwiftUI view reflects it live.
/// While a permission is still missing it polls (and also refreshes whenever the
/// app is reactivated) so granting a permission in System Settings is picked up
/// immediately — no quit-and-relaunch required.
class PermissionManager: ObservableObject {

    // MARK: - Published Properties
    @Published var microphonePermissionStatus: PermissionStatus = .notDetermined
    @Published var accessibilityPermissionStatus: PermissionStatus = .notDetermined

    private let logger = Logger(componentName: "PermissionManager")
    private var pollingTimer: Timer?

    // MARK: - Permission Status Enum
    enum PermissionStatus {
        case notDetermined
        case denied
        case authorized
        case restricted

        var displayText: String {
            switch self {
            case .notDetermined: return "Not requested"
            case .denied:        return "Denied"
            case .authorized:    return "Granted"
            case .restricted:    return "Restricted"
            }
        }

        var color: NSColor {
            switch self {
            case .notDetermined:     return .systemOrange
            case .denied, .restricted: return .systemRed
            case .authorized:        return .systemGreen
            }
        }

        var icon: String {
            switch self {
            case .notDetermined:       return "questionmark.circle.fill"
            case .denied, .restricted: return "xmark.circle.fill"
            case .authorized:          return "checkmark.circle.fill"
            }
        }

        var isAuthorized: Bool { self == .authorized }
    }

    // MARK: - Initialization
    init() {
        refresh()

        // Re-check whenever the user switches back to the app — typically right
        // after granting a permission in System Settings.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        pollingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Onboarding

    /// Requests both permissions in a single, coherent first-run flow:
    /// microphone first (an in-app prompt), then accessibility (opens System Settings).
    func requestPermissionsForOnboarding() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.requestMicrophonePermission()
            await MainActor.run {
                self.requestAccessibilityPermission()
                self.startPollingIfNeeded()
            }
        }
    }

    /// True while any required permission is still missing.
    var hasAllPermissions: Bool {
        microphonePermissionStatus.isAuthorized && accessibilityPermissionStatus.isAuthorized
    }

    // MARK: - Public Requests
    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { self.microphonePermissionStatus = granted ? .authorized : .denied }
            logger.log("Microphone permission requested, granted: \(granted)", level: .info)
            return granted

        case .denied, .restricted:
            await MainActor.run { self.microphonePermissionStatus = status == .denied ? .denied : .restricted }
            logger.log("Microphone permission denied or restricted", level: .warning)
            return false

        case .authorized:
            await MainActor.run { self.microphonePermissionStatus = .authorized }
            return true

        @unknown default:
            await MainActor.run { self.microphonePermissionStatus = .denied }
            return false
        }
    }

    /// Prompts for Accessibility. macOS shows the prompt and opens System Settings only
    /// the first time; afterwards `refresh()`/polling pick up the grant.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        applyAccessibility(trusted: trusted)
        logger.log("Accessibility permission requested, trusted: \(trusted)", level: .info)
        startPollingIfNeeded()
    }

    func openSystemPreferences(for permission: PermissionType) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    /// Drives the primary button for a permission row.
    func performPrimaryAction(for permission: PermissionType) {
        switch permission {
        case .microphone:
            if microphonePermissionStatus == .notDetermined {
                Task { await requestMicrophonePermission() }
            } else if !microphonePermissionStatus.isAuthorized {
                openSystemPreferences(for: .microphone)
            }
        case .accessibility:
            if accessibilityPermissionStatus.isAuthorized {
                openSystemPreferences(for: .accessibility)
            } else {
                requestAccessibilityPermission()
            }
        }
    }

    func primaryActionText(for permission: PermissionType) -> String {
        let status = status(for: permission)
        switch status {
        case .authorized:               return "Manage…"
        case .notDetermined:            return "Grant"
        case .denied, .restricted:      return "Open Settings"
        }
    }

    func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .microphone:    return microphonePermissionStatus
        case .accessibility: return accessibilityPermissionStatus
        }
    }

    // MARK: - Refresh / Polling

    /// Re-reads both permissions from the system and publishes any changes.
    func refresh() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let mic: PermissionStatus
        switch micStatus {
        case .notDetermined: mic = .notDetermined
        case .denied:        mic = .denied
        case .restricted:    mic = .restricted
        case .authorized:    mic = .authorized
        @unknown default:    mic = .denied
        }

        let trusted = AXIsProcessTrusted()

        DispatchQueue.main.async {
            self.microphonePermissionStatus = mic
            self.applyAccessibility(trusted: trusted)
        }
    }

    @objc private func handleAppDidBecomeActive() {
        refresh()
    }

    private func startPollingIfNeeded() {
        guard pollingTimer == nil, !hasAllPermissions else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refresh()
            if self.hasAllPermissions { self.stopPolling() }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// Updates the accessibility status and broadcasts the grant transition so the
    /// app can re-register hotkeys live. Must be called on the main thread.
    private func applyAccessibility(trusted: Bool) {
        let newStatus: PermissionStatus = trusted ? .authorized : .denied
        let wasAuthorized = accessibilityPermissionStatus.isAuthorized
        accessibilityPermissionStatus = newStatus
        if trusted && !wasAuthorized {
            logger.log("Accessibility permission granted — broadcasting", level: .info)
            NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: self)
        }
    }
}

// MARK: - Permission Type Enum
enum PermissionType: CaseIterable {
    case microphone
    case accessibility

    var displayName: String {
        switch self {
        case .microphone:    return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    var description: String {
        switch self {
        case .microphone:    return "Required for speech recording"
        case .accessibility: return "Required for the global hotkey and paste-at-cursor"
        }
    }
}
