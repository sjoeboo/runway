import AppKit
import GhosttyTerminal
import SwiftUI
import Theme

/// Embeds the Ghostty terminal in a child NSPanel that overlays the SwiftUI detail area.
/// This gives the terminal a real AppKit window with proper first responder and event handling,
/// completely bypassing SwiftUI's event interception.
public struct TerminalWindowView: NSViewRepresentable {
    public let config: TerminalConfig
    @Environment(\.theme) private var theme

    public init(config: TerminalConfig) {
        self.config = config
    }

    public func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.setup(config: config, theme: theme)
        return host
    }

    public func updateNSView(_ host: TerminalHostView, context: Context) {
        // Theme updates could be applied here
    }
}

/// NSView that hosts the Ghostty terminal as a subview directly (no child window).
/// The key insight: instead of using TerminalSurfaceView (SwiftUI), we create the
/// AppTerminalView (NSView) directly and add it as a subview. This keeps it in
/// the same window but gives us direct control over the view hierarchy.
public final class TerminalHostView: NSView {
    private var terminalView: NSView?  // AppTerminalView
    private var controller: TerminalController?
    private var state: TerminalViewState?

    override public var acceptsFirstResponder: Bool { true }

    func setup(config: TerminalConfig, theme: AppTheme) {
        // Create the Ghostty state
        let termConfig = buildConfig(from: theme)
        let ghosttyTheme = TerminalTheme(light: termConfig, dark: termConfig)

        let fontConfig = TerminalConfiguration(configure: { builder in
            builder.withFontFamily("SF Mono")
            builder.withFontSize(13)
            builder.withCursorStyle(.bar)
            builder.withCursorStyleBlink(true)
            if config.command != "/bin/zsh" && config.command != "/bin/bash" {
                builder.withCustom("command", config.command)
            }
        })

        let tvState = TerminalViewState(
            theme: ghosttyTheme,
            terminalConfiguration: fontConfig
        )

        tvState.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: 13,
            workingDirectory: config.workingDirectory
        )

        self.state = tvState

        // Use a hosting view for the SwiftUI TerminalSurfaceView
        let surfaceView = TerminalSurfaceView(context: tvState)
        let hosting = NSHostingView(rootView: surfaceView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // After a delay, find the actual AppTerminalView and give it focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.focusTerminal()
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.focusTerminal()
            }
        }
    }

    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focusTerminal()
    }

    private func focusTerminal() {
        guard let window else { return }
        if let terminal = findTerminal(in: self) {
            window.makeFirstResponder(terminal)
        }
    }

    private func findTerminal(in view: NSView) -> NSView? {
        for subview in view.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("AppTerminalView") {
                return subview
            }
            if let found = findTerminal(in: subview) {
                return found
            }
        }
        return nil
    }

    private func buildConfig(from theme: AppTheme) -> TerminalConfiguration {
        let palette = theme.terminal
        return TerminalConfiguration(configure: { builder in
            builder.withBackground(colorToHex(palette.background))
            builder.withForeground(colorToHex(palette.foreground))
            builder.withCursorColor(colorToHex(palette.cursor))
            builder.withSelectionBackground(colorToHex(palette.selection))
            for (index, color) in palette.ansi.enumerated() {
                builder.withPalette(index, color: colorToHex(color))
            }
        })
    }

    private func colorToHex(_ color: SwiftUI.Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
