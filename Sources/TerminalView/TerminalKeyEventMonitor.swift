import AppKit
import SwiftUI
import GhosttyKit

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

        // Forward to the terminal
        switch event.type {
        case .keyDown:
            // Try normal keyDown first (works for character keys)
            terminal.keyDown(with: event)
            // For special keys, also write directly to the Ghostty surface PTY.
            // This bypasses interpretKeyEvents which doesn't work outside
            // AppKit's normal event dispatch chain.
            if let text = Self.specialKeySequence(event) {
                Self.sendDirectText(text, to: terminal)
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

    /// Send text directly to the Ghostty surface by finding the ghostty_surface_t
    /// pointer through Objective-C runtime introspection and calling the C API.
    private static func sendDirectText(_ text: String, to terminal: NSView) {
        // The AppTerminalView stores the surface pointer deep in its coordinator.
        // We use Mirror to traverse: terminal.core.surface.rawValue (ghostty_surface_t?)
        let termMirror = Mirror(reflecting: terminal)
        guard let core = termMirror.children.first(where: { $0.label == "core" })?.value else {
            print("[KeyMonitor] Could not find 'core' on terminal view")
            return
        }
        let coreMirror = Mirror(reflecting: core)
        guard let surfaceObj = coreMirror.children.first(where: { $0.label == "surface" })?.value else {
            print("[KeyMonitor] Could not find 'surface' on core")
            return
        }
        // surfaceObj is Optional<TerminalSurface>, unwrap it
        let surfMirror = Mirror(reflecting: surfaceObj)
        if surfMirror.displayStyle == .optional {
            guard let unwrapped = surfMirror.children.first?.value else {
                print("[KeyMonitor] Surface is nil")
                return
            }
            let innerMirror = Mirror(reflecting: unwrapped)
            if let rawPtr = innerMirror.children.first(where: { $0.label == "surface" })?.value {
                // rawPtr should be ghostty_surface_t? (which is an OpaquePointer?)
                if let surfacePtr = rawPtr as? UnsafeMutableRawPointer {
                    text.withCString { cStr in
                        ghostty_surface_text(surfacePtr, cStr, UInt(text.utf8.count))
                    }
                    return
                }
                // Try OpaquePointer as fallback
                if let opaquePtr = rawPtr as? OpaquePointer {
                    let ptr = UnsafeMutableRawPointer(opaquePtr)
                    text.withCString { cStr in
                        ghostty_surface_text(ptr, cStr, UInt(text.utf8.count))
                    }
                    return
                }
            }
        }
        print("[KeyMonitor] Failed to extract ghostty_surface_t pointer")
    }

    /// Map special keys to their terminal escape sequences.
    private static func specialKeySequence(_ event: NSEvent) -> String? {
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
