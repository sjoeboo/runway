import AppKit
import SwiftUI

/// Monitors keyboard events at the application level and forwards them
/// directly to the Ghostty AppTerminalView, bypassing SwiftUI's event
/// interception layer.
///
/// SwiftUI's NavigationSplitView and command system intercept key events
/// before they reach NSViewRepresentable views. This monitor catches
/// keyDown/keyUp/flagsChanged events and sends them to the terminal
/// when it's the intended first responder.
@MainActor
public final class TerminalKeyEventMonitor {
    public static let shared = TerminalKeyEventMonitor()

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsMonitor: Any?

    private init() {}

    public func start() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.forwardToTerminal(event) == true {
                return nil // consumed
            }
            return event
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if self?.forwardToTerminal(event) == true {
                return nil
            }
            return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if self?.forwardToTerminal(event) == true {
                return nil
            }
            return event
        }
    }

    public func stop() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        keyDownMonitor = nil
        keyUpMonitor = nil
        flagsMonitor = nil
    }

    /// Forward the event to the terminal if it's the first responder.
    /// Returns true if the event was consumed.
    private func forwardToTerminal(_ event: NSEvent) -> Bool {
        guard let window = NSApplication.shared.keyWindow,
              let firstResponder = window.firstResponder as? NSView else {
            return false
        }

        let className = String(describing: type(of: firstResponder))
        guard className.contains("AppTerminalView") else {
            return false
        }

        // Don't intercept Cmd+key combos that should go to the menu system
        // (except Cmd+C which terminal apps need for interrupt)
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers ?? ""
            // Let these through to SwiftUI menu commands
            if ["n", "p", "1", "2", "3", "q", ",", "w"].contains(key) {
                return false
            }
        }

        // Forward directly to the terminal view
        switch event.type {
        case .keyDown:
            firstResponder.keyDown(with: event)
            return true
        case .keyUp:
            firstResponder.keyUp(with: event)
            return true
        case .flagsChanged:
            firstResponder.flagsChanged(with: event)
            return true
        default:
            return false
        }
    }
}
