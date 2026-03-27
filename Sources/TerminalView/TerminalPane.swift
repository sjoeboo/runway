import AppKit
import SwiftUI
import GhosttyTerminal
import Terminal
import Theme

/// A SwiftUI view wrapping Ghostty's Metal-accelerated terminal emulator.
///
/// Uses libghostty via the `libghostty-spm` Swift Package for GPU-rendered
/// terminal emulation with full VT100/xterm support.
public struct TerminalPane: View {
    /// Configuration for the terminal session.
    public let config: TerminalConfig

    @State private var terminalState: TerminalViewState?
    @Environment(\.theme) private var theme

    public init(config: TerminalConfig = TerminalConfig()) {
        self.config = config
    }

    public var body: some View {
        Group {
            if let state = terminalState {
                TerminalSurfaceView(context: state)
            } else {
                Color.black
            }
        }
        .onAppear { setupTerminal() }
    }

    private func setupTerminal() {
        guard terminalState == nil else { return }

        // Build Ghostty terminal configuration from our theme
        let termConfig = buildTerminalConfiguration()

        let ghosttyTheme = TerminalTheme(
            light: termConfig,
            dark: termConfig
        )

        let fontConfig = TerminalConfiguration(configure: { builder in
            builder.withFontFamily("SF Mono")
            builder.withFontSize(13)
            builder.withCursorStyle(.bar)
            builder.withCursorStyleBlink(true)

            // Set the command to run (e.g., "claude" instead of default shell)
            if config.command != "/bin/zsh" && config.command != "/bin/bash" {
                builder.withCustom("command", config.command)
            }
        })

        let state = TerminalViewState(
            theme: ghosttyTheme,
            terminalConfiguration: fontConfig
        )

        // Set working directory and command
        state.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: 13,
            workingDirectory: config.workingDirectory
        )

        terminalState = state
    }

    /// Build Ghostty terminal color configuration from our app theme.
    private func buildTerminalConfiguration() -> TerminalConfiguration {
        let palette = theme.terminal
        return TerminalConfiguration(configure: { builder in
            builder.withBackground(colorToHex(palette.background))
            builder.withForeground(colorToHex(palette.foreground))
            builder.withCursorColor(colorToHex(palette.cursor))
            builder.withSelectionBackground(colorToHex(palette.selection))

            // Map ANSI colors 0-15
            for (index, color) in palette.ansi.enumerated() {
                builder.withPalette(index, color: colorToHex(color))
            }
        })
    }

    /// Convert SwiftUI Color to hex string for Ghostty config.
    private func colorToHex(_ color: SwiftUI.Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
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
