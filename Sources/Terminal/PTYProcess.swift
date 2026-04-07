import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Size of a terminal in columns and rows.
public struct TerminalSize: Sendable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = cols
        self.rows = rows
    }
}

/// Manages a child process connected via a pseudo-terminal (PTY).
///
/// Uses `forkpty()` from Darwin to create a PTY pair and fork the child process.
/// The master file descriptor is used for reading output and writing input.
public final class PTYProcess: @unchecked Sendable {
    public let pid: pid_t
    public let masterFD: Int32
    public var isAlive: Bool {
        lock.withLock { _isAlive }
    }

    private var _isAlive: Bool = true
    private let lock = NSLock()
    private let readSource: DispatchSourceRead
    private let processSource: DispatchSourceProcess
    private let outputHandler: @Sendable (Data) -> Void
    private let exitHandler: @Sendable (Int32) -> Void

    /// Spawn a child process with a PTY.
    ///
    /// - Parameters:
    ///   - command: Executable path (e.g., "/usr/bin/claude" or result of `which claude`)
    ///   - arguments: Command-line arguments
    ///   - cwd: Working directory for the child process
    ///   - env: Environment variables (merged with inherited environment)
    ///   - size: Initial terminal size
    ///   - outputHandler: Called on background queue when output is available
    ///   - exitHandler: Called when the child process exits
    public init(
        command: String,
        arguments: [String] = [],
        cwd: URL,
        env: [String: String] = [:],
        size: TerminalSize = TerminalSize(),
        outputHandler: @escaping @Sendable (Data) -> Void,
        exitHandler: @escaping @Sendable (Int32) -> Void
    ) throws {
        self.outputHandler = outputHandler
        self.exitHandler = exitHandler

        var masterFD: Int32 = 0
        var winSize = winsize(
            ws_row: UInt16(size.rows),
            ws_col: UInt16(size.cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let pid = forkpty(&masterFD, nil, nil, &winSize)

        guard pid >= 0 else {
            throw PTYError.forkFailed(errno: errno)
        }

        if pid == 0 {
            // Child process
            if chdir(cwd.path) != 0 {
                _exit(1)
            }

            // Close inherited file descriptors (database, sockets, hook server port)
            // to prevent the child from holding parent resources open.
            // FDs 0-2 (stdin/stdout/stderr) are the PTY slave, keep those.
            let maxFD = getdtablesize()
            for fd in Int32(3)..<maxFD {
                close(fd)
            }

            // Set environment
            for (key, value) in env {
                setenv(key, value, 1)
            }
            setenv("TERM", "xterm-256color", 1)

            // Build argv
            let argv = ([command] + arguments).map { strdup($0) } + [nil]
            execvp(command, argv)

            // If execvp returns, it failed
            _exit(127)
        }

        // Parent process
        self.pid = pid
        self.masterFD = masterFD

        // Set up non-blocking read on master FD
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        let fd = masterFD

        self.readSource = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: DispatchQueue(label: "runway.pty.\(pid)", qos: .userInteractive)
        )

        // Monitor child exit via kqueue (event-driven, no thread blocked).
        // Initialized before event handlers that capture [weak self] so all
        // stored properties are set before self is referenced.
        self.processSource = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: DispatchQueue(label: "runway.pty.exit.\(pid)", qos: .utility)
        )

        self.readSource.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[..<bytesRead])
                outputHandler(data)
            } else if bytesRead <= 0 {
                self?.handleExit()
            }
        }

        self.readSource.setCancelHandler {
            close(fd)
        }

        self.processSource.setEventHandler { [weak self] in
            self?.handleExit()
            // Reap the zombie — WNOHANG because we already know it exited.
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            // WIFEXITED/WEXITSTATUS are C macros unavailable in Swift
            let exited = (status & 0x7F) == 0
            let exitCode: Int32 = exited ? (status >> 8) & 0xFF : -1
            exitHandler(exitCode)
        }

        self.readSource.resume()
        self.processSource.resume()
    }

    /// Write data to the PTY master (sends to child's stdin).
    public func write(_ data: Data) {
        guard isAlive else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            _ = Darwin.write(masterFD, ptr, buffer.count)
        }
    }

    /// Resize the PTY.
    public func resize(cols: Int, rows: Int) {
        guard isAlive else { return }
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
    }

    /// Send SIGTERM to the child process, then SIGKILL after a timeout.
    public func terminate(timeout: TimeInterval = 3.0) {
        guard isAlive else { return }
        kill(pid, SIGTERM)

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.lock.withLock({ self._isAlive }) else { return }
            kill(self.pid, SIGKILL)
        }
    }

    private func handleExit() {
        let shouldCancel = lock.withLock {
            guard _isAlive else { return false }
            _isAlive = false
            return true
        }
        if shouldCancel {
            readSource.cancel()
            processSource.cancel()
        }
    }
}

// MARK: - Errors

public enum PTYError: Error, LocalizedError {
    case forkFailed(errno: Int32)
    case commandNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .forkFailed(let errno):
            "Failed to fork PTY: \(String(cString: strerror(errno)))"
        case .commandNotFound(let cmd):
            "Command not found: \(cmd)"
        }
    }
}
