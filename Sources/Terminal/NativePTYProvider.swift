import Foundation

/// A basic TerminalProvider that uses direct PTY management without a terminal emulator.
///
/// This is a fallback/bootstrap provider for initial development. It manages PTY processes
/// but does NOT provide terminal emulation (no VT parsing, no screen buffer).
/// The libghostty provider will replace this for full terminal rendering.
public actor NativePTYProvider: TerminalProvider {
    private var processes: [String: PTYProcess] = [:]
    private var buffers: [String: RingBuffer] = [:]

    public init() {}

    public func createTerminal(
        id: String,
        command: String,
        arguments: [String],
        cwd: URL,
        env: [String: String],
        size: TerminalSize
    ) async throws -> TerminalHandle {
        let buffer = RingBuffer(capacity: 100_000)
        buffers[id] = buffer

        let process = try PTYProcess(
            command: command,
            arguments: arguments,
            cwd: cwd,
            env: env,
            size: size,
            outputHandler: { data in
                buffer.append(data)
            },
            exitHandler: { _ in }
        )

        processes[id] = process
        return TerminalHandle(id: id, pid: process.pid)
    }

    public func readBuffer(terminal: TerminalHandle, lastLines: Int) async -> String {
        guard let buffer = buffers[terminal.id] else { return "" }
        let data = buffer.tail(maxBytes: lastLines * 200)
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\n")
        return lines.suffix(lastLines).joined(separator: "\n")
    }

    public func sendInput(terminal: TerminalHandle, data: Data) async {
        processes[terminal.id]?.write(data)
    }

    public func resize(terminal: TerminalHandle, size: TerminalSize) async {
        processes[terminal.id]?.resize(cols: size.cols, rows: size.rows)
    }

    public func terminate(terminal: TerminalHandle) async {
        processes[terminal.id]?.terminate()
        processes.removeValue(forKey: terminal.id)
        buffers.removeValue(forKey: terminal.id)
    }

    public func isRunning(terminal: TerminalHandle) -> Bool {
        processes[terminal.id]?.isAlive ?? false
    }
}

// MARK: - Ring Buffer

/// A simple ring buffer for accumulating terminal output bytes.
final class RingBuffer: @unchecked Sendable {
    private var data: Data
    private let capacity: Int
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.data = Data()
        self.data.reserveCapacity(capacity)
    }

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
        if data.count > capacity {
            data = data.suffix(capacity)
        }
    }

    func tail(maxBytes: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data.suffix(min(maxBytes, data.count))
    }
}
