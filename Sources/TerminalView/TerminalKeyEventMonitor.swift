import AppKit
import SwiftUI

/// Monitors keyboard events at the application level and forwards them
/// directly to the Ghostty AppTerminalView, bypassing SwiftUI's event
/// interception layer.
///
/// SwiftUI's NavigationSplitView intercepts key events before they reach
/// NSViewRepresentable views. This monitor catches ALL key events and
/// routes them to the terminal when appropriate — regardless of what
/// SwiftUI thinks the first responder is.
@MainActor
public final class TerminalKeyEventMonitor {
    public static let shared = TerminalKeyEventMonitor()

    /// Set to true when the sessions view is showing a terminal
    public var terminalIsVisible: Bool = false

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsMonitor: Any?

    private init() {}

    public func start() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleEvent(event) == true {
                return nil
            }
            return event
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if self?.handleEvent(event) == true {
                return nil
            }
            return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if self?.handleEvent(event) == true {
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

    private func handleEvent(_ event: NSEvent) -> Bool {
        guard terminalIsVisible else { return false }
        guard let window = NSApplication.shared.keyWindow else { return false }

        // Check what currently has focus
        let fr = window.firstResponder
        let frClass = fr.map { String(describing: type(of: $0)) } ?? "nil"

        // Don't steal from text fields (dialog inputs)
        if frClass.contains("TextField") || frClass.contains("FieldEditor") {
            return false
        }

        // Let Cmd+key shortcuts through to the menu system
        // EXCEPT Cmd+C (SIGINT) which the terminal needs
        if event.modifierFlags.contains(.command) && event.type == .keyDown {
            let key = event.charactersIgnoringModifiers ?? ""
            if key != "c" && !key.isEmpty {
                return false
            }
        }

        // Find the terminal view and forward the event directly
        guard let terminal = findTerminalView(in: window.contentView) else {
            return false
        }

        // Ensure the terminal is first responder (may have been stolen by SwiftUI List)
        if !(fr === terminal) {
            window.makeFirstResponder(terminal)
        }

        // Forward directly to the terminal.
        // Create a fresh event targeted at the terminal's window to ensure
        // interpretKeyEvents works correctly in the AppKit event loop.
        switch event.type {
        case .keyDown:
            terminal.keyDown(with: event)
            // For special keys (Enter, Escape, arrows, Tab), also send the
            // raw character data directly via insertText as a fallback
            if let fallback = Self.specialKeyFallback(event) {
                terminal.insertText(fallback as NSString)
            }
            return true
        case .keyUp:
            terminal.keyUp(with: event)
            return true
        case .flagsChanged:
            terminal.flagsChanged(with: event)
            return true
        default:
            return false
        }
    }

    /// Map special keys to their terminal escape sequences / characters.
    /// Used as fallback when interpretKeyEvents doesn't deliver them.
    private static func specialKeyFallback(_ event: NSEvent) -> String? {
        switch event.keyCode {
        case 36: return "\r"          // Return/Enter
        case 76: return "\r"          // Numpad Enter
        case 53: return "\u{1B}"      // Escape
        case 48: return "\t"          // Tab
        case 51: return "\u{7F}"      // Backspace (DEL)
        case 123: return "\u{1B}[D"   // Left arrow
        case 124: return "\u{1B}[C"   // Right arrow
        case 125: return "\u{1B}[B"   // Down arrow
        case 126: return "\u{1B}[A"   // Up arrow
        default: return nil
        }
    }

    private func findTerminalView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        for subview in view.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("AppTerminalView") && subview.acceptsFirstResponder {
                return subview
            }
            if let found = findTerminalView(in: subview) {
                return found
            }
        }
        return nil
    }
}
