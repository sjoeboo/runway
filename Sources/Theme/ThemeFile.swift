import Foundation
import SwiftUI

/// JSON-serializable theme format for user-installed themes in ~/.runway/themes/
public struct ThemeFile: Codable {
    let name: String
    let appearance: String  // "dark" or "light"
    let chrome: ChromeColors
    let terminal: TerminalColors

    struct ChromeColors: Codable {
        let background: String
        let surface: String
        let surfaceHover: String
        let border: String
        let text: String
        let textDim: String
        let accent: String
        let green: String
        let yellow: String
        let red: String
        let orange: String
        let purple: String
        let cyan: String
        let comment: String
    }

    struct TerminalColors: Codable {
        let foreground: String
        let background: String
        let cursor: String
        let selection: String
        let ansi: [String]  // exactly 16 hex colors
    }

    /// Convert to AppTheme. Returns nil if terminal.ansi doesn't have exactly 16 entries.
    func toAppTheme(id: String) -> AppTheme? {
        let colorScheme: ColorScheme = appearance == "light" ? .light : .dark
        guard terminal.ansi.count == 16 else { return nil }

        let chromePalette = ChromePalette(
            background: Color(hexString: chrome.background),
            surface: Color(hexString: chrome.surface),
            surfaceHover: Color(hexString: chrome.surfaceHover),
            border: Color(hexString: chrome.border),
            text: Color(hexString: chrome.text),
            textDim: Color(hexString: chrome.textDim),
            accent: Color(hexString: chrome.accent),
            green: Color(hexString: chrome.green),
            yellow: Color(hexString: chrome.yellow),
            red: Color(hexString: chrome.red),
            orange: Color(hexString: chrome.orange),
            purple: Color(hexString: chrome.purple),
            cyan: Color(hexString: chrome.cyan),
            comment: Color(hexString: chrome.comment)
        )

        let terminalPalette = TerminalPalette(
            foreground: Color(hexString: terminal.foreground),
            background: Color(hexString: terminal.background),
            cursor: Color(hexString: terminal.cursor),
            selection: Color(hexString: terminal.selection),
            ansi: terminal.ansi.map { Color(hexString: $0) }
        )

        return AppTheme(
            id: id, name: name, appearance: colorScheme,
            chrome: chromePalette, terminal: terminalPalette
        )
    }
}

extension Color {
    /// Initialize Color from a hex string like "#1a1b26", "1a1b26", or "F00" (3-digit shorthand).
    public init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        // Expand 3-digit CSS shorthand (e.g., "F00" → "FF0000")
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(hex: UInt32(value))
    }

    /// Failable hex string initializer — returns nil for malformed strings.
    /// Used by GitHub label colors that may contain unexpected values.
    public init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        self.init(hex: UInt32(int))
    }
}
