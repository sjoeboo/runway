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
                Color(hex: 0x15161E), // black
                Color(hex: 0xF7768E), // red
                Color(hex: 0x9ECE6A), // green
                Color(hex: 0xE0AF68), // yellow
                Color(hex: 0x7AA2F7), // blue
                Color(hex: 0xBB9AF7), // magenta
                Color(hex: 0x7DCFFF), // cyan
                Color(hex: 0xA9B1D6), // white
                Color(hex: 0x414868), // bright black
                Color(hex: 0xF7768E), // bright red
                Color(hex: 0x9ECE6A), // bright green
                Color(hex: 0xE0AF68), // bright yellow
                Color(hex: 0x7AA2F7), // bright blue
                Color(hex: 0xBB9AF7), // bright magenta
                Color(hex: 0x7DCFFF), // bright cyan
                Color(hex: 0xC0CAF5), // bright white
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
                Color(hex: 0x191E2A), // black
                Color(hex: 0xFF3333), // red
                Color(hex: 0xBAE67E), // green
                Color(hex: 0xFFCC66), // yellow
                Color(hex: 0x73D0FF), // blue
                Color(hex: 0xD4BFFF), // magenta
                Color(hex: 0x95E6CB), // cyan
                Color(hex: 0xCBCCC6), // white
                Color(hex: 0x707A8C), // bright black
                Color(hex: 0xFF3333), // bright red
                Color(hex: 0xBAE67E), // bright green
                Color(hex: 0xFFD580), // bright yellow
                Color(hex: 0x73D0FF), // bright blue
                Color(hex: 0xD4BFFF), // bright magenta
                Color(hex: 0x95E6CB), // bright cyan
                Color(hex: 0xF0F0F0), // bright white
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
                Color(hex: 0x232A2E), // black
                Color(hex: 0xE67E80), // red
                Color(hex: 0xA7C080), // green
                Color(hex: 0xDBBC7F), // yellow
                Color(hex: 0x7FBBB3), // blue
                Color(hex: 0xD699B6), // magenta
                Color(hex: 0x83C092), // cyan
                Color(hex: 0xD3C6AA), // white
                Color(hex: 0x7A8478), // bright black
                Color(hex: 0xE67E80), // bright red
                Color(hex: 0xA7C080), // bright green
                Color(hex: 0xDBBC7F), // bright yellow
                Color(hex: 0x7FBBB3), // bright blue
                Color(hex: 0xD699B6), // bright magenta
                Color(hex: 0x83C092), // bright cyan
                Color(hex: 0xE3DCC4), // bright white
            ]
        )
    )

    /// All built-in themes.
    public static let builtIn: [AppTheme] = [
        .tokyoNightStorm,
        .ayuMirage,
        .everforestDark,
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
