import Foundation
import Models

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
        // Build a single tmux command chain using \; separators to minimize subprocess spawns.
        // Previously this was 4-6 sequential process calls; now it's 1 (+ optional send-keys).
        var args = [
            "new-session", "-d", "-s", name, "-c", workDir,
        ]

        // Pass environment variables directly via -e flags (tmux 3.2+)
        for (key, value) in env {
            args += ["-e", "\(key)=\(value)"]
        }

        // Chain option settings via \; separator
        args += [
            ";", "set-option", "-t", name, "status", "off",
            ";", "set-option", "-t", name, "mouse", "on",
            ";", "set-option", "-t", name, "history-limit", "50000",
            // Enable CSI u (extended keys) so modifiers like Shift+Enter
            // pass through to the application inside tmux (e.g., Claude Code
            // recognises \e[13;2u as "insert newline" rather than "submit").
            ";", "set-option", "-t", name, "extended-keys", "on",
        ]

        try await runTmux(args: args)

        // Send initial command if provided (separate call since send-keys
        // with \; can be fragile if the command itself contains semicolons)
        if let command, !command.isEmpty {
            // Use -l for literal text (no tmux key-name interpretation),
            // then send Enter separately as a key name.
            _ = try? await runTmux(args: ["send-keys", "-t", name, "-l", command])
            _ = try? await runTmux(args: ["send-keys", "-t", name, "Enter"])
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
        guard
            let output = try? await runTmux(args: [
                "list-sessions", "-F", "#{session_name}\t#{session_created}\t#{session_attached}",
            ])
        else {
            return []
        }

        return
            output
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

    /// Send text to a tmux session without pressing Enter.
    /// Used to pre-fill terminal input (e.g., initial review prompt).
    public func sendText(sessionName: String, text: String) async throws {
        // send-keys -l sends literal text (no key interpretation)
        try await runTmux(args: ["send-keys", "-t", sessionName, "-l", text])
    }

    /// Split the current pane in a tmux session.
    ///
    /// - Parameters:
    ///   - sessionName: The tmux session to split a pane in.
    ///   - direction: `.horizontal` splits top/bottom, `.vertical` splits left/right.
    public func splitWindow(sessionName: String, direction: TmuxSplitDirection) async throws {
        try await runTmux(args: [
            "split-window", direction.flag, "-t", sessionName,
        ])
    }

    // MARK: - Private

    @discardableResult
    private func runTmux(args: [String]) async throws -> String {
        try await ShellRunner.runTmux(args: args)
    }
}

// MARK: - Split Direction

/// Direction for splitting a tmux pane.
public enum TmuxSplitDirection: Sendable {
    /// Split left/right (vertical divider).
    case vertical
    /// Split top/bottom (horizontal divider).
    case horizontal

    var flag: String {
        switch self {
        case .vertical: "-h"
        case .horizontal: "-v"
        }
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
