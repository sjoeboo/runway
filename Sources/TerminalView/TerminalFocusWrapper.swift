import AppKit
import SwiftUI

/// An invisible NSView overlay that, when clicked or when the view appears,
/// finds the Ghostty AppTerminalView in the window and makes it first responder.
///
/// This fixes keyboard input not working when Ghostty's terminal is embedded
/// in SwiftUI's NavigationSplitView, which doesn't automatically grant
/// first responder to NSView-backed views.
struct TerminalFocusView: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusHelperView {
        let view = FocusHelperView()
        return view
    }

    func updateNSView(_ nsView: FocusHelperView, context: Context) {}
}

final class FocusHelperView: NSView {
    private var didInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Delay to allow the Ghostty view to fully initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.focusTerminal()
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focusTerminal()
    }

    func focusTerminal() {
        guard let window else { return }
        // Walk the entire window's view tree to find the Ghostty terminal
        if let terminal = findTerminalView(in: window.contentView) {
            window.makeFirstResponder(terminal)
            didInitialFocus = true
        }
    }

    /// Find the Ghostty AppTerminalView by looking for an NSView that:
    /// 1. Accepts first responder
    /// 2. Has a class name containing "Terminal" (from AppTerminalView)
    /// 3. Is not a text field or other standard control
    private func findTerminalView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        for subview in view.subviews {
            let className = String(describing: type(of: subview))
            if subview.acceptsFirstResponder
                && className.contains("Terminal")
                && !(subview is NSTextField)
                && !(subview is NSButton) {
                return subview
            }
            if let found = findTerminalView(in: subview) {
                return found
            }
        }
        return nil
    }
}
