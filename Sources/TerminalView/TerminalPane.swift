import AppKit
import SwiftUI
import SwiftTerm
import Terminal
import Theme

/// A SwiftUI view wrapping SwiftTerm's LocalProcessTerminalView.
///
/// SwiftTerm is a mature terminal emulator designed for embedding in macOS apps.
/// It handles its own PTY, keyboard input, and focus management as a self-contained
/// NSView — no event monitor hacks needed.
public struct TerminalPane: NSViewRepresentable {
    public let config: TerminalConfig
    @Environment(\.theme) private var theme

    public init(config: TerminalConfig = TerminalConfig()) {
        self.config = config
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        context.coordinator.terminal = terminal

        // Font — prefer Nerd Font, fall back to system monospace
        let fontSize = CGFloat(config.fontSize ?? 13)
        let fontName = config.fontFamily ?? "MesloLGS Nerd Font"
        terminal.font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Colors from theme
        applyTheme(terminal)

        // Start the process
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let env = buildEnvironment()

        if config.command == "claude" || config.command == "/bin/zsh" || config.command == "/bin/bash" {
            // For claude or shells, start the shell and optionally send commands
            terminal.startProcess(
                executable: shell,
                args: [],
                environment: env,
                execName: nil
            )

            // If the tool is claude, send the command after shell starts
            if config.command == "claude" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    terminal.send(txt: "claude\r")
                }
            }

            // cd to working directory
            if let cwd = config.workingDirectory {
                terminal.send(txt: "cd \(shellEscape(cwd)) && clear\r")
            }
        } else {
            // Custom command — start the shell and run it
            terminal.startProcess(
                executable: shell,
                args: [],
                environment: env,
                execName: nil
            )
            if let cwd = config.workingDirectory {
                terminal.send(txt: "cd \(shellEscape(cwd)) && \(config.command)\r")
            } else {
                terminal.send(txt: "\(config.command)\r")
            }
        }

        // Request focus after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            terminal.window?.makeFirstResponder(terminal)
        }

        return terminal
    }

    public func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        // Re-apply theme colors if changed
        applyTheme(terminal)
    }

    private func applyTheme(_ terminal: LocalProcessTerminalView) {
        let palette = theme.terminal
        terminal.nativeForegroundColor = NSColor(palette.foreground)
        terminal.nativeBackgroundColor = NSColor(palette.background)
        terminal.selectedTextBackgroundColor = NSColor(palette.selection)
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        for (key, value) in config.environment {
            env[key] = value
        }

        return env.map { "\($0.key)=\($0.value)" }
    }

    private func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Coordinator

    public class Coordinator {
        var terminal: LocalProcessTerminalView?
    }
}

// MARK: - Terminal Configuration

public struct TerminalConfig: Sendable {
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]
    public let fontFamily: String?
    public let fontSize: Float?

    public init(
        command: String = "/bin/zsh",
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        fontFamily: String? = nil,
        fontSize: Float? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }
}
