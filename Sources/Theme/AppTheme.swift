import SwiftUI

/// A complete theme definition bundling both app chrome and terminal colors.
public struct AppTheme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let appearance: ColorScheme
    public let chrome: ChromePalette
    public let terminal: TerminalPalette

    public init(
        id: String,
        name: String,
        appearance: ColorScheme,
        chrome: ChromePalette,
        terminal: TerminalPalette
    ) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.chrome = chrome
        self.terminal = terminal
    }
}

// MARK: - Chrome Palette (App UI)

public struct ChromePalette: Sendable {
    public let background: Color
    public let surface: Color
    public let surfaceHover: Color
    public let border: Color
    public let text: Color
    public let textDim: Color
    public let accent: Color
    public let green: Color
    public let yellow: Color
    public let red: Color
    public let orange: Color
    public let purple: Color
    public let cyan: Color
    public let comment: Color

    public init(
        background: Color, surface: Color, surfaceHover: Color, border: Color,
        text: Color, textDim: Color, accent: Color,
        green: Color, yellow: Color, red: Color, orange: Color,
        purple: Color, cyan: Color, comment: Color
    ) {
        self.background = background
        self.surface = surface
        self.surfaceHover = surfaceHover
        self.border = border
        self.text = text
        self.textDim = textDim
        self.accent = accent
        self.green = green
        self.yellow = yellow
        self.red = red
        self.orange = orange
        self.purple = purple
        self.cyan = cyan
        self.comment = comment
    }
}

// MARK: - Terminal Palette (ANSI colors)

public struct TerminalPalette: Sendable {
    public let foreground: Color
    public let background: Color
    public let cursor: Color
    public let selection: Color
    /// ANSI colors 0-15 (normal 0-7, bright 8-15)
    public let ansi: [Color]

    public init(foreground: Color, background: Color, cursor: Color, selection: Color, ansi: [Color]) {
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        // Pad or truncate to exactly 16 entries to prevent crash on malformed theme JSON
        if ansi.count == 16 {
            self.ansi = ansi
        } else if ansi.count > 16 {
            self.ansi = Array(ansi.prefix(16))
        } else {
            var padded = ansi
            while padded.count < 16 { padded.append(.gray) }
            self.ansi = padded
        }
    }
}
