import Foundation
import CGhosttyVT

/// Swift wrapper around libghostty-vt's terminal state machine.
///
/// Provides VT100/xterm terminal emulation via Ghostty's battle-tested parser.
/// Feed PTY output in, read structured cell data out for rendering.
///
/// This does NOT render anything — it's a pure state machine. The rendering
/// is handled by SwiftTerm (current) or a future Metal renderer.
/// Primary use: buffer access for status detection (replacing hand-rolled ring buffer).
public final class GhosttyVTTerminal: @unchecked Sendable {
    private var terminal: GhosttyTerminal?
    private var renderState: GhosttyRenderState?
    private let lock = NSLock()

    public let cols: Int
    public let rows: Int

    /// Create a new Ghostty VT terminal with the given size.
    public init(cols: Int = 80, rows: Int = 24, scrollback: Int = 10000) throws {
        self.cols = cols
        self.rows = rows

        var term: GhosttyTerminal?
        let opts = GhosttyTerminalOptions(
            cols: UInt16(cols),
            rows: UInt16(rows),
            max_scrollback: scrollback
        )
        let result = ghostty_terminal_new(nil, &term, opts)
        guard result == GHOSTTY_SUCCESS, let term else {
            throw GhosttyError.initFailed
        }
        self.terminal = term

        // Create render state for reading cell data
        var rs: GhosttyRenderState?
        let rsResult = ghostty_render_state_new(nil, &rs)
        if rsResult == GHOSTTY_SUCCESS {
            self.renderState = rs
        }
    }

    deinit {
        if let terminal {
            ghostty_terminal_free(terminal)
        }
    }

    /// Feed raw PTY output data into the terminal parser.
    ///
    /// This updates the terminal's internal screen buffer, cursor position,
    /// styles, and mode flags. Call this with data read from the PTY master fd.
    public func write(_ data: Data) {
        guard let terminal else { return }
        lock.lock()
        defer { lock.unlock() }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            ghostty_terminal_vt_write(terminal, ptr, buffer.count)
        }
    }

    /// Resize the terminal.
    public func resize(cols: Int, rows: Int) {
        guard let terminal else { return }
        lock.lock()
        defer { lock.unlock() }
        _ = ghostty_terminal_resize(terminal, UInt16(cols), UInt16(rows), 0, 0)
    }

    /// Read the last N lines of the terminal screen as plain text.
    ///
    /// Used for status detection — extracts visible text from the screen buffer
    /// by iterating render state rows and cells.
    public func readLastLines(_ count: Int) -> String {
        guard let terminal, let renderState else { return "" }
        lock.lock()
        defer { lock.unlock() }

        // Update render state from terminal
        _ = ghostty_render_state_update(renderState, terminal)

        // TODO: Implement row iteration using ghostty_render_state_row_iterator_new
        // and ghostty_render_state_row_cells_get for per-cell grapheme extraction.
        // For now, this is a placeholder — status detection still uses the
        // SwiftTerm buffer via NativePTYProvider.
        return ""
    }
}

// MARK: - Errors

public enum GhosttyError: Error, LocalizedError {
    case initFailed
    case renderStateFailed

    public var errorDescription: String? {
        switch self {
        case .initFailed: "Failed to initialize Ghostty terminal"
        case .renderStateFailed: "Failed to create render state"
        }
    }
}
