import AppKit
import SwiftUI

/// Wraps a SwiftUI view and ensures the first NSView descendant that accepts
/// first responder gets keyboard focus when the view appears or is clicked.
///
/// This fixes the issue where Ghostty's AppTerminalView (which is an NSView
/// wrapped in NSViewRepresentable) doesn't automatically become first responder
/// when embedded in SwiftUI's NavigationSplitView.
struct TerminalFocusWrapper<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> FocusableHostingView<Content> {
        let view = FocusableHostingView(rootView: content)
        // Delay focus request to after the view hierarchy is set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            view.focusTerminalView()
        }
        return view
    }

    func updateNSView(_ nsView: FocusableHostingView<Content>, context: Context) {
        nsView.rootView = content
    }
}

/// An NSHostingView that finds and focuses the terminal NSView on click and appearance.
final class FocusableHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focusTerminalView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.focusTerminalView()
            }
        }
    }

    /// Walk the view hierarchy to find the Ghostty terminal view and make it first responder.
    func focusTerminalView() {
        guard let window else { return }
        if let terminalView = findFirstResponderCandidate(in: self) {
            window.makeFirstResponder(terminalView)
        }
    }

    /// Recursively search for the first NSView that accepts first responder
    /// and isn't this hosting view itself (we want the terminal, not the wrapper).
    private func findFirstResponderCandidate(in view: NSView) -> NSView? {
        for subview in view.subviews {
            // Look for the Ghostty AppTerminalView by checking if it accepts first responder
            // and has a Metal layer (CAMetalLayer)
            if subview !== self && subview.acceptsFirstResponder && subview.layer is CAMetalLayer {
                return subview
            }
            if let found = findFirstResponderCandidate(in: subview) {
                return found
            }
        }
        return nil
    }
}
