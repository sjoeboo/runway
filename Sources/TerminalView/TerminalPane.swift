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
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13

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

            // Reapply font when settings change so existing terminals update live.
            let currentFontFamily = fontFamily
            let currentFontSize = fontSize
            if context.coordinator.lastFontFamily != currentFontFamily
                || context.coordinator.lastFontSize != currentFontSize
            {
                context.coordinator.lastFontFamily = currentFontFamily
                context.coordinator.lastFontSize = currentFontSize
                let size = CGFloat(currentFontSize)
                terminal.font =
                    NSFont(name: currentFontFamily, size: size)
                    ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            }
        }
    }

    private func createTerminal() -> LocalProcessTerminalView {
        // Start event monitors (idempotent)
        ShiftEnterMonitor.shared.start()
        MouseSelectionMonitor.shared.start()

        // Use a reasonable default frame so the PTY is forked with sane
        // dimensions (cols/rows). A .zero frame causes getWindowSize() to
        // return 0×0, making early input render vertically at 1 column.
        // Auto Layout will resize this to the real size shortly after.
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Increase scrollback from SwiftTerm's 500-line default
        terminal.changeScrollback(10_000)

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
            // Use "-shellname" as execName so the shell starts as a login shell.
            // Unix convention: argv[0] prefixed with '-' triggers login behavior,
            // which sources ~/.zprofile, ~/.zshrc login blocks, completions, etc.
            let shellBase = (shell as NSString).lastPathComponent
            terminal.startProcess(
                executable: shell,
                args: [],
                environment: env,
                execName: "-\(shellBase)"
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

    @MainActor public class Coordinator {
        var terminal: LocalProcessTerminalView?
        var lastThemeID: String?
        var lastFontFamily: String?
        var lastFontSize: Double?
    }
}

/// POSIX-safe shell escaping via single quotes.
private func shellEscape(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Mouse Selection Monitor

/// Intercepts mouse events via a local event monitor and temporarily disables
/// SwiftTerm's mouse reporting so native text selection always works.
///
/// Scroll wheel events are also monitored to ensure `allowMouseReporting` is
/// restored before any scroll — this prevents a timing race where an async
/// restore hasn't fired yet and the scroll falls to the wrong code path,
/// knocking tmux out of copy-mode.
@MainActor
class MouseSelectionMonitor {
    static let shared = MouseSelectionMonitor()
    private var monitor: Any?
    private var savedReporting = true
    private var suppressed = false

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        ) { [self] event in
            guard
                let terminal = NSApplication.shared.keyWindow?.firstResponder
                    as? LocalProcessTerminalView
            else { return event }

            // Scroll events: if we're mid-selection with reporting suppressed,
            // restore it immediately so SwiftTerm forwards the scroll to tmux.
            if event.type == .scrollWheel {
                if suppressed {
                    terminal.allowMouseReporting = savedReporting
                    suppressed = false
                }
                return event
            }

            // Mouse-up: end the suppression window.
            if event.type == .leftMouseUp {
                if suppressed {
                    // Restore after the event is dispatched so SwiftTerm's
                    // mouseUp handler still sees reporting disabled (avoids
                    // sending a spurious click to tmux).
                    DispatchQueue.main.async { [self] in
                        if suppressed {
                            terminal.allowMouseReporting = savedReporting
                            suppressed = false
                        }
                    }
                }
                return event
            }

            // Mouse-down: let the click pass through with reporting intact
            // so tmux can handle pane switching via mouse clicks.
            if event.type == .leftMouseDown {
                return event
            }

            // Mouse-drag: suppress reporting for native text selection.
            if !suppressed {
                savedReporting = terminal.allowMouseReporting
                suppressed = true
            }
            terminal.allowMouseReporting = false
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        suppressed = false
    }
}

// MARK: - Container View

/// NSView container that holds the terminal view and passes mouse events through.
/// Also registers for file drag-drop so users can drag files into the terminal.
class TerminalContainerView: NSView {
    private var terminalRef: LocalProcessTerminalView?
    override func layout() {
        super.layout()
        // Resize the terminal to match the container's real Auto Layout bounds.
        // Only send SIGWINCH (via needsLayout) when the frame actually changes —
        // re-embedding a cached terminal at the same size should be free.
        if let terminal = terminalRef,
            bounds.width > 0, bounds.height > 0,
            terminal.frame.size != bounds.size
        {
            terminal.frame = bounds
            terminal.needsLayout = true
        }
    }

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

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp"]

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        // For image drops (screenshots, image files), save a stable copy to temp.
        // macOS screenshot drags use file promises — the URL points to an ephemeral
        // TemporaryItems path that vanishes once the drag ends.
        guard let path = resolveDropPath(from: pb) else { return false }
        sendAsPaste(path)
        return true
    }

    private func resolveDropPath(from pb: NSPasteboard) -> String? {
        // Prefer raw image data — avoids ephemeral file promise paths
        if let pngData = pb.data(forType: .png) {
            return saveTempImage(pngData, ext: "png")
        }
        if let tiffData = pb.data(forType: .tiff),
            let image = NSImage(data: tiffData),
            let tiffRep = image.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiffRep),
            let pngData = bitmapRep.representation(using: .png, properties: [:])
        {
            return saveTempImage(pngData, ext: "png")
        }
        // Fall back to file URL for non-image files (or images from Finder)
        if let items = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let first = items.first {
            let ext = first.pathExtension.lowercased()
            if Self.imageExtensions.contains(ext), let data = try? Data(contentsOf: first) {
                return saveTempImage(data, ext: ext)
            }
            return first.path
        }
        return nil
    }

    private func saveTempImage(_ data: Data, ext: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "runway_drop_\(ProcessInfo.processInfo.globallyUniqueString).\(ext)"
        let url = tempDir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    private static let bracketedPasteStart: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e]  // ESC [ 200 ~
    private static let bracketedPasteEnd: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]  // ESC [ 201 ~

    private func sendAsPaste(_ text: String) {
        guard let terminal = terminalRef else { return }
        if terminal.terminal.bracketedPasteMode {
            terminal.send(data: Self.bracketedPasteStart[0...])
            terminal.send(txt: text)
            terminal.send(data: Self.bracketedPasteEnd[0...])
        } else {
            terminal.send(txt: text)
        }
    }

    func embed(_ terminal: NSView) {
        for subview in subviews { subview.removeFromSuperview() }
        if let localTerminal = terminal as? LocalProcessTerminalView {
            terminalRef = localTerminal
        }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // Hide SwiftTerm's built-in NSScroller — tmux owns scrollback,
        // so the scroller is misleading and causes users to get stuck
        // in SwiftTerm's (empty) alternate-screen buffer scroll.
        hideSwiftTermScroller(in: terminal)
    }

    private func hideSwiftTermScroller(in view: NSView) {
        for subview in view.subviews {
            if let scroller = subview as? NSScroller {
                scroller.isHidden = true
                return
            }
        }
    }
}

// MARK: - Shift+Enter Support

/// Installs a local event monitor that intercepts Shift+Enter and sends
/// the CSI u escape sequence (\e[13;2u) that Claude Code recognizes as
/// "insert newline" instead of "submit".
///
/// Uses view hierarchy traversal instead of firstResponder to find the
/// terminal — SwiftUI's NavigationSplitView intermittently steals first
/// responder, which would cause the cast to fail silently.
@MainActor
class ShiftEnterMonitor {
    static let shared = ShiftEnterMonitor()
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Shift+Enter (keyCode 36 with shift)
            if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
                guard let window = NSApplication.shared.keyWindow else { return event }
                if let terminal = Self.findTerminalView(in: window.contentView) {
                    // Restore first responder so subsequent keypresses go directly
                    if !(window.firstResponder === terminal) {
                        window.makeFirstResponder(terminal)
                    }
                    terminal.send(txt: "\u{1B}[13;2u")
                    return nil  // consumed
                }
            }
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private static func findTerminalView(in view: NSView?) -> LocalProcessTerminalView? {
        guard let view else { return nil }
        if let terminal = view as? LocalProcessTerminalView {
            return terminal
        }
        for subview in view.subviews {
            if let found = findTerminalView(in: subview) {
                return found
            }
        }
        return nil
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
