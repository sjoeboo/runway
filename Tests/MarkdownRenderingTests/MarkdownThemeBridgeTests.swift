import HighlightSwift
import Theme
import XCTest

@testable import MarkdownRendering

final class MarkdownThemeBridgeTests: XCTestCase {
    func testDarkThemeUsesTokyoNight() {
        let bridge = MarkdownThemeBridge(theme: .tokyoNightStorm)
        XCTAssertEqual(bridge.highlightColors, .dark(.tokyoNight))
    }

    func testCodeTextColorsUseTokyoNightDarkAndGithubLight() {
        let bridge = MarkdownThemeBridge(theme: .tokyoNightStorm)
        let colors = bridge.codeTextColors
        let expected = CodeTextColors.custom(
            dark: .dark(.tokyoNight),
            light: .light(.github)
        )
        XCTAssertEqual(colors, expected)
    }
}
