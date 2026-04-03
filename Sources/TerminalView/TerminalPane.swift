import AppKit
import SwiftTerm
import SwiftUI
import Terminal
import Theme

/// A SwiftUI view wrapping SwiftTerm's LocalProcessTerminalView.
///
/// Uses TerminalSessionCache to persist terminal sessions across view lifecycle —
/// switching tabs or navigating away doesn't kill the PTY process.
public struct TerminalPane: NSViewRepresentable {
    public let config: TerminalConfig
    public let sessionID: String
    public let tabID: String
    @Environment(\.theme) private var theme

    public init(config: TerminalConfig, sessionID: String = "", tabID: String = "") {
        self.config = config
        self.sessionID = sessionID
        self.tabID = tabID
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        // Use a container view so we can swap the terminal in/out
        let container = TerminalContainerView()

        let terminal = TerminalSessionCache.shared.terminalView(
            forSessionID: sessionID,
            tabID: tabID
        ) {
            createTerminal()
        }

        container.embed(terminal)
        context.coordinator.terminal = terminal

        // Request focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            terminal.window?.makeFirstResponder(terminal)
        }

        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let terminal = context.coordinator.terminal {
            applyTheme(terminal)
        }
    }

    private func createTerminal() -> LocalProcessTerminalView {
        // Start the Shift+Enter monitor (idempotent)
        ShiftEnterMonitor.shared.start()

        let terminal = LocalProcessTerminalView(frame: .zero)

        // Font
        let fontSize = CGFloat(config.fontSize ?? 13)
        let fontName = config.fontFamily ?? "MesloLGS Nerd Font"
        terminal.font =
            NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Colors
        applyTheme(terminal)

        let env = buildEnvironment()

        if let tmuxName = config.tmuxSessionName {
            // Attach to existing tmux session — tmux owns the process lifecycle
            terminal.startProcess(
                executable: "/usr/bin/env",
                args: ["tmux", "attach-session", "-t", tmuxName],
                environment: env,
                execName: nil
            )
        } else {
            // Fallback: direct spawn (no tmux, no persistence)
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            terminal.startProcess(
                executable: shell,
                args: [],
                environment: env,
                execName: nil
            )

            if let cwd = config.workingDirectory {
                if config.command != "/bin/zsh" && config.command != "/bin/bash"
                    && config.command != shell
                {
                    let fullCommand = ([config.command] + config.arguments).joined(separator: " ")
                    terminal.send(txt: "cd \(shellEscape(cwd)) && \(fullCommand)\r")
                } else {
                    terminal.send(txt: "cd \(shellEscape(cwd)) && clear\r")
                }
            }
        }

        return terminal
    }

    private func applyTheme(_ terminal: LocalProcessTerminalView) {
        let palette = theme.terminal
        terminal.nativeForegroundColor = NSColor(palette.foreground)
        terminal.nativeBackgroundColor = NSColor(palette.background)
        terminal.selectedTextBackgroundColor = NSColor(palette.selection)

        // Apply ANSI palette (16 colors: 0-7 normal, 8-15 bright)
        // Convert SwiftUI.Color → SwiftTerm.Color (16-bit RGB)
        let termColors = palette.ansi.map { swiftUIColor -> SwiftTerm.Color in
            let nsColor =
                NSColor(swiftUIColor).usingColorSpace(.sRGB)
                ?? NSColor(swiftUIColor)
            return SwiftTerm.Color(
                red: UInt16(nsColor.redComponent * 65535),
                green: UInt16(nsColor.greenComponent * 65535),
                blue: UInt16(nsColor.blueComponent * 65535)
            )
        }
        terminal.installColors(termColors)

        // Force redraw to apply new colors
        terminal.needsDisplay = true
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

    public class Coordinator {
        var terminal: LocalProcessTerminalView?
    }
}

// MARK: - Container View

/// Simple NSView container that holds the terminal view.
/// Ensures proper autoresizing when embedded in SwiftUI.
class TerminalContainerView: NSView {
    func embed(_ terminal: NSView) {
        // Remove previous
        for subview in subviews { subview.removeFromSuperview() }

        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

// MARK: - Shift+Enter Support

/// Installs a local event monitor that intercepts Shift+Enter and sends
/// the CSI u escape sequence (\e[13;2u) that Claude Code recognizes as
/// "insert newline" instead of "submit".
@MainActor
class ShiftEnterMonitor {
    static let shared = ShiftEnterMonitor()
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Shift+Enter (keyCode 36 with shift)
            if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
                if let terminal = NSApplication.shared.keyWindow?.firstResponder as? LocalProcessTerminalView {
                    terminal.send(txt: "\u{1B}[13;2u")
                    return nil  // consumed
                }
            }
            return event
        }
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
    public let tmuxSessionName: String?

    public init(
        command: String = "/bin/zsh",
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        fontFamily: String? = nil,
        fontSize: Float? = nil,
        tmuxSessionName: String? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.tmuxSessionName = tmuxSessionName
    }
}
