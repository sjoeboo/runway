import SwiftUI

// MARK: - Built-in Themes

extension AppTheme {
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

    /// Catppuccin Mocha — pastel dark theme from the Catppuccin palette.
    public static let catppuccinMocha = AppTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x1E1E2E),
            surface: Color(hex: 0x181825),
            surfaceHover: Color(hex: 0x313244),
            border: Color(hex: 0x45475A),
            text: Color(hex: 0xCDD6F4),
            textDim: Color(hex: 0xA6ADC8),
            accent: Color(hex: 0x89B4FA),
            green: Color(hex: 0xA6E3A1),
            yellow: Color(hex: 0xF9E2AF),
            red: Color(hex: 0xF38BA8),
            orange: Color(hex: 0xFAB387),
            purple: Color(hex: 0xCBA6F7),
            cyan: Color(hex: 0x94E2D5),
            comment: Color(hex: 0x6C7086)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xCDD6F4),
            background: Color(hex: 0x1E1E2E),
            cursor: Color(hex: 0xF5E0DC),
            selection: Color(hex: 0x585B70),
            ansi: [
                Color(hex: 0x45475A),  // black
                Color(hex: 0xF38BA8),  // red
                Color(hex: 0xA6E3A1),  // green
                Color(hex: 0xF9E2AF),  // yellow
                Color(hex: 0x89B4FA),  // blue
                Color(hex: 0xF5C2E7),  // magenta
                Color(hex: 0x94E2D5),  // cyan
                Color(hex: 0xBAC2DE),  // white
                Color(hex: 0x585B70),  // bright black
                Color(hex: 0xF38BA8),  // bright red
                Color(hex: 0xA6E3A1),  // bright green
                Color(hex: 0xF9E2AF),  // bright yellow
                Color(hex: 0x89B4FA),  // bright blue
                Color(hex: 0xF5C2E7),  // bright magenta
                Color(hex: 0x94E2D5),  // bright cyan
                Color(hex: 0xA6ADC8),  // bright white
            ]
        )
    )

    /// Catppuccin Latte — pastel light theme from the Catppuccin palette.
    public static let catppuccinLatte = AppTheme(
        id: "catppuccin-latte",
        name: "Catppuccin Latte",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xEFF1F5),
            surface: Color(hex: 0xE6E9EF),
            surfaceHover: Color(hex: 0xCCD0DA),
            border: Color(hex: 0xBCC0CC),
            text: Color(hex: 0x4C4F69),
            textDim: Color(hex: 0x6C6F85),
            accent: Color(hex: 0x1E66F5),
            green: Color(hex: 0x40A02B),
            yellow: Color(hex: 0xDF8E1D),
            red: Color(hex: 0xD20F39),
            orange: Color(hex: 0xFE640B),
            purple: Color(hex: 0x8839EF),
            cyan: Color(hex: 0x179299),
            comment: Color(hex: 0x9CA0B0)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x4C4F69),
            background: Color(hex: 0xEFF1F5),
            cursor: Color(hex: 0xDC8A78),
            selection: Color(hex: 0xACB0BE),
            ansi: [
                Color(hex: 0x5C5F77),  // black
                Color(hex: 0xD20F39),  // red
                Color(hex: 0x40A02B),  // green
                Color(hex: 0xDF8E1D),  // yellow
                Color(hex: 0x1E66F5),  // blue
                Color(hex: 0xEA76CB),  // magenta
                Color(hex: 0x179299),  // cyan
                Color(hex: 0xACB0BE),  // white
                Color(hex: 0x6C6F85),  // bright black
                Color(hex: 0xD20F39),  // bright red
                Color(hex: 0x40A02B),  // bright green
                Color(hex: 0xDF8E1D),  // bright yellow
                Color(hex: 0x1E66F5),  // bright blue
                Color(hex: 0xEA76CB),  // bright magenta
                Color(hex: 0x179299),  // bright cyan
                Color(hex: 0xBCC0CC),  // bright white
            ]
        )
    )

    /// Dracula — iconic purple-accented dark theme.
    public static let dracula = AppTheme(
        id: "dracula",
        name: "Dracula",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x282A36),
            surface: Color(hex: 0x343746),
            surfaceHover: Color(hex: 0x44475A),
            border: Color(hex: 0x6272A4),
            text: Color(hex: 0xF8F8F2),
            textDim: Color(hex: 0x6272A4),
            accent: Color(hex: 0xBD93F9),
            green: Color(hex: 0x50FA7B),
            yellow: Color(hex: 0xF1FA8C),
            red: Color(hex: 0xFF5555),
            orange: Color(hex: 0xFFB86C),
            purple: Color(hex: 0xBD93F9),
            cyan: Color(hex: 0x8BE9FD),
            comment: Color(hex: 0x6272A4)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xF8F8F2),
            background: Color(hex: 0x282A36),
            cursor: Color(hex: 0xF8F8F2),
            selection: Color(hex: 0x44475A),
            ansi: [
                Color(hex: 0x21222C),  // black
                Color(hex: 0xFF5555),  // red
                Color(hex: 0x50FA7B),  // green
                Color(hex: 0xF1FA8C),  // yellow
                Color(hex: 0xBD93F9),  // blue
                Color(hex: 0xFF79C6),  // magenta
                Color(hex: 0x8BE9FD),  // cyan
                Color(hex: 0xF8F8F2),  // white
                Color(hex: 0x6272A4),  // bright black
                Color(hex: 0xFF6E6E),  // bright red
                Color(hex: 0x69FF94),  // bright green
                Color(hex: 0xFFFFA5),  // bright yellow
                Color(hex: 0xD6ACFF),  // bright blue
                Color(hex: 0xFF92DF),  // bright magenta
                Color(hex: 0xA4FFFF),  // bright cyan
                Color(hex: 0xFFFFFF),  // bright white
            ]
        )
    )

    /// Dracula Alucard — light companion to Dracula, maintaining the signature palette.
    public static let draculaAlucard = AppTheme(
        id: "dracula-alucard",
        name: "Dracula Alucard",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xF8F8F2),
            surface: Color(hex: 0xECEDF4),
            surfaceHover: Color(hex: 0xE2E3ED),
            border: Color(hex: 0xD0D1DE),
            text: Color(hex: 0x282A36),
            textDim: Color(hex: 0x6272A4),
            accent: Color(hex: 0x8B6FD0),
            green: Color(hex: 0x28A745),
            yellow: Color(hex: 0xB5A400),
            red: Color(hex: 0xE23F3F),
            orange: Color(hex: 0xD08B30),
            purple: Color(hex: 0x8B6FD0),
            cyan: Color(hex: 0x1CA2C0),
            comment: Color(hex: 0x7C7F93)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x282A36),
            background: Color(hex: 0xF8F8F2),
            cursor: Color(hex: 0x282A36),
            selection: Color(hex: 0xD0D1DE),
            ansi: [
                Color(hex: 0x282A36),  // black
                Color(hex: 0xE23F3F),  // red
                Color(hex: 0x28A745),  // green
                Color(hex: 0xB5A400),  // yellow
                Color(hex: 0x8B6FD0),  // blue
                Color(hex: 0xD65BA0),  // magenta
                Color(hex: 0x1CA2C0),  // cyan
                Color(hex: 0xD0D1DE),  // white
                Color(hex: 0x6272A4),  // bright black
                Color(hex: 0xE23F3F),  // bright red
                Color(hex: 0x28A745),  // bright green
                Color(hex: 0xB5A400),  // bright yellow
                Color(hex: 0x8B6FD0),  // bright blue
                Color(hex: 0xD65BA0),  // bright magenta
                Color(hex: 0x1CA2C0),  // bright cyan
                Color(hex: 0x44475A),  // bright white
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

    /// Gruvbox Dark — retro warm dark theme with earthy tones.
    public static let gruvboxDark = AppTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x282828),
            surface: Color(hex: 0x3C3836),
            surfaceHover: Color(hex: 0x504945),
            border: Color(hex: 0x665C54),
            text: Color(hex: 0xEBDBB2),
            textDim: Color(hex: 0x928374),
            accent: Color(hex: 0xFE8019),
            green: Color(hex: 0xB8BB26),
            yellow: Color(hex: 0xFABD2F),
            red: Color(hex: 0xFB4934),
            orange: Color(hex: 0xFE8019),
            purple: Color(hex: 0xD3869B),
            cyan: Color(hex: 0x8EC07C),
            comment: Color(hex: 0x928374)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xEBDBB2),
            background: Color(hex: 0x282828),
            cursor: Color(hex: 0xEBDBB2),
            selection: Color(hex: 0x504945),
            ansi: [
                Color(hex: 0x282828),  // black
                Color(hex: 0xCC241D),  // red
                Color(hex: 0x98971A),  // green
                Color(hex: 0xD79921),  // yellow
                Color(hex: 0x458588),  // blue
                Color(hex: 0xB16286),  // magenta
                Color(hex: 0x689D6A),  // cyan
                Color(hex: 0xA89984),  // white
                Color(hex: 0x928374),  // bright black
                Color(hex: 0xFB4934),  // bright red
                Color(hex: 0xB8BB26),  // bright green
                Color(hex: 0xFABD2F),  // bright yellow
                Color(hex: 0x83A598),  // bright blue
                Color(hex: 0xD3869B),  // bright magenta
                Color(hex: 0x8EC07C),  // bright cyan
                Color(hex: 0xEBDBB2),  // bright white
            ]
        )
    )

    /// Gruvbox Light — retro warm light theme with earthy tones.
    public static let gruvboxLight = AppTheme(
        id: "gruvbox-light",
        name: "Gruvbox Light",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xFBF1C7),
            surface: Color(hex: 0xEBDBB2),
            surfaceHover: Color(hex: 0xD5C4A1),
            border: Color(hex: 0xBDAE93),
            text: Color(hex: 0x3C3836),
            textDim: Color(hex: 0x928374),
            accent: Color(hex: 0xAF3A03),
            green: Color(hex: 0x79740E),
            yellow: Color(hex: 0xB57614),
            red: Color(hex: 0x9D0006),
            orange: Color(hex: 0xAF3A03),
            purple: Color(hex: 0x8F3F71),
            cyan: Color(hex: 0x427B58),
            comment: Color(hex: 0x928374)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x3C3836),
            background: Color(hex: 0xFBF1C7),
            cursor: Color(hex: 0x3C3836),
            selection: Color(hex: 0xD5C4A1),
            ansi: [
                Color(hex: 0xFBF1C7),  // black
                Color(hex: 0xCC241D),  // red
                Color(hex: 0x98971A),  // green
                Color(hex: 0xD79921),  // yellow
                Color(hex: 0x458588),  // blue
                Color(hex: 0xB16286),  // magenta
                Color(hex: 0x689D6A),  // cyan
                Color(hex: 0x7C6F64),  // white
                Color(hex: 0x928374),  // bright black
                Color(hex: 0x9D0006),  // bright red
                Color(hex: 0x79740E),  // bright green
                Color(hex: 0xB57614),  // bright yellow
                Color(hex: 0x076678),  // bright blue
                Color(hex: 0x8F3F71),  // bright magenta
                Color(hex: 0x427B58),  // bright cyan
                Color(hex: 0x3C3836),  // bright white
            ]
        )
    )

    /// Kanagawa — dark theme inspired by Katsushika Hokusai's The Great Wave.
    public static let kanagawa = AppTheme(
        id: "kanagawa",
        name: "Kanagawa",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x1F1F28),
            surface: Color(hex: 0x2A2A37),
            surfaceHover: Color(hex: 0x363646),
            border: Color(hex: 0x54546D),
            text: Color(hex: 0xDCD7BA),
            textDim: Color(hex: 0x727169),
            accent: Color(hex: 0x7E9CD8),
            green: Color(hex: 0x98BB6C),
            yellow: Color(hex: 0xE6C384),
            red: Color(hex: 0xFF5D62),
            orange: Color(hex: 0xFFA066),
            purple: Color(hex: 0x957FB8),
            cyan: Color(hex: 0x7AA89F),
            comment: Color(hex: 0x727169)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xDCD7BA),
            background: Color(hex: 0x1F1F28),
            cursor: Color(hex: 0xC8C093),
            selection: Color(hex: 0x2D4F67),
            ansi: [
                Color(hex: 0x090618),  // black
                Color(hex: 0xC34043),  // red
                Color(hex: 0x76946A),  // green
                Color(hex: 0xC0A36E),  // yellow
                Color(hex: 0x7E9CD8),  // blue
                Color(hex: 0x957FB8),  // magenta
                Color(hex: 0x6A9589),  // cyan
                Color(hex: 0xC8C093),  // white
                Color(hex: 0x727169),  // bright black
                Color(hex: 0xE82424),  // bright red
                Color(hex: 0x98BB6C),  // bright green
                Color(hex: 0xE6C384),  // bright yellow
                Color(hex: 0x7FB4CA),  // bright blue
                Color(hex: 0x938AA9),  // bright magenta
                Color(hex: 0x7AA89F),  // bright cyan
                Color(hex: 0xDCD7BA),  // bright white
            ]
        )
    )

    /// Nord — arctic blue dark theme inspired by the polar night.
    public static let nord = AppTheme(
        id: "nord",
        name: "Nord",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x2E3440),
            surface: Color(hex: 0x3B4252),
            surfaceHover: Color(hex: 0x434C5E),
            border: Color(hex: 0x4C566A),
            text: Color(hex: 0xD8DEE9),
            textDim: Color(hex: 0x616E88),
            accent: Color(hex: 0x88C0D0),
            green: Color(hex: 0xA3BE8C),
            yellow: Color(hex: 0xEBCB8B),
            red: Color(hex: 0xBF616A),
            orange: Color(hex: 0xD08770),
            purple: Color(hex: 0xB48EAD),
            cyan: Color(hex: 0x8FBCBB),
            comment: Color(hex: 0x616E88)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xD8DEE9),
            background: Color(hex: 0x2E3440),
            cursor: Color(hex: 0xD8DEE9),
            selection: Color(hex: 0x434C5E),
            ansi: [
                Color(hex: 0x3B4252),  // black
                Color(hex: 0xBF616A),  // red
                Color(hex: 0xA3BE8C),  // green
                Color(hex: 0xEBCB8B),  // yellow
                Color(hex: 0x81A1C1),  // blue
                Color(hex: 0xB48EAD),  // magenta
                Color(hex: 0x88C0D0),  // cyan
                Color(hex: 0xE5E9F0),  // white
                Color(hex: 0x4C566A),  // bright black
                Color(hex: 0xBF616A),  // bright red
                Color(hex: 0xA3BE8C),  // bright green
                Color(hex: 0xEBCB8B),  // bright yellow
                Color(hex: 0x81A1C1),  // bright blue
                Color(hex: 0xB48EAD),  // bright magenta
                Color(hex: 0x8FBCBB),  // bright cyan
                Color(hex: 0xECEFF4),  // bright white
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

    /// Rosé Pine — elegant muted dark theme with a warm purple accent.
    public static let rosePine = AppTheme(
        id: "rose-pine",
        name: "Rosé Pine",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x191724),
            surface: Color(hex: 0x1F1D2E),
            surfaceHover: Color(hex: 0x26233A),
            border: Color(hex: 0x403D52),
            text: Color(hex: 0xE0DEF4),
            textDim: Color(hex: 0x908CAA),
            accent: Color(hex: 0xC4A7E7),
            green: Color(hex: 0x31748F),
            yellow: Color(hex: 0xF6C177),
            red: Color(hex: 0xEB6F92),
            orange: Color(hex: 0xEBBCBA),
            purple: Color(hex: 0xC4A7E7),
            cyan: Color(hex: 0x9CCFD8),
            comment: Color(hex: 0x6E6A86)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0xE0DEF4),
            background: Color(hex: 0x191724),
            cursor: Color(hex: 0x524F67),
            selection: Color(hex: 0x403D52),
            ansi: [
                Color(hex: 0x26233A),  // black
                Color(hex: 0xEB6F92),  // red
                Color(hex: 0x31748F),  // green
                Color(hex: 0xF6C177),  // yellow
                Color(hex: 0x9CCFD8),  // blue
                Color(hex: 0xC4A7E7),  // magenta
                Color(hex: 0xEBBCBA),  // cyan
                Color(hex: 0xE0DEF4),  // white
                Color(hex: 0x6E6A86),  // bright black
                Color(hex: 0xEB6F92),  // bright red
                Color(hex: 0x31748F),  // bright green
                Color(hex: 0xF6C177),  // bright yellow
                Color(hex: 0x9CCFD8),  // bright blue
                Color(hex: 0xC4A7E7),  // bright magenta
                Color(hex: 0xEBBCBA),  // bright cyan
                Color(hex: 0xE0DEF4),  // bright white
            ]
        )
    )

    /// Rosé Pine Dawn — elegant muted light theme, the daytime companion to Rosé Pine.
    public static let rosePineDawn = AppTheme(
        id: "rose-pine-dawn",
        name: "Rosé Pine Dawn",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xFAF4ED),
            surface: Color(hex: 0xFFFAF3),
            surfaceHover: Color(hex: 0xF2E9E1),
            border: Color(hex: 0xDFDAD9),
            text: Color(hex: 0x575279),
            textDim: Color(hex: 0x797593),
            accent: Color(hex: 0x907AA9),
            green: Color(hex: 0x286983),
            yellow: Color(hex: 0xEA9D34),
            red: Color(hex: 0xB4637A),
            orange: Color(hex: 0xD7827E),
            purple: Color(hex: 0x907AA9),
            cyan: Color(hex: 0x56949F),
            comment: Color(hex: 0x9893A5)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x575279),
            background: Color(hex: 0xFAF4ED),
            cursor: Color(hex: 0xCECACD),
            selection: Color(hex: 0xDFDAD9),
            ansi: [
                Color(hex: 0xF2E9E1),  // black
                Color(hex: 0xB4637A),  // red
                Color(hex: 0x286983),  // green
                Color(hex: 0xEA9D34),  // yellow
                Color(hex: 0x56949F),  // blue
                Color(hex: 0x907AA9),  // magenta
                Color(hex: 0xD7827E),  // cyan
                Color(hex: 0x575279),  // white
                Color(hex: 0x9893A5),  // bright black
                Color(hex: 0xB4637A),  // bright red
                Color(hex: 0x286983),  // bright green
                Color(hex: 0xEA9D34),  // bright yellow
                Color(hex: 0x56949F),  // bright blue
                Color(hex: 0x907AA9),  // bright magenta
                Color(hex: 0xD7827E),  // bright cyan
                Color(hex: 0x575279),  // bright white
            ]
        )
    )

    /// Solarized Dark — precision-engineered dark theme by Ethan Schoonover.
    public static let solarizedDark = AppTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        appearance: .dark,
        chrome: ChromePalette(
            background: Color(hex: 0x002B36),
            surface: Color(hex: 0x073642),
            surfaceHover: Color(hex: 0x0A4050),
            border: Color(hex: 0x586E75),
            text: Color(hex: 0x839496),
            textDim: Color(hex: 0x586E75),
            accent: Color(hex: 0x268BD2),
            green: Color(hex: 0x859900),
            yellow: Color(hex: 0xB58900),
            red: Color(hex: 0xDC322F),
            orange: Color(hex: 0xCB4B16),
            purple: Color(hex: 0x6C71C4),
            cyan: Color(hex: 0x2AA198),
            comment: Color(hex: 0x586E75)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x839496),
            background: Color(hex: 0x002B36),
            cursor: Color(hex: 0x839496),
            selection: Color(hex: 0x073642),
            ansi: [
                Color(hex: 0x073642),  // black
                Color(hex: 0xDC322F),  // red
                Color(hex: 0x859900),  // green
                Color(hex: 0xB58900),  // yellow
                Color(hex: 0x268BD2),  // blue
                Color(hex: 0xD33682),  // magenta
                Color(hex: 0x2AA198),  // cyan
                Color(hex: 0xEEE8D5),  // white
                Color(hex: 0x002B36),  // bright black
                Color(hex: 0xCB4B16),  // bright red
                Color(hex: 0x586E75),  // bright green
                Color(hex: 0x657B83),  // bright yellow
                Color(hex: 0x839496),  // bright blue
                Color(hex: 0x6C71C4),  // bright magenta
                Color(hex: 0x93A1A1),  // bright cyan
                Color(hex: 0xFDF6E3),  // bright white
            ]
        )
    )

    /// Solarized Light — precision-engineered light theme by Ethan Schoonover.
    public static let solarizedLight = AppTheme(
        id: "solarized-light",
        name: "Solarized Light",
        appearance: .light,
        chrome: ChromePalette(
            background: Color(hex: 0xFDF6E3),
            surface: Color(hex: 0xEEE8D5),
            surfaceHover: Color(hex: 0xE4DCCA),
            border: Color(hex: 0x93A1A1),
            text: Color(hex: 0x657B83),
            textDim: Color(hex: 0x93A1A1),
            accent: Color(hex: 0x268BD2),
            green: Color(hex: 0x859900),
            yellow: Color(hex: 0xB58900),
            red: Color(hex: 0xDC322F),
            orange: Color(hex: 0xCB4B16),
            purple: Color(hex: 0x6C71C4),
            cyan: Color(hex: 0x2AA198),
            comment: Color(hex: 0x93A1A1)
        ),
        terminal: TerminalPalette(
            foreground: Color(hex: 0x657B83),
            background: Color(hex: 0xFDF6E3),
            cursor: Color(hex: 0x657B83),
            selection: Color(hex: 0xEEE8D5),
            ansi: [
                Color(hex: 0x073642),  // black
                Color(hex: 0xDC322F),  // red
                Color(hex: 0x859900),  // green
                Color(hex: 0xB58900),  // yellow
                Color(hex: 0x268BD2),  // blue
                Color(hex: 0xD33682),  // magenta
                Color(hex: 0x2AA198),  // cyan
                Color(hex: 0xEEE8D5),  // white
                Color(hex: 0x002B36),  // bright black
                Color(hex: 0xCB4B16),  // bright red
                Color(hex: 0x586E75),  // bright green
                Color(hex: 0x657B83),  // bright yellow
                Color(hex: 0x839496),  // bright blue
                Color(hex: 0x6C71C4),  // bright magenta
                Color(hex: 0x93A1A1),  // bright cyan
                Color(hex: 0xFDF6E3),  // bright white
            ]
        )
    )

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

    /// All built-in themes.
    public static let builtIn: [AppTheme] = [
        .tokyoNightStorm,
        .ayuMirage,
        .catppuccinMocha,
        .catppuccinLatte,
        .dracula,
        .draculaAlucard,
        .everforestDark,
        .everforestLight,
        .gruvboxDark,
        .gruvboxLight,
        .kanagawa,
        .nord,
        .oasisLagoonDark,
        .oasisLagoonLight,
        .rosePine,
        .rosePineDawn,
        .solarizedDark,
        .solarizedLight,
    ]

    /// Paired themes for auto light/dark switching.
    public static let pairedThemes: [(dark: String, light: String)] = [
        ("catppuccin-mocha", "catppuccin-latte"),
        ("dracula", "dracula-alucard"),
        ("everforest-dark", "everforest-light"),
        ("gruvbox-dark", "gruvbox-light"),
        ("oasis-lagoon-dark", "oasis-lagoon-light"),
        ("rose-pine", "rose-pine-dawn"),
        ("solarized-dark", "solarized-light"),
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
