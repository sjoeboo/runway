import Markdown
import Theme
import XCTest

@testable import MarkdownRendering

final class InlineRendererTests: XCTestCase {
    let theme = AppTheme.tokyoNightStorm

    // MARK: - Helper

    private func renderInline(_ markdown: String) -> AttributedString {
        let document = Document(parsing: markdown)
        guard let paragraph = document.children.first(where: { $0 is Paragraph }) else {
            return AttributedString()
        }
        var renderer = InlineRenderer(theme: theme)
        return renderer.visit(paragraph)
    }

    // MARK: - Plain Text

    func testPlainText() {
        let result = renderInline("Hello world")
        XCTAssertEqual(String(result.characters), "Hello world")
    }

    // MARK: - Bold

    func testBoldText() {
        let result = renderInline("Hello **world**")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(result.characters[runs[0].range]), "Hello ")
        XCTAssertNil(runs[0].inlinePresentationIntent)
        XCTAssertEqual(String(result.characters[runs[1].range]), "world")
        XCTAssertTrue(runs[1].inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
    }

    // MARK: - Italic

    func testItalicText() {
        let result = renderInline("Hello *world*")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(result.characters[runs[0].range]), "Hello ")
        XCTAssertNil(runs[0].inlinePresentationIntent)
        XCTAssertEqual(String(result.characters[runs[1].range]), "world")
        XCTAssertTrue(runs[1].inlinePresentationIntent?.contains(.emphasized) ?? false)
    }

    // MARK: - Bold + Italic Nested

    func testBoldItalicNested() {
        let result = renderInline("***both***")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 1)
        let intent = runs[0].inlinePresentationIntent ?? []
        XCTAssertTrue(intent.contains(.stronglyEmphasized))
        XCTAssertTrue(intent.contains(.emphasized))
    }

    // MARK: - Strikethrough

    func testStrikethrough() {
        let result = renderInline("~~removed~~")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].inlinePresentationIntent?.contains(.strikethrough) ?? false)
    }

    // MARK: - Inline Code

    func testInlineCode() {
        let result = renderInline("Use `field_required` here")
        let runs = Array(result.runs)
        // "Use " + "field_required" (code) + " here"
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(String(result.characters[runs[1].range]), "field_required")
        XCTAssertTrue(runs[1].inlinePresentationIntent?.contains(.code) ?? false)
    }

    // MARK: - Link

    func testLink() {
        let result = renderInline("See [docs](https://example.com)")
        let runs = Array(result.runs)
        // "See " + "docs" (link)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(result.characters[runs[1].range]), "docs")
        XCTAssertEqual(runs[1].link, URL(string: "https://example.com"))
    }

    // MARK: - Soft Break

    func testSoftBreakRendersAsSpace() {
        let result = renderInline("hello\nworld")
        XCTAssertEqual(String(result.characters), "hello world")
    }

    // MARK: - Mixed Content

    func testMixedInlineContent() {
        let result = renderInline("Hello **bold** and *italic* with `code`")
        let text = String(result.characters)
        XCTAssertEqual(text, "Hello bold and italic with code")
    }
}
