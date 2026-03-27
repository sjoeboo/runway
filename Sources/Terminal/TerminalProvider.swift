import Foundation

/// Size of a terminal in columns and rows.
public struct TerminalSize: Sendable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = cols
        self.rows = rows
    }
}

/// Opaque handle to a managed terminal session (PTY + emulator state).
public final class TerminalHandle: Identifiable, Sendable {
    public let id: String
    public let pid: Int32

    public init(id: String, pid: Int32) {
        self.id = id
        self.pid = pid
    }
}

/// Protocol abstracting the terminal emulator backend.
///
/// Implementations can use libghostty (GPU, Metal) or SwiftTerm (CPU, AppKit)
/// without affecting the rest of the application.
/// All methods are async to support actor-isolated implementations.
public protocol TerminalProvider: Sendable {
    /// Create a new terminal running the given command.
    func createTerminal(
        id: String,
        command: String,
        arguments: [String],
        cwd: URL,
        env: [String: String],
        size: TerminalSize
    ) async throws -> TerminalHandle

    /// Read the last N lines from the terminal's screen buffer.
    func readBuffer(terminal: TerminalHandle, lastLines: Int) async -> String

    /// Write input data to the terminal's PTY.
    func sendInput(terminal: TerminalHandle, data: Data) async

    /// Resize the terminal.
    func resize(terminal: TerminalHandle, size: TerminalSize) async

    /// Terminate the terminal's child process.
    func terminate(terminal: TerminalHandle) async

    /// Check if the terminal's child process is still running.
    func isRunning(terminal: TerminalHandle) async -> Bool
}
