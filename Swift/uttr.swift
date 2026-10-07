import SwiftUI
import Cocoa
import AVFoundation

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

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {

    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private var audioRecorder: AudioRecorder?
    private var hotkeyManager: HotkeyManager?
    private var pasteManager: PasteManager?
    private var transcriptionProvider: TranscriptionProvider?
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

    private enum WorkflowState { case loading, ready, recording, processing, unavailable, stopped }
    private var state: WorkflowState = .loading {
        didSet { renderWorkflowState() }
    }
    private var workflowTask: Task<Void, Never>?
    private var pendingProviderID: String?

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupComponents()
        setupMenuBar()
        startTranscriptionProvider()
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
            self?.logger?.log("Accessibility granted — re-registering global hotkey", level: .info)
            self?.hotkeyManager?.refreshHotkeyConfiguration()
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
        audioRecorder = AudioRecorder()
        audioRecorder?.preferredInputDeviceUID = settingsManager.inputDeviceUID
        audioRecorder?.onInterrupted = { [weak self] in
            self?.handleRecordingInterrupted()
        }

        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        pasteManager = PasteManager()

        hotkeyManager?.onTranscribeHotkeyPressed = { [weak self] in
            self?.handleTranscribeHotkeyPress()
        }

        // Wire popover callbacks
        popoverViewModel.hotkeyDisplay = settingsManager.getHotkeyDisplayString()
        popoverViewModel.onStartRecording = { [weak self] in self?.startRecording() }
        popoverViewModel.onStopRecording  = { [weak self] in self?.stopRecording() }
        popoverViewModel.onOpenSettings   = { [weak self] in self?.openSettingsWindow() }
        popoverViewModel.onOpenHistory    = { [weak self] in self?.openHistoryWindow() }

        NotificationCenter.default.addObserver(
            forName: .transcriptionProviderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.handleSettingsChanged() }

        // The recorder builds a fresh engine per recording, so the new device
        // takes effect on the next one — no need to rebuild anything here.
        NotificationCenter.default.addObserver(
            forName: .inputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.audioRecorder?.preferredInputDeviceUID = self.settingsManager.inputDeviceUID
        }

        NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.refreshHotkeyConfiguration()
            self?.popoverViewModel.hotkeyDisplay = self?.settingsManager.getHotkeyDisplayString() ?? ""
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

    private func startTranscriptionProvider() {
        pendingProviderID = settingsManager.transcriptionProviderID
        loadPendingProvider()
    }

    private func loadPendingProvider() {
        guard pendingProviderID != nil, workflowTask == nil,
              state != .recording, state != .processing, state != .stopped else { return }
        state = .loading
        settingsManager.providerStatus = "Loading…"
        workflowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.workflowTask = nil }
            // One task owns switching. A newer choice is picked up on the next pass.
            while let id = self.pendingProviderID {
                self.pendingProviderID = nil
                await self.transcriptionProvider?.teardown()
                guard self.state != .stopped else { return }
                let provider = TranscriptionProviderFactory.make(id: id)
                self.transcriptionProvider = provider
                do {
                    try await provider.prepare()
                    guard self.state != .stopped else { return }
                    if self.pendingProviderID != nil { continue }
                    self.state = .ready
                    self.logger?.log("Transcription provider ready: \(provider.displayName)", level: .info)
                    self.updateProviderStatus()
                    self.notificationManager?.showAppInitializationSuccess()
                    self.menuBarIconManager?.playStartupAnimation()
                } catch {
                    guard self.state != .stopped else { return }
                    if self.pendingProviderID != nil { continue }
                    self.state = .unavailable
                    self.logger?.log("Failed to prepare transcription provider: \(error)", level: .error)
                    self.settingsManager.providerStatus = "Failed — \(error.localizedDescription)"
                    self.notificationManager?.showAppInitializationError("Failed to prepare transcription provider")
                }
            }
        }
    }

    private func renderWorkflowState() {
        popoverViewModel.isRecording = state == .recording
        popoverViewModel.canToggleRecording = state == .ready || state == .recording
        switch state {
        case .loading:
            popoverViewModel.recordingStatus = "Model loading…"
            menuBarIconManager?.setLoadingState()
        case .ready: menuBarIconManager?.setReadyState()
        case .recording: menuBarIconManager?.setRecordingState()
        case .processing:
            popoverViewModel.recordingStatus = "Transcribing…"
            menuBarIconManager?.setProcessingState()
        case .unavailable:
            popoverViewModel.recordingStatus = "Model unavailable"
            menuBarIconManager?.showErrorState(restoreReady: false)
        case .stopped:
            popoverViewModel.recordingStatus = "App stopping…"
            menuBarIconManager?.hideIcon()
        }
    }

    private func updateProviderStatus() {
        settingsManager.providerStatus = "Loaded · ~600 MB"
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
        renderWorkflowState()
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
        guard let button = statusItem?.button else { return }
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

    private func handleTranscribeHotkeyPress() {
        if state == .recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard state == .ready else {
            if state == .loading || state == .unavailable {
                notificationManager?.showTranscriptionError("Model unavailable")
            }
            return
        }

        do {
            try audioRecorder?.startRecording()
            state = .recording
            notificationManager?.showRecordingStarted()
            logger?.log("Recording started")
        } catch {
            logger?.logError(error, context: "Failed to start recording")
            notificationManager?.showTranscriptionError("Failed to start recording")
            menuBarIconManager?.showErrorState()
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        state = .processing

        guard let audioFileURL = audioRecorder?.stopRecording() else {
            state = .ready
            logger?.log("Failed to get audio file", level: .error)
            notificationManager?.showTranscriptionError("Failed to save audio file")
            menuBarIconManager?.showErrorState()
            loadPendingProvider()
            return
        }

        notificationManager?.showRecordingStopped()
        logger?.log("Audio file successfully saved to: \(audioFileURL.path)", level: .debug)
        processAudioFile(audioFileURL)
    }

    /// Some devices only hold a pinned capture format for a couple of seconds
    /// before CoreAudio forces the engine to stop (see `AudioRecorderInterruption`).
    /// The recording is already discarded by the time this fires — surface it
    /// rather than silently returning to the idle state.
    private func handleRecordingInterrupted() {
        guard state == .recording else { return }
        state = .ready
        logger?.log("Recording interrupted — device stopped unexpectedly", level: .error)
        notificationManager?.showTranscriptionError("Microphone disconnected")
        menuBarIconManager?.showErrorState()
        loadPendingProvider()
    }

    private func processAudioFile(_ audioFileURL: URL) {
        logger?.log("Starting audio file processing for: \(audioFileURL.path)", level: .info)
        workflowTask = Task { @MainActor [weak self] in
            guard let self, let provider = self.transcriptionProvider else { return }
            defer {
                self.workflowTask = nil
                self.loadPendingProvider()
            }
            do {
                let text = try await provider.transcribe(audioFileURL: audioFileURL)
                guard self.state == .processing else { return }
                self.handleTranscribedText(text, audioFileName: audioFileURL.lastPathComponent)
            } catch {
                guard self.state == .processing else { return }
                self.state = .ready
                self.logger?.logError(error, context: "Transcription failed")
                self.notificationManager?.showTranscriptionError("Transcription failed: \(error.localizedDescription)")
                self.menuBarIconManager?.showErrorState()
            }
        }
    }

    private func handleTranscribedText(_ text: String, audioFileName: String? = nil) {
        logger?.log("Handling transcribed text: \(text)", level: .info)
        HistoryManager.shared.addTranscription(text, audioFileName: audioFileName)
        pasteManager?.pasteText(text) { [weak self] success in
            DispatchQueue.main.async {
                guard let self, self.state == .processing else { return }
                self.state = .ready
                if success {
                    self.logger?.log("Text pasted at cursor successfully", level: .info)
                    self.notificationManager?.showTranscriptionSuccess()
                    self.menuBarIconManager?.showSuccessState()
                } else {
                    self.logger?.log("Failed to paste text at cursor", level: .error)
                    self.notificationManager?.showTranscriptionError("Failed to paste text at cursor")
                    self.menuBarIconManager?.showErrorState()
                }
                self.loadPendingProvider()
            }
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
        hotkeyManager?.refreshHotkeyConfiguration()
        startTranscriptionProvider()
        if state == .recording || state == .processing {
            settingsManager.providerStatus = "Switching after this transcription…"
        }
    }

    // MARK: - Cleanup
    private func cleanup() {
        let wasRecording = state == .recording
        state = .stopped
        workflowTask?.cancel()
        pendingProviderID = nil
        audioRecorder?.onInterrupted = nil
        if wasRecording { _ = audioRecorder?.stopRecording() }
        // Quit is immediate; process exit releases models without racing inference.
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
