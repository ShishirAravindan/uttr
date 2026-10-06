import SwiftUI
import Cocoa
import Combine

@main
struct uttr: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindowView(
                settings: appDelegate.settingsManager,
                permissions: appDelegate.permissionManager
            )
        }
        .defaultSize(width: 520, height: 580)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {

    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var session: TranscriptionSession?
    private var sessionObservation: AnyCancellable?
    private var logger: Logger?
    let settingsManager = SettingsManager()
    let permissionManager = PermissionManager()
    private var notificationManager: NotificationManager?
    private var popoverViewModel = PopoverViewModel()
    private var popover: NSPopover?
    private var menuBarIconManager: MenuBarIconManager?
    private var eventMonitor: Any?

    // History window
    private var historyWindow: NSWindow?
    private var historyWindowController: NSWindowController?

    // Settings window
    private var settingsWindow: NSWindow?
    private var settingsWindowController: NSWindowController?

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupComponents()
        setupMenuBar()
        session?.prepare()
        requestPermissions()
        logger?.log("=== App Setup Complete ===", level: .info)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    // MARK: - Permissions

    /// Runs the first-run permission flow and re-registers the global hotkey the
    /// instant Accessibility is granted, so the user never has to quit and relaunch.
    private func requestPermissions() {
        NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.logger?.log("Accessibility granted — re-registering global hotkey", level: .info)
                self?.hotkeyManager?.refreshHotkeyConfiguration()
            }
        }

        if !permissionManager.hasAllPermissions {
            permissionManager.requestPermissionsForOnboarding()
        }
    }

    // MARK: - Setup
    private func setupComponents() {
        logger = Logger()
        logger?.log("=== Initializing App Setup ===", level: .debug)

        notificationManager = NotificationManager()
        let recorder = AudioRecorder()
        recorder.preferredInputDeviceUID = settingsManager.inputDeviceUID
        let session = TranscriptionSession(
            recorder: recorder,
            provider: TranscriptionProviderFactory.make(id: settingsManager.transcriptionProviderID),
            pasteManager: PasteManager()
        )
        self.session = session
        session.onEvent = { [weak self] event in self?.handleSessionEvent(event) }
        sessionObservation = session.$state.sink { [weak self] state in
            self?.renderSessionState(state)
        }

        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        hotkeyManager?.onTranscribeHotkeyPressed = { [weak session] in
            session?.toggleRecording()
        }

        popoverViewModel.hotkeyDisplay = settingsManager.getHotkeyDisplayString()
        popoverViewModel.onToggleRecording = { [weak session] in session?.toggleRecording() }
        popoverViewModel.onOpenSettings   = { [weak self] in self?.openSettingsWindow() }
        popoverViewModel.onOpenHistory    = { [weak self] in self?.openHistoryWindow() }

        NotificationCenter.default.addObserver(
            forName: .transcriptionProviderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSettingsChanged() }
        }

        // The recorder builds a fresh engine per recording, so the new device
        // takes effect on the next one — no need to rebuild anything here.
        NotificationCenter.default.addObserver(
            forName: .inputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.session?.setInputDevice(uid: self.settingsManager.inputDeviceUID)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hotkeyManager?.refreshHotkeyConfiguration()
                self?.popoverViewModel.hotkeyDisplay = self?.settingsManager.getHotkeyDisplayString() ?? ""
            }
        }

        // Show dock icon whenever a titled window is active
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow,
               window.styleMask.contains(.titled) {
                NSApp.setActivationPolicy(.regular)
            }
        }

        // Reset activation policy to accessory when all titled windows have closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.dismissIfNoWindows()
            }
        }

        logger?.log("App Components Initialized", level: .debug)
    }

    // MARK: - Session presentation

    private func renderSessionState(_ state: SessionState) {
        popoverViewModel.sessionState = state
        settingsManager.providerStatus = session?.providerStatus(for: state) ?? "Loading…"
        menuBarIconManager?.renderSessionState(state)
    }

    private func handleSessionEvent(_ event: SessionEvent) {
        let restoreIcon = { [weak self] in
            guard let self, let session = self.session else { return }
            self.menuBarIconManager?.renderSessionState(session.state)
        }
        switch event {
        case .providerReady(let name):
            logger?.log("Transcription provider ready: \(name)")
            notificationManager?.showAppInitializationSuccess()
            menuBarIconManager?.playStartupAnimation()
        case .providerFailed(let message):
            logger?.log("Failed to prepare transcription provider: \(message)", level: .error)
            notificationManager?.showAppInitializationError("Failed to prepare transcription provider")
        case .notReady:
            logger?.log("Recording blocked — transcription model unavailable", level: .warning)
            notificationManager?.showTranscriptionError("Model unavailable")
        case .recordingStarted:
            logger?.log("Recording started")
            notificationManager?.showRecordingStarted()
        case .recordingStopped:
            logger?.log("Recording stopped; processing audio")
            notificationManager?.showRecordingStopped()
        case .recordingFailed(let message):
            logger?.log(message, level: .error)
            notificationManager?.showTranscriptionError(message)
            menuBarIconManager?.showErrorState(restore: restoreIcon)
        case .recordingCleanupFailed(let message):
            logger?.log("Failed to remove recording: \(message)", level: .error)
        case .recordingInterrupted:
            logger?.log("Recording interrupted — device stopped unexpectedly", level: .error)
            notificationManager?.showTranscriptionError("Microphone disconnected")
            menuBarIconManager?.showErrorState(restore: restoreIcon)
        case .transcribed(let text, let audioFileName):
            logger?.log("Handling transcribed text: \(text)")
            HistoryManager.shared.addTranscription(text, audioFileName: audioFileName)
        case .transcriptionFailed(let message):
            logger?.log("Transcription failed: \(message)", level: .error)
            notificationManager?.showTranscriptionError("Transcription failed: \(message)")
            menuBarIconManager?.showErrorState(restore: restoreIcon)
        case .inserted:
            logger?.log("Text pasted at cursor successfully")
            notificationManager?.showTranscriptionSuccess()
            menuBarIconManager?.showSuccessState(restore: restoreIcon)
        case .insertionFailed:
            logger?.log("Failed to paste text at cursor", level: .error)
            notificationManager?.showTranscriptionError("Failed to paste text at cursor")
            menuBarIconManager?.showErrorState(restore: restoreIcon)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.imagePosition = .imageLeft
            button.action = #selector(menuBarClicked)
            button.target = self
        }

        menuBarIconManager = MenuBarIconManager(statusItem: statusItem!)
        setupPopover()
        if let session { renderSessionState(session.state) }
    }

    private func setupPopover() {
        let popoverView = MenuBarPopoverView(viewModel: popoverViewModel)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 220, height: 46)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: popoverView)
        popover?.delegate = self

        logger?.log("MenuBarPopoverView setup complete", level: .debug)
    }

    // MARK: - Event Handlers
    @objc private func menuBarClicked() {
        guard statusItem?.button != nil else { return }
        if popover?.isShown == true { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover?.isShown == true { self?.closePopover() }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Window Management

    /// Public entry point used by the popover button and the SwiftUI Settings command.
    func showSettings() {
        openSettingsWindow()
    }

    private func openSettingsWindow() {
        logger?.log("Opening settings window", level: .info)
        closePopover()

        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsWindowView(settings: settingsManager, permissions: permissionManager)
            )
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 520, height: 580))
            settingsWindow?.center()
            settingsWindow?.delegate = self
            settingsWindowController = NSWindowController(window: settingsWindow)
        }

        NSApp.setActivationPolicy(.regular)
        settingsWindowController?.showWindow(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistoryWindow() {
        logger?.log("Opening history window", level: .info)

        if historyWindow == nil {
            let hostingController = NSHostingController(rootView: HomeTabView())
            historyWindow = NSWindow(contentViewController: hostingController)
            historyWindow?.title = "History"
            historyWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            historyWindow?.setContentSize(NSSize(width: 520, height: 500))
            historyWindow?.center()
            historyWindow?.delegate = self
            historyWindowController = NSWindowController(window: historyWindow)
        }

        NSApp.setActivationPolicy(.regular)
        historyWindowController?.showWindow(nil)
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissIfNoWindows() {
        let hasVisibleTitledWindow = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasVisibleTitledWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Window Delegate
    func windowWillClose(_ notification: Notification) {
        switch notification.object as? NSWindow {
        case historyWindow:
            historyWindow = nil
            historyWindowController = nil
        case settingsWindow:
            settingsWindow = nil
            settingsWindowController = nil
        default:
            break
        }
    }

    // MARK: - Settings Handler
    private func handleSettingsChanged() {
        session?.changeProvider(
            TranscriptionProviderFactory.make(id: settingsManager.transcriptionProviderID)
        )
        if let session { renderSessionState(session.state) }
    }

    // MARK: - Cleanup
    private func cleanup() {
        session?.shutDown()
        sessionObservation = nil
        closePopover()
        historyWindow?.close()
        historyWindow = nil
        historyWindowController = nil
        settingsWindow?.close()
        settingsWindow = nil
        settingsWindowController = nil
        NotificationCenter.default.removeObserver(self)
        logger?.log("App terminating")
    }
}
