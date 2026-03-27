import SwiftUI
import Terminal

/// A SwiftUI view wrapping a terminal emulator surface.
///
/// Phase 1: Uses a basic NSView showing PTY output as attributed text.
/// Future: Will wrap libghostty's Metal-backed NSView for GPU rendering.
public struct TerminalPane: NSViewRepresentable {
    let terminalHandle: TerminalHandle?
    let provider: (any TerminalProvider)?

    public init(terminalHandle: TerminalHandle? = nil, provider: (any TerminalProvider)? = nil) {
        self.terminalHandle = terminalHandle
        self.provider = provider
    }

    public func makeNSView(context: Context) -> NSView {
        let view = TerminalNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.14, green: 0.16, blue: 0.23, alpha: 1.0).cgColor
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // Will be connected to terminal output stream
    }
}

/// Placeholder NSView for terminal rendering.
/// Will be replaced by GhosttyTerminalView (libghostty + Metal) once integrated.
class TerminalNSView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Forward to PTY
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Placeholder: dark background
        NSColor(red: 0.14, green: 0.16, blue: 0.23, alpha: 1.0).setFill()
        dirtyRect.fill()
    }
}
