import Foundation
import AppKit
import QuartzCore

enum MenuBarIconState {
    case startup
    case ready
    case recording
    case processing
    case transforming
    case speaking
    case success
    case error
    case hidden
}

class MenuBarIconManager: ObservableObject {
    
    // MARK: - Properties
    private let logger = Logger()
    private weak var statusItem: NSStatusItem?
    private var currentState: MenuBarIconState = .startup
    
    // MARK: - Initialization
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        logger.log("[MenuBarIconManager] Initialized", level: .debug)
        // Show a visible icon immediately so the menu bar slot is never blank
        // while the model downloads/loads on first launch.
        if let button = statusItem.button {
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "uttr"
            button.toolTip = appName
            #if DEBUG
            button.title = "D"
            button.font = .systemFont(ofSize: 9, weight: .semibold)
            button.imagePosition = .imageLeft
            #endif
            button.alphaValue = 1.0
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: appName)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        }
    }

    // MARK: - Public Methods

    /// Indicate the transcription model is still downloading or loading.
    func setLoadingState() {
        logger.log("[MenuBarIconManager] Setting loading state", level: .debug)
        transitionToIcon("ellipsis.circle", withAnimation: true)
        currentState = .processing
    }

    /// Play the startup animation sequence
    func playStartupAnimation() {
        logger.log("[MenuBarIconManager] Playing startup animation", level: .debug)
        
        guard let button = statusItem?.button else {
            logger.log("[MenuBarIconManager] Status item button not available", level: .error)
            return
        }
        
        // Start invisible
        button.alphaValue = 0.0
        currentState = .startup
        
        // Sequence: invisible → mic → mic.fill → mic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.transitionToIcon("mic", withAnimation: false)
            self.fadeInIcon()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.transitionToIcon("mic.fill", withAnimation: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.transitionToIcon("mic", withAnimation: false)
            self.currentState = .ready
        }
    }
    
    /// Transition to ready state (default mic icon)
    func setReadyState() {
        logger.log("[MenuBarIconManager] Setting ready state", level: .debug)
        transitionToIcon("mic", withAnimation: true)
        currentState = .ready
    }
    
    /// Transition to recording state.
    ///
    /// Rather than hiding uttr's icon and deferring to the macOS system mic indicator
    /// (which collapses to a stray orange dot when the menu bar is full), we keep
    /// mic.fill in place and breathe it with a slow opacity pulse. The recording state
    /// stays exactly where the user expects it, fully under the app's control.
    func setRecordingState() {
        logger.log("[MenuBarIconManager] Setting recording state — breathing pulse", level: .debug)
        transitionToIcon("mic.fill", withAnimation: false)
        currentState = .recording
        startRecordingPulse()
    }
    
    /// Show processing state after recording stops
    func setProcessingState() {
        logger.log("[MenuBarIconManager] Setting processing state", level: .debug)
        transitionToIcon("clock", withAnimation: true)
        currentState = .processing
    }
    
    /// Show transform processing state (banana yellow)
    func setTransformingState() {
        logger.log("[MenuBarIconManager] Setting transforming state", level: .debug)
        transitionToIcon("arrow.triangle.2.circlepath", withAnimation: true, tintColor: .systemYellow)
        currentState = .transforming
    }
    
    /// Show that selected text is being read aloud
    func setSpeakingState() {
        logger.log("[MenuBarIconManager] Setting speaking state", level: .debug)
        transitionToIcon("speaker.wave.2.fill", withAnimation: true)
        currentState = .speaking
    }

    /// Show success state briefly
    func showSuccessState(then restore: (() -> Void)? = nil) {
        logger.log("[MenuBarIconManager] Showing success state", level: .debug)
        transitionToIcon("checkmark.circle.fill", withAnimation: true)
        currentState = .success
        
        scheduleRestore(after: 0.8, restore)
    }
    
    /// Show that the text was left on the clipboard instead of pasted
    func showClipboardState(then restore: (() -> Void)? = nil) {
        logger.log("[MenuBarIconManager] Showing clipboard state", level: .debug)
        transitionToIcon("doc.on.clipboard.fill", withAnimation: true)
        currentState = .success

        scheduleRestore(after: 1.2, restore)
    }

    /// Show error state briefly
    func showErrorState(then restore: (() -> Void)? = nil) {
        logger.log("[MenuBarIconManager] Showing error state", level: .debug)
        transitionToIcon("exclamationmark.triangle.fill", withAnimation: true)
        currentState = .error
        
        scheduleRestore(after: 0.6, restore)
    }
    
    /// Hide the icon completely
    func hideIcon() {
        logger.log("[MenuBarIconManager] Hiding icon", level: .debug)
        fadeOutIcon {
            self.currentState = .hidden
        }
    }
    
    /// Show the icon if it was hidden
    func showIcon() {
        if currentState == .hidden {
            logger.log("[MenuBarIconManager] Showing hidden icon", level: .debug)
            fadeInIcon()
            setReadyState()
        }
    }
    
    /// One soft dip in the icon's opacity, a single breath of the recording pulse,
    /// for a hotkey that was ignored. The state and icon stay as they are.
    func nudge() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        let dip = CAKeyframeAnimation(keyPath: "opacity")
        dip.values = [1.0, 0.4, 1.0]
        dip.keyTimes = [0, 0.5, 1]
        dip.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        dip.duration = 0.4
        button.layer?.add(dip, forKey: nudgeKey)
    }

    // MARK: - Private Methods

    private let recordingPulseKey = "recordingPulse"
    private let nudgeKey = "nudge"

    /// Bumped by every icon change, so a flash's delayed restore never overrides a newer state.
    private var iconGeneration = 0

    private func scheduleRestore(after delay: TimeInterval, _ restore: (() -> Void)?) {
        let generation = iconGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.iconGeneration else { return }
            (restore ?? self.setReadyState)()
        }
    }

    private func startRecordingPulse() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        button.alphaValue = 1.0

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(pulse, forKey: recordingPulseKey)
    }

    private func stopRecordingPulse() {
        statusItem?.button?.layer?.removeAnimation(forKey: recordingPulseKey)
    }

    private func transitionToIcon(_ iconName: String, withAnimation: Bool = true, tintColor: NSColor? = nil) {
        guard let button = statusItem?.button else { return }

        // Any state change ends the recording breathe.
        stopRecordingPulse()
        iconGeneration += 1

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "uttr"
        var newImage = NSImage(systemSymbolName: iconName, accessibilityDescription: appName)?.withSymbolConfiguration(config)
        
        // Apply tint color if specified
        if let tintColor = tintColor, let image = newImage {
            newImage = image.tinted(with: tintColor)
        }
        
        if withAnimation {
            // Use NSAnimationContext for smooth macOS animations
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                // Fade out
                button.animator().alphaValue = 0.0
            }, completionHandler: {
                // Change icon
                button.image = newImage
                
                // Fade in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    button.animator().alphaValue = 1.0
                })
            })
        } else {
            button.image = newImage
        }
    }
    
    private func fadeInIcon() {
        guard let button = statusItem?.button else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.animator().alphaValue = 1.0
        })
    }
    
    private func fadeOutIcon(completion: @escaping () -> Void) {
        guard let button = statusItem?.button else {
            completion()
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.animator().alphaValue = 0.0
        }, completionHandler: completion)
    }
    
    // MARK: - Debug
    func getCurrentState() -> MenuBarIconState {
        return currentState
    }
}

// MARK: - NSImage Tinting Extension
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        
        color.set()
        
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        
        image.unlockFocus()
        image.isTemplate = false
        
        return image
    }
}
