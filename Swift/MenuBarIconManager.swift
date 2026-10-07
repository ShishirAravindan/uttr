import Foundation
import AppKit
import QuartzCore

enum MenuBarIconState {
    case startup
    case ready
    case recording
    case processing
    case transforming
    case success
    case error
    case hidden
}

class MenuBarIconManager: ObservableObject {
    
    // MARK: - Properties
    private let logger = Logger()
    private weak var statusItem: NSStatusItem?
    private var currentState: MenuBarIconState = .startup
    private var stateRevision = 0
    
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
        beginState(.processing)
        transitionToIcon("ellipsis.circle", withAnimation: true)
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
        beginState(.startup)
        let revision = stateRevision
        
        // Sequence: invisible → mic → mic.fill → mic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard self.stateRevision == revision else { return }
            self.transitionToIcon("mic", withAnimation: false)
            self.fadeInIcon()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.stateRevision == revision else { return }
            self.transitionToIcon("mic.fill", withAnimation: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard self.stateRevision == revision else { return }
            self.transitionToIcon("mic", withAnimation: false)
            self.currentState = .ready
        }
    }
    
    /// Transition to ready state (default mic icon)
    func setReadyState() {
        logger.log("[MenuBarIconManager] Setting ready state", level: .debug)
        beginState(.ready)
        transitionToIcon("mic", withAnimation: true)
    }
    
    /// Transition to recording state.
    ///
    /// Rather than hiding uttr's icon and deferring to the macOS system mic indicator
    /// (which collapses to a stray orange dot when the menu bar is full), we keep
    /// mic.fill in place and breathe it with a slow opacity pulse. The recording state
    /// stays exactly where the user expects it, fully under the app's control.
    func setRecordingState() {
        logger.log("[MenuBarIconManager] Setting recording state — breathing pulse", level: .debug)
        beginState(.recording)
        transitionToIcon("mic.fill", withAnimation: false)
        startRecordingPulse()
    }
    
    /// Show processing state after recording stops
    func setProcessingState() {
        logger.log("[MenuBarIconManager] Setting processing state", level: .debug)
        beginState(.processing)
        transitionToIcon("clock", withAnimation: true)
    }
    
    /// Show transform processing state (banana yellow)
    func setTransformingState() {
        logger.log("[MenuBarIconManager] Setting transforming state", level: .debug)
        beginState(.transforming)
        transitionToIcon("arrow.triangle.2.circlepath", withAnimation: true, tintColor: .systemYellow)
    }
    
    /// Show success state briefly
    func showSuccessState() {
        logger.log("[MenuBarIconManager] Showing success state", level: .debug)
        beginState(.success)
        let revision = stateRevision
        transitionToIcon("checkmark.circle.fill", withAnimation: true)
        
        // Return to ready state after brief flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.stateRevision == revision else { return }
            self.setReadyState()
        }
    }
    
    /// Show error state briefly
    func showErrorState(restoreReady: Bool = true) {
        logger.log("[MenuBarIconManager] Showing error state", level: .debug)
        beginState(.error)
        let revision = stateRevision
        transitionToIcon("exclamationmark.triangle.fill", withAnimation: true)
        
        // Return to ready state after brief flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard restoreReady, self.stateRevision == revision else { return }
            self.setReadyState()
        }
    }
    
    /// Hide the icon completely
    func hideIcon() {
        logger.log("[MenuBarIconManager] Hiding icon", level: .debug)
        beginState(.hidden)
        fadeOutIcon()
    }
    
    /// Show the icon if it was hidden
    func showIcon() {
        if currentState == .hidden {
            logger.log("[MenuBarIconManager] Showing hidden icon", level: .debug)
            fadeInIcon()
            setReadyState()
        }
    }
    
    // MARK: - Private Methods

    private func beginState(_ state: MenuBarIconState) {
        stateRevision += 1
        currentState = state
    }

    private let recordingPulseKey = "recordingPulse"

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

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "uttr"
        var newImage = NSImage(systemSymbolName: iconName, accessibilityDescription: appName)?.withSymbolConfiguration(config)
        
        // Apply tint color if specified
        if let tintColor = tintColor, let image = newImage {
            newImage = image.tinted(with: tintColor)
        }
        
        let revision = stateRevision
        if withAnimation {
            // Use NSAnimationContext for smooth macOS animations
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                // Fade out
                button.animator().alphaValue = 0.0
            }, completionHandler: {
                guard self.stateRevision == revision else { return }
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
            button.alphaValue = 1.0
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
    
    private func fadeOutIcon() {
        guard let button = statusItem?.button else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.animator().alphaValue = 0.0
        })
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
