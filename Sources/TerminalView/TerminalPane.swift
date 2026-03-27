import AppKit
import SwiftUI
import SwiftTerm
import Terminal
import Theme

/// A SwiftUI view wrapping a SwiftTerm terminal emulator.
///
/// Uses SwiftTerm's `LocalProcessTerminalView` for full VT100/xterm emulation
/// with PTY management. This is the bootstrap terminal — will be replaced by
/// libghostty (Metal GPU rendering) in a future phase.
public struct TerminalPane: NSViewRepresentable {
    /// Configuration for the terminal session.
    public let config: TerminalConfig

    @Environment(\.theme) private var theme

    public init(config: TerminalConfig = TerminalConfig()) {
        self.config = config
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.translatesAutoresizingMaskIntoConstraints = false

        // Configure appearance
        applyTheme(terminal, theme: theme)

        // Configure font
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Start the process
        let env = buildEnvironment()
        terminal.startProcess(
            executable: config.command,
            args: config.arguments,
            environment: env,
            execName: nil
        )

        if let cwd = config.workingDirectory {
            // Send cd command to set working directory
            let cdCmd = "cd \(shellEscape(cwd))\r"
            terminal.send(txt: cdCmd)
            // Clear the screen after cd so the user sees a clean terminal
            terminal.send(txt: "clear\r")
        }

        return terminal
    }

    public func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        // Re-apply theme if it changed
        applyTheme(terminal, theme: theme)
    }

    private func applyTheme(_ terminal: LocalProcessTerminalView, theme: AppTheme) {
        // Set terminal colors from theme's terminal palette
        let palette = theme.terminal
        terminal.nativeForegroundColor = nsColor(from: palette.foreground)
        terminal.nativeBackgroundColor = nsColor(from: palette.background)
        terminal.selectedTextBackgroundColor = nsColor(from: palette.selection)
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        // Add Runway session info
        for (key, value) in config.environment {
            env[key] = value
        }

        return env.map { "\($0.key)=\($0.value)" }
    }

    private func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Convert SwiftUI Color to NSColor.
    private func nsColor(from color: SwiftUI.Color) -> NSColor {
        NSColor(color)
    }
}

// MARK: - Terminal Configuration

/// Configuration for a terminal session.
public struct TerminalConfig: Sendable {
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]

    public init(
        command: String = "/bin/zsh",
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}
