import Foundation
import Testing

@testable import Theme

@Test func parseValidThemeFile() throws {
    let json = """
        {
            "name": "Test Theme",
            "appearance": "dark",
            "chrome": {
                "background": "#1a1b26",
                "surface": "#24283b",
                "surfaceHover": "#292e42",
                "border": "#3b4261",
                "text": "#c0caf5",
                "textDim": "#565f89",
                "accent": "#7aa2f7",
                "green": "#9ece6a",
                "yellow": "#e0af68",
                "red": "#f7768e",
                "orange": "#ff9e64",
                "purple": "#bb9af7",
                "cyan": "#7dcfff",
                "comment": "#565f89"
            },
            "terminal": {
                "foreground": "#c0caf5",
                "background": "#1a1b26",
                "cursor": "#c0caf5",
                "selection": "#33467c",
                "ansi": [
                    "#15161e", "#f7768e", "#9ece6a", "#e0af68",
                    "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                    "#414868", "#f7768e", "#9ece6a", "#e0af68",
                    "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"
                ]
            }
        }
        """
    let data = try #require(json.data(using: .utf8))
    let themeFile = try JSONDecoder().decode(ThemeFile.self, from: data)
    let theme = themeFile.toAppTheme(id: "test-theme")
    #expect(theme != nil)
    #expect(theme?.name == "Test Theme")
    #expect(theme?.id == "test-theme")
}

@Test func rejectThemeFileWithWrongAnsiCount() throws {
    let json = """
        {
            "name": "Bad",
            "appearance": "dark",
            "chrome": {
                "background": "#000", "surface": "#000", "surfaceHover": "#000",
                "border": "#000", "text": "#fff", "textDim": "#888",
                "accent": "#00f", "green": "#0f0", "yellow": "#ff0",
                "red": "#f00", "orange": "#f80", "purple": "#80f",
                "cyan": "#0ff", "comment": "#888"
            },
            "terminal": {
                "foreground": "#fff", "background": "#000",
                "cursor": "#fff", "selection": "#333",
                "ansi": ["#000", "#f00"]
            }
        }
        """
    let data = try #require(json.data(using: .utf8))
    let themeFile = try JSONDecoder().decode(ThemeFile.self, from: data)
    let theme = themeFile.toAppTheme(id: "bad")
    #expect(theme == nil)
}
