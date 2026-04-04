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
            // Only reapply theme when it actually changes — avoids redundant
            // installColors + needsDisplay on every unrelated state mutation.
            let themeID = theme.id
            if context.coordinator.lastThemeID != themeID {
                context.coordinator.lastThemeID = themeID
                applyTheme(terminal)
            }
        }
    }

    private func createTerminal() -> LocalProcessTerminalView {
        // Start event monitors (idempotent)
        ShiftEnterMonitor.shared.start()
        MouseSelectionMonitor.shared.start()

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
                    let escapedParts = [shellEscape(config.command)] + config.arguments.map { shellEscape($0) }
                    let fullCommand = escapedParts.joined(separator: " ")
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

    public class Coordinator {
        var terminal: LocalProcessTerminalView?
        var lastThemeID: String?
    }
}

/// POSIX-safe shell escaping via single quotes.
private func shellEscape(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Mouse Selection Monitor

/// Intercepts mouse events via a local event monitor and temporarily disables
/// SwiftTerm's mouse reporting so native text selection always works.
/// Scroll wheel events are unaffected so tmux scrollback still functions.
@MainActor
class MouseSelectionMonitor {
    static let shared = MouseSelectionMonitor()
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { event in
            if let terminal = NSApplication.shared.keyWindow?.firstResponder
                as? LocalProcessTerminalView
            {
                let saved = terminal.allowMouseReporting
                terminal.allowMouseReporting = false
                // Restore after the event is dispatched (next run loop iteration)
                DispatchQueue.main.async {
                    terminal.allowMouseReporting = saved
                }
            }
            return event
        }
    }
}

// MARK: - Container View

/// NSView container that holds the terminal view and passes mouse events through.
/// Also registers for file drag-drop so users can drag files into the terminal.
class TerminalContainerView: NSView {
    private var terminalRef: LocalProcessTerminalView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass mouse events through to the terminal subview
        if let terminal = subviews.first {
            let converted = convert(point, to: terminal)
            return terminal.hitTest(converted) ?? super.hitTest(point)
        }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        let paths = items.map { "@" + $0.path }
        terminalRef?.send(txt: paths.joined(separator: " "))
        return true
    }

    func embed(_ terminal: NSView) {
        for subview in subviews { subview.removeFromSuperview() }
        if let localTerminal = terminal as? LocalProcessTerminalView {
            terminalRef = localTerminal
        }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        registerForDraggedTypes([.fileURL])
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
