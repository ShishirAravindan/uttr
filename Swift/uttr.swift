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

    private var readAloud: ReadAloud?
    private var textCleanup: TextCleanup?
    private var coordinator: ActionCoordinator?

    private var isProviderReady = false

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupComponents()
        setupMenuBar()
        setupCoordinator()
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
            MainActor.assumeIsolated { self?.coordinator?.captureInterrupted() }
        }

        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        pasteManager = PasteManager()
        transcriptionProvider = TranscriptionProviderFactory.make(
            id: settingsManager.transcriptionProviderID
        )
        logger?.log("TranscriptionProvider initialized: \(settingsManager.transcriptionProviderID)", level: .debug)

        hotkeyManager?.onHotkeyEvent = { [weak self] action, phase in
            guard phase == .pressed else { return }
            let request: ActionRequest
            switch action {
            case .record: request = .toggleRecord
            case .readAloud: request = .readAloud
            case .cleanSelection: request = .instruct
            }
            MainActor.assumeIsolated { self?.coordinator?.request(request) }
        }

        // Wire popover callbacks
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

        HistoryManager.shared.setMaxEntries(settingsManager.historyMaxEntries)
        NotificationCenter.default.addObserver(
            forName: .historyMaxEntriesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            HistoryManager.shared.setMaxEntries(self.settingsManager.historyMaxEntries)
        }

        NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.refreshHotkeyConfiguration()
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
        isProviderReady = false
        settingsManager.providerStatus = "Loading…"
        menuBarIconManager?.setLoadingState()
        Task { [weak self] in
            guard let self, let provider = self.transcriptionProvider else { return }
            do {
                try await provider.prepare()
                await MainActor.run {
                    self.isProviderReady = true
                    self.logger?.log("Transcription provider ready: \(provider.displayName)", level: .info)
                    self.updateProviderStatus()
                    self.notificationManager?.showAppInitializationSuccess()
                    self.menuBarIconManager?.playStartupAnimation()
                }
            } catch {
                await MainActor.run {
                    self.logger?.log("Failed to prepare transcription provider: \(error)", level: .error)
                    self.settingsManager.providerStatus = "Failed — \(error.localizedDescription)"
                    self.notificationManager?.showAppInitializationError("Failed to prepare transcription provider")
                    self.menuBarIconManager?.showErrorState()
                }
            }
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
    }

    private func setupPopover() {
        let popoverView = MenuBarPopoverView(viewModel: popoverViewModel)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 140, height: 46)
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

    // MARK: - Actions
    private func setupCoordinator() {
        MainActor.assumeIsolated {
            guard let pasteManager, let recorder = audioRecorder,
                  let icon = menuBarIconManager, let notifications = notificationManager else { return }
            let settings = settingsManager
            let cleanup = TextCleanup(backend: CleanupBackendFactory.make())
            let instruct = SelectionCleanup(cleanup: cleanup) { settings.cleanupPrompt }
            let speech = ReadAloud()
            let reader = SelectionReader()
            textCleanup = cleanup
            readAloud = speech

            let services = ActionServices(
                providerReady: { [weak self] in self?.isProviderReady ?? false },
                startCapture: { try recorder.startRecording() },
                stopCapture: { recorder.stopRecording() },
                transcribe: { [weak self] url in
                    guard let provider = self?.transcriptionProvider else { throw CancellationError() }
                    return try await provider.transcribe(audioFileURL: url)
                },
                discardAudio: { try? FileManager.default.removeItem(at: $0) },
                dictationCleanupEnabled: { settings.cleanDictation },
                cleanDictation: { text in
                    (try? await cleanup.clean(text, instructions: settings.cleanupPrompt, profile: .dictation))
                        ?? .original(text, .failed)
                },
                accessibilityGranted: { AXIsProcessTrusted() },
                instructAvailable: { instruct.isAvailable },
                readSelection: { await reader.readSelection()?.text },
                cleanSelection: { try await instruct.clean($0) },
                speak: { speech.speak($0) },
                stopSpeech: { speech.stop() },
                frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                paste: { text, done in
                    pasteManager.pasteText(text) { success in
                        DispatchQueue.main.async { MainActor.assumeIsolated { done(success) } }
                    }
                },
                record: { record in
                    switch record {
                    case .dictation(let text, let audio, let original):
                        if let original {
                            HistoryManager.shared.add(text, kind: .dictation, audioFileName: audio, originalText: original)
                        } else {
                            HistoryManager.shared.addTranscription(text, audioFileName: audio)
                        }
                    case .cleanup(let text, let original):
                        HistoryManager.shared.add(text, kind: .cleanup, originalText: original)
                    case .readAloud(let text):
                        HistoryManager.shared.add(text, kind: .readAloud)
                    }
                },
                prepareVoice: {
                    // The system voice reads until Kokoro is ready, and keeps reading if it fails.
                    let kokoro = KokoroSpeechEngine()
                    guard await kokoro.prepare() else { return }
                    speech.useEngine(kokoro)
                }
            )

            let feedback = MenuBarFeedback(
                icon: icon,
                notifications: notifications,
                currentPhase: { [weak self] in self?.coordinator?.phase ?? .ready },
                isModelReady: { [weak self] in self?.isProviderReady ?? false },
                onModelLoading: { [weak self] in
                    self?.settingsManager.providerStatus = "Loading… (try again in a moment)"
                }
            )
            let coordinator = ActionCoordinator(services: services, feedback: feedback)
            speech.onIdle = { [weak coordinator] in coordinator?.speechEnded() }
            self.coordinator = coordinator
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
        logger?.log("Settings changed, swapping transcription provider", level: .info)
        hotkeyManager?.refreshHotkeyConfiguration()

        settingsManager.providerStatus = "Loading…"
        Task { [weak self] in
            guard let self else { return }
            await self.transcriptionProvider?.teardown()
            self.transcriptionProvider = TranscriptionProviderFactory.make(
                id: settingsManager.transcriptionProviderID
            )
            self.startTranscriptionProvider()
        }
    }

    // MARK: - Cleanup
    private func cleanup() {
        MainActor.assumeIsolated { coordinator?.shutDown() }
        Task { await transcriptionProvider?.teardown() }
        if let readAloud { Task { @MainActor in await readAloud.teardown() } }
        if let textCleanup { Task { @MainActor in await textCleanup.shutDown() } }
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
