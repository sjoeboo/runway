import Foundation

/// Represents a live tmux session discovered via `tmux list-sessions`.
public struct TmuxSession: Sendable {
    public let name: String
    public let created: Date?
    public let attached: Bool
}

/// Manages tmux sessions for terminal persistence.
///
/// Each Runway terminal session maps to a detached tmux session.
/// SwiftTerm attaches to the tmux session for display; tmux keeps
/// the process alive independently of the app lifecycle.
public actor TmuxSessionManager {

    public init() {}

    // MARK: - Public API

    /// Check if tmux is installed and available.
    public func isAvailable() async -> Bool {
        do {
            _ = try await runTmux(args: ["-V"])
            return true
        } catch {
            return false
        }
    }

    /// Create a new detached tmux session.
    ///
    /// - Parameters:
    ///   - name: Unique session name (e.g., "runway-{sessionID}")
    ///   - workDir: Working directory for the session
    ///   - command: Optional initial command to run (e.g., "claude --flags")
    ///   - env: Environment variables to set in the tmux session
    public func createSession(
        name: String,
        workDir: String,
        command: String?,
        env: [String: String]
    ) async throws {
        // Create detached session with working directory
        try await runTmux(args: ["new-session", "-d", "-s", name, "-c", workDir])

        // Set environment variables
        for (key, value) in env {
            _ = try? await runTmux(args: ["set-environment", "-t", name, key, value])
        }

        // Send initial command if provided
        if let command, !command.isEmpty {
            _ = try? await runTmux(args: ["send-keys", "-t", name, command, "Enter"])
        }
    }

    /// Check if a tmux session with the given name exists.
    public func sessionExists(name: String) async -> Bool {
        do {
            try await runTmux(args: ["has-session", "-t", name])
            return true
        } catch {
            return false
        }
    }

    /// List tmux sessions matching a prefix.
    ///
    /// - Parameter prefix: Only return sessions whose name starts with this prefix.
    ///   Defaults to "runway-" to filter out user's personal tmux sessions.
    public func listSessions(prefix: String = "runway-") async -> [TmuxSession] {
        guard let output = try? await runTmux(args: [
            "list-sessions", "-F", "#{session_name}\t#{session_created}\t#{session_attached}",
        ]) else {
            return []
        }

        return output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> TmuxSession? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 3 else { return nil }
                let name = parts[0]
                guard name.hasPrefix(prefix) else { return nil }
                let created = Double(parts[1]).map { Date(timeIntervalSince1970: $0) }
                let attached = parts[2] == "1"
                return TmuxSession(name: name, created: created, attached: attached)
            }
    }

    /// Kill a tmux session.
    public func killSession(name: String) async throws {
        try await runTmux(args: ["kill-session", "-t", name])
    }

    /// Return the executable and arguments needed to attach to a tmux session.
    ///
    /// Used by TerminalPane to start a `LocalProcessTerminalView` that
    /// attaches to the tmux session for display.
    public func attachCommand(name: String) -> (executable: String, args: [String]) {
        ("/usr/bin/env", ["tmux", "attach-session", "-t", name])
    }

    // MARK: - Private

    @discardableResult
    private func runTmux(args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux"] + args

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            throw TmuxError.commandFailed(
                args: args,
                exitCode: process.terminationStatus,
                stderr: errOutput
            )
        }

        return output
    }
}

// MARK: - Errors

public enum TmuxError: Error, LocalizedError {
    case commandFailed(args: [String], exitCode: Int32, stderr: String)
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let args, let exitCode, let stderr):
            "tmux \(args.joined(separator: " ")) failed (exit \(exitCode)): \(stderr)"
        case .notInstalled:
            "tmux is not installed. Install with: brew install tmux"
        }
    }
}
