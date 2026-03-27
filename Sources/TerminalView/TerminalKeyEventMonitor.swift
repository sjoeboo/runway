import AppKit
import SwiftUI

/// Monitors keyboard events at the application level and forwards them
/// directly to the Ghostty AppTerminalView, bypassing SwiftUI's event
/// interception layer.
///
/// SwiftUI's NavigationSplitView intercepts key events before they reach
/// NSViewRepresentable views. This monitor catches events and forwards
/// them to the terminal when it's the first responder.
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
                return nil // consumed — we delivered it directly
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

    private func forwardToTerminal(_ event: NSEvent) -> Bool {
        guard let window = NSApplication.shared.keyWindow else { return false }
        guard let firstResponder = window.firstResponder as? NSView else { return false }

        let className = String(describing: type(of: firstResponder))

        // Only forward when the terminal is the first responder
        guard className.contains("AppTerminalView") else { return false }

        // Let Cmd+key shortcuts through to the menu system
        // EXCEPT Cmd+C (SIGINT) which the terminal needs
        if event.modifierFlags.contains(.command) && event.type == .keyDown {
            let key = event.charactersIgnoringModifiers ?? ""
            if key != "c" && !key.isEmpty {
                return false
            }
        }

        // Forward the event directly to the terminal view.
        // Call keyDown which triggers Ghostty's handleKeyDown → interpretKeyEvents chain.
        switch event.type {
        case .keyDown:
            firstResponder.keyDown(with: event)
            // Also trigger interpretKeyEvents for special keys (Enter, arrows, etc.)
            // This ensures the NSTextInputClient chain processes them correctly.
            firstResponder.interpretKeyEvents([event])
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
