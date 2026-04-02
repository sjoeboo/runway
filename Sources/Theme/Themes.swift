import SwiftUI

// MARK: - Built-in Themes

extension AppTheme {
    /// Tokyo Night Storm — dark theme inspired by the VS Code Tokyo Night extension.
    public static let tokyoNightStorm = AppTheme(
        id: "tokyo-night-storm",
        name: "Tokyo Night Storm",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x24283B),
            surface: Color(hex: 0x1F2335),
            surfaceHover: Color(hex: 0x292E42),
            border: Color(hex: 0x3B4261),
            text: Color(hex: 0xC0CAF5),
            textDim: Color(hex: 0x565F89),
            accent: Color(hex: 0x7AA2F7),
            green: Color(hex: 0x9ECE6A),
            yellow: Color(hex: 0xE0AF68),
            red: Color(hex: 0xF7768E),
            orange: Color(hex: 0xFF9E64),
            purple: Color(hex: 0xBB9AF7),
            cyan: Color(hex: 0x7DCFFF),
            comment: Color(hex: 0x565F89)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xC0CAF5),
            background: Color(hex: 0x24283B),
            cursor: Color(hex: 0xC0CAF5),
            selection: Color(hex: 0x33467C),
            ansi: [
                Color(hex: 0x15161E),  // black
                Color(hex: 0xF7768E),  // red
                Color(hex: 0x9ECE6A),  // green
                Color(hex: 0xE0AF68),  // yellow
                Color(hex: 0x7AA2F7),  // blue
                Color(hex: 0xBB9AF7),  // magenta
                Color(hex: 0x7DCFFF),  // cyan
                Color(hex: 0xA9B1D6),  // white
                Color(hex: 0x414868),  // bright black
                Color(hex: 0xF7768E),  // bright red
                Color(hex: 0x9ECE6A),  // bright green
                Color(hex: 0xE0AF68),  // bright yellow
                Color(hex: 0x7AA2F7),  // bright blue
                Color(hex: 0xBB9AF7),  // bright magenta
                Color(hex: 0x7DCFFF),  // bright cyan
                Color(hex: 0xC0CAF5),  // bright white
            ]
        )
    )

    /// Ayu Mirage — warm dark theme based on the Ayu color scheme.
    public static let ayuMirage = AppTheme(
        id: "ayu-mirage",
        name: "Ayu Mirage",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x1F2430),
            surface: Color(hex: 0x232834),
            surfaceHover: Color(hex: 0x2A2F3A),
            border: Color(hex: 0x33394A),
            text: Color(hex: 0xCBCCC6),
            textDim: Color(hex: 0x707A8C),
            accent: Color(hex: 0xFFCC66),
            green: Color(hex: 0xBAE67E),
            yellow: Color(hex: 0xFFCC66),
            red: Color(hex: 0xFF3333),
            orange: Color(hex: 0xFFA759),
            purple: Color(hex: 0xD4BFFF),
            cyan: Color(hex: 0x95E6CB),
            comment: Color(hex: 0x5C6773)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xCBCCC6),
            background: Color(hex: 0x1F2430),
            cursor: Color(hex: 0xFFCC66),
            selection: Color(hex: 0x34455A),
            ansi: [
                Color(hex: 0x191E2A),  // black
                Color(hex: 0xFF3333),  // red
                Color(hex: 0xBAE67E),  // green
                Color(hex: 0xFFCC66),  // yellow
                Color(hex: 0x73D0FF),  // blue
                Color(hex: 0xD4BFFF),  // magenta
                Color(hex: 0x95E6CB),  // cyan
                Color(hex: 0xCBCCC6),  // white
                Color(hex: 0x707A8C),  // bright black
                Color(hex: 0xFF3333),  // bright red
                Color(hex: 0xBAE67E),  // bright green
                Color(hex: 0xFFD580),  // bright yellow
                Color(hex: 0x73D0FF),  // bright blue
                Color(hex: 0xD4BFFF),  // bright magenta
                Color(hex: 0x95E6CB),  // bright cyan
                Color(hex: 0xF0F0F0),  // bright white
            ]
        )
    )

    /// Everforest Dark — nature-inspired dark theme with soft green tones.
    public static let everforestDark = AppTheme(
        id: "everforest-dark",
        name: "Everforest Dark",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x2D353B),
            surface: Color(hex: 0x343F44),
            surfaceHover: Color(hex: 0x3D484D),
            border: Color(hex: 0x475258),
            text: Color(hex: 0xD3C6AA),
            textDim: Color(hex: 0x859289),
            accent: Color(hex: 0xA7C080),
            green: Color(hex: 0xA7C080),
            yellow: Color(hex: 0xDBBC7F),
            red: Color(hex: 0xE67E80),
            orange: Color(hex: 0xE69875),
            purple: Color(hex: 0xD699B6),
            cyan: Color(hex: 0x83C092),
            comment: Color(hex: 0x859289)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xD3C6AA),
            background: Color(hex: 0x2D353B),
            cursor: Color(hex: 0xD3C6AA),
            selection: Color(hex: 0x475258),
            ansi: [
                Color(hex: 0x232A2E),  // black
                Color(hex: 0xE67E80),  // red
                Color(hex: 0xA7C080),  // green
                Color(hex: 0xDBBC7F),  // yellow
                Color(hex: 0x7FBBB3),  // blue
                Color(hex: 0xD699B6),  // magenta
                Color(hex: 0x83C092),  // cyan
                Color(hex: 0xD3C6AA),  // white
                Color(hex: 0x7A8478),  // bright black
                Color(hex: 0xE67E80),  // bright red
                Color(hex: 0xA7C080),  // bright green
                Color(hex: 0xDBBC7F),  // bright yellow
                Color(hex: 0x7FBBB3),  // bright blue
                Color(hex: 0xD699B6),  // bright magenta
                Color(hex: 0x83C092),  // bright cyan
                Color(hex: 0xE3DCC4),  // bright white
            ]
        )
    )

    /// Everforest Light — nature-inspired light theme.
    public static let everforestLight = AppTheme(
        id: "everforest-light",
        name: "Everforest Light",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xFDF6E3),
            surface: Color(hex: 0xF4F0D9),
            surfaceHover: Color(hex: 0xEAE6C7),
            border: Color(hex: 0xD5CDB4),
            text: Color(hex: 0x5C6A72),
            textDim: Color(hex: 0x829181),
            accent: Color(hex: 0x8DA101),
            green: Color(hex: 0x8DA101),
            yellow: Color(hex: 0xDFA000),
            red: Color(hex: 0xF85552),
            orange: Color(hex: 0xF57D26),
            purple: Color(hex: 0xDF69BA),
            cyan: Color(hex: 0x35A77C),
            comment: Color(hex: 0x939F91)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x5C6A72),
            background: Color(hex: 0xFDF6E3),
            cursor: Color(hex: 0x5C6A72),
            selection: Color(hex: 0xE6E2CC),
            ansi: [
                Color(hex: 0x5C6A72),  // black
                Color(hex: 0xF85552),  // red
                Color(hex: 0x8DA101),  // green
                Color(hex: 0xDFA000),  // yellow
                Color(hex: 0x3A94C5),  // blue
                Color(hex: 0xDF69BA),  // magenta
                Color(hex: 0x35A77C),  // cyan
                Color(hex: 0xE0DCC7),  // white
                Color(hex: 0x829181),  // bright black
                Color(hex: 0xF85552),  // bright red
                Color(hex: 0x8DA101),  // bright green
                Color(hex: 0xDFA000),  // bright yellow
                Color(hex: 0x3A94C5),  // bright blue
                Color(hex: 0xDF69BA),  // bright magenta
                Color(hex: 0x35A77C),  // bright cyan
                Color(hex: 0x5C6A72),  // bright white
            ]
        )
    )

    /// Oasis Lagoon Dark — deep navy/blue dark theme. Ported from Hangar.
    public static let oasisLagoonDark = AppTheme(
        id: "oasis-lagoon-dark",
        name: "Oasis Lagoon Dark",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x101825),
            surface: Color(hex: 0x22385C),
            surfaceHover: Color(hex: 0x2A4570),
            border: Color(hex: 0x264870),
            text: Color(hex: 0xD9E6FA),
            textDim: Color(hex: 0x8FB0D0),
            accent: Color(hex: 0x58B8FD),
            green: Color(hex: 0x53D390),
            yellow: Color(hex: 0xF0E68C),
            red: Color(hex: 0xFF7979),
            orange: Color(hex: 0xF8B471),
            purple: Color(hex: 0xC695FF),
            cyan: Color(hex: 0x68C0B6),
            comment: Color(hex: 0x8FB0D0)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xD9E6FA),
            background: Color(hex: 0x101825),
            cursor: Color(hex: 0x58B8FD),
            selection: Color(hex: 0x264870),
            ansi: [
                Color(hex: 0x101825),  // black
                Color(hex: 0xFF7979),  // red
                Color(hex: 0x53D390),  // green
                Color(hex: 0xF0E68C),  // yellow
                Color(hex: 0x58B8FD),  // blue
                Color(hex: 0xC695FF),  // magenta
                Color(hex: 0x68C0B6),  // cyan
                Color(hex: 0xD9E6FA),  // white
                Color(hex: 0x8FB0D0),  // bright black
                Color(hex: 0xFF7979),  // bright red
                Color(hex: 0x53D390),  // bright green
                Color(hex: 0xF0E68C),  // bright yellow
                Color(hex: 0x58B8FD),  // bright blue
                Color(hex: 0xC695FF),  // bright magenta
                Color(hex: 0x68C0B6),  // bright cyan
                Color(hex: 0xD9E6FA),  // bright white
            ]
        )
    )

    /// Oasis Lagoon Light — airy blue light theme. Ported from Hangar.
    public static let oasisLagoonLight = AppTheme(
        id: "oasis-lagoon-light",
        name: "Oasis Lagoon Light",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xEEF4FF),
            surface: Color(hex: 0xD0E8FE),
            surfaceHover: Color(hex: 0xC0DEFE),
            border: Color(hex: 0xB2DCFE),
            text: Color(hex: 0x10426D),
            textDim: Color(hex: 0x1F3F71),
            accent: Color(hex: 0x1670AD),
            green: Color(hex: 0x1B491D),
            yellow: Color(hex: 0x6B2E00),
            red: Color(hex: 0x663021),
            orange: Color(hex: 0x533C00),
            purple: Color(hex: 0x46259F),
            cyan: Color(hex: 0x064658),
            comment: Color(hex: 0x1F3F71)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x10426D),
            background: Color(hex: 0xEEF4FF),
            cursor: Color(hex: 0x1670AD),
            selection: Color(hex: 0xB2DCFE),
            ansi: [
                Color(hex: 0x10426D),  // black
                Color(hex: 0x663021),  // red
                Color(hex: 0x1B491D),  // green
                Color(hex: 0x6B2E00),  // yellow
                Color(hex: 0x1670AD),  // blue
                Color(hex: 0x46259F),  // magenta
                Color(hex: 0x064658),  // cyan
                Color(hex: 0xD0E8FE),  // white
                Color(hex: 0x1F3F71),  // bright black
                Color(hex: 0x663021),  // bright red
                Color(hex: 0x1B491D),  // bright green
                Color(hex: 0x6B2E00),  // bright yellow
                Color(hex: 0x1670AD),  // bright blue
                Color(hex: 0x46259F),  // bright magenta
                Color(hex: 0x064658),  // bright cyan
                Color(hex: 0x10426D),  // bright white
            ]
        )
    )

    /// All built-in themes.
    public static let builtIn: [AppTheme] = [
        .tokyoNightStorm,
        .ayuMirage,
        .everforestDark,
        .everforestLight,
        .oasisLagoonDark,
        .oasisLagoonLight,
    ]

    /// Paired themes for auto light/dark switching.
    public static let pairedThemes: [(dark: String, light: String)] = [
        ("everforest-dark", "everforest-light"),
        ("oasis-lagoon-dark", "oasis-lagoon-light"),
    ]
}

// MARK: - Color hex initializer

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
