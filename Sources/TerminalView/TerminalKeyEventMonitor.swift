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

        // Monitor key events to ensure the terminal stays focused.
        // We DON'T consume events — we just ensure the first responder
        // is restored to the terminal if something stole it.
        // AppKit delivers key events to the first responder naturally.
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.ensureTerminalFocus(for: event)
            return event // pass through — let AppKit deliver normally
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
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

    /// Ensure the terminal has focus when a key event arrives.
    /// If something stole focus (e.g., SwiftUI sidebar), restore it.
    private func ensureTerminalFocus(for event: NSEvent) {
        guard let window = NSApplication.shared.keyWindow else { return }

        let fr = window.firstResponder
        let frClass = fr.map { String(describing: type(of: $0)) } ?? "nil"

        // Already focused on terminal — nothing to do
        if frClass.contains("AppTerminalView") {
            return
        }

        // If focus is on a text field (dialog input), don't steal it
        if frClass.contains("TextField") || frClass.contains("FieldEditor") {
            return
        }

        // Focus was lost to something else — try to restore to terminal
        if let contentView = window.contentView {
            if let terminal = findTerminalView(in: contentView) {
                print("[KeyMonitor] Restoring focus from \(frClass) to terminal")
                window.makeFirstResponder(terminal)
            }
        }
    }

    private func findTerminalView(in view: NSView) -> NSView? {
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
