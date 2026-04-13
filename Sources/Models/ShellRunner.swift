import Foundation

/// Shared utility for running shell commands without blocking the cooperative thread pool.
///
/// All actors (`PRManager`, `IssueManager`, `WorktreeManager`, `TmuxSessionManager`)
/// previously duplicated the same `Process+Pipe+waitUntilExit` pattern. This caused
/// two problems:
/// 1. Code duplication across 4 actors
/// 2. `waitUntilExit()` blocks the cooperative thread pool, starving other async work
///
/// `ShellRunner` uses `terminationHandler` + `withCheckedThrowingContinuation` to
/// release the cooperative thread while the subprocess runs.
public enum ShellRunner {

    /// Resolve the user's full PATH by running their login shell.
    ///
    /// macOS `.app` bundles launched from Finder/Dock inherit a minimal PATH
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`) from launchd. Tools installed via
    /// Homebrew, MacPorts, nix, etc. aren't on this PATH, so `/usr/bin/env tmux`
    /// (and `gh`, `claude`, etc.) fail with "No such file or directory".
    ///
    /// Call once at app startup. Uses `setenv` so all subsequent subprocess
    /// launches — both inherited-env and `ProcessInfo.processInfo.environment` —
    /// see the enriched PATH.
    public static func enrichPath() {
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        // If common Homebrew paths are already present, we're running via
        // `swift run` or the terminal — nothing to fix.
        if current.contains("/opt/homebrew/bin") || current.contains("/usr/local/bin") {
            print("[Runway] PATH already contains Homebrew dirs, skipping enrichment")
            return
        }

        print("[Runway] Enriching PATH (launchd PATH: \(current))")
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell (sources ~/.zprofile, ~/.zshenv → picks up PATH)
        process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else {
            print("[Runway] Login shell failed to launch, applying fallback PATH")
            applyFallbackPath(current)
            return
        }

        // Timeout after 1 second — most login shells resolve PATH in <500ms.
        // This blocks the main thread at launch, so keep it tight.
        let deadline = DispatchTime.now() + .seconds(1)
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: deadline) == .timedOut {
            process.terminate()
            print("[Runway] Login shell timed out after 1s, applying fallback PATH")
            applyFallbackPath(current)
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let resolved = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus == 0, !resolved.isEmpty {
            setenv("PATH", resolved, 1)
            print("[Runway] PATH enriched via login shell (\(resolved.components(separatedBy: ":").count) entries)")
        } else {
            print("[Runway] Login shell exited \(process.terminationStatus), applying fallback PATH")
            applyFallbackPath(current)
        }
    }

    private static func applyFallbackPath(_ current: String) {
        let fallback =
            "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:\(current)"
        setenv("PATH", fallback, 1)
    }

    /// Run a shell command and return its stdout output.
    ///
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/usr/bin/git", "/usr/bin/env")
    ///   - args: Command-line arguments
    ///   - cwd: Optional working directory
    ///   - env: Optional environment variables (merged with inherited environment)
    ///   - timeout: Maximum time to wait for the process to complete (default: 30s).
    ///     A hung subprocess blocks the entire calling actor, so this prevents permanent stalls.
    /// - Returns: The stdout output as a String
    /// - Throws: `ShellError.commandFailed` if the process exits with non-zero status,
    ///   or `ShellError.timeout` if the process exceeds the timeout
    @discardableResult
    public static func run(
        executable: String,
        args: [String],
        cwd: String? = nil,
        env: [String: String]? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        if let env {
            process.environment = env
        }
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Drain both pipes concurrently to prevent pipe buffer deadlocks.
        // If a child writes >64KB to stdout or stderr, it blocks until the
        // pipe is drained. Reading only after termination creates a deadlock
        // because the child can't exit until the pipe is consumed.
        async let stdoutData = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let stderrData = Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        // Use terminationHandler + continuation to avoid blocking the cooperative thread pool.
        // IMPORTANT: Set terminationHandler BEFORE process.run() to prevent a race where
        // the process exits before the handler is assigned, leaving the continuation
        // permanently unresolved and deadlocking the calling actor.
        let terminationStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }

            // Schedule a timeout that kills the process if it hasn't exited.
            // A hung subprocess (e.g., git waiting for credentials, gh DNS stall)
            // would block the entire calling actor indefinitely without this.
            let timeoutWork = DispatchWorkItem { [weak process] in
                guard let process, process.isRunning else { return }
                process.terminate()
                // Give it a moment, then force-kill
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak process] in
                    guard let process, process.isRunning else { return }
                    process.interrupt()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + Double(timeout.components.seconds),
                execute: timeoutWork
            )

            do {
                try process.run()
            } catch {
                timeoutWork.cancel()
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }

        let stdout = await stdoutData
        let stderr = await stderrData
        let output = String(data: stdout, encoding: .utf8) ?? ""

        if terminationStatus != 0 {
            let errOutput = String(data: stderr, encoding: .utf8) ?? ""
            // Distinguish timeout kills (SIGTERM = 15) from normal failures
            if terminationStatus == 15 || terminationStatus == 2 {
                throw ShellError.timeout(executable: executable, args: args)
            }
            throw ShellError.commandFailed(
                executable: executable,
                args: args,
                exitCode: terminationStatus,
                stderr: errOutput
            )
        }

        return output
    }

    /// Convenience for running `gh` commands via `/usr/bin/env gh`.
    @discardableResult
    public static func runGH(
        args: [String],
        cwd: String? = nil,
        host: String? = nil
    ) async throws -> String {
        var env = ProcessInfo.processInfo.environment
        if let host {
            env["GH_HOST"] = host
        } else {
            env.removeValue(forKey: "GH_HOST")
        }
        return try await run(
            executable: "/usr/bin/env",
            args: ["gh"] + args,
            cwd: cwd,
            env: env
        )
    }

    /// Convenience for running `git` commands.
    @discardableResult
    public static func runGit(
        in directory: String,
        args: [String]
    ) async throws -> String {
        try await run(
            executable: "/usr/bin/git",
            args: args,
            cwd: directory
        )
    }

    /// Convenience for running `tmux` commands via `/usr/bin/env tmux`.
    @discardableResult
    public static func runTmux(args: [String]) async throws -> String {
        try await run(
            executable: "/usr/bin/env",
            args: ["tmux"] + args
        )
    }
}

/// Unified error type for shell command failures.
public enum ShellError: Error, LocalizedError {
    case commandFailed(executable: String, args: [String], exitCode: Int32, stderr: String)
    case timeout(executable: String, args: [String])

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let executable, let args, let exitCode, let stderr):
            let cmd = URL(fileURLWithPath: executable).lastPathComponent
            return "\(cmd) \(args.joined(separator: " ")) failed (exit \(exitCode)): \(stderr)"
        case .timeout(let executable, let args):
            let cmd = URL(fileURLWithPath: executable).lastPathComponent
            return "\(cmd) \(args.joined(separator: " ")) timed out"
        }
    }
}
