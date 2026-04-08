import Foundation
import Markdown
import SwiftUI
import Theme

/// Walks inline markdown nodes and produces a styled AttributedString.
///
/// Uses `inlinePresentationIntent` for bold/italic/strikethrough/code,
/// which SwiftUI's `Text(AttributedString)` renders natively.
struct InlineRenderer: MarkupVisitor {
    typealias Result = AttributedString

    let theme: AppTheme

    /// Tracks nested inline intents (bold inside italic, etc.)
    private var currentIntent: InlinePresentationIntent = []

    init(theme: AppTheme) {
        self.theme = theme
    }

    // MARK: - Default

    mutating func defaultVisit(_ markup: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result += visit(child)
        }
        return result
    }

    // MARK: - Text

    mutating func visitText(_ text: Markdown.Text) -> AttributedString {
        var attr = AttributedString(text.string)
        if !currentIntent.isEmpty {
            attr.inlinePresentationIntent = currentIntent
        }
        return attr
    }

    // MARK: - Emphasis (italic)

    mutating func visitEmphasis(_ emphasis: Emphasis) -> AttributedString {
        let saved = currentIntent
        currentIntent.insert(.emphasized)
        let result = defaultVisit(emphasis)
        currentIntent = saved
        return result
    }

    // MARK: - Strong (bold)

    mutating func visitStrong(_ strong: Strong) -> AttributedString {
        let saved = currentIntent
        currentIntent.insert(.stronglyEmphasized)
        let result = defaultVisit(strong)
        currentIntent = saved
        return result
    }

    // MARK: - Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> AttributedString {
        let saved = currentIntent
        currentIntent.insert(.strikethrough)
        let result = defaultVisit(strikethrough)
        currentIntent = saved
        return result
    }

    // MARK: - Inline Code

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> AttributedString {
        var attr = AttributedString(inlineCode.code)
        var intent = currentIntent
        intent.insert(.code)
        attr.inlinePresentationIntent = intent
        attr.font = .system(.body, design: .monospaced)
        attr.backgroundColor = theme.chrome.surface
        return attr
    }

    // MARK: - Link

    mutating func visitLink(_ link: Markdown.Link) -> AttributedString {
        var attr = defaultVisit(link)
        if let destination = link.destination, let url = URL(string: destination) {
            attr.link = url
        }
        attr.foregroundColor = theme.chrome.accent
        attr.underlineStyle = Text.LineStyle(pattern: .solid)
        return attr
    }

    // MARK: - Image (inline: render alt text)

    mutating func visitImage(_ image: Markdown.Image) -> AttributedString {
        // At inline level, render alt text. Block-level handles AsyncImage.
        let altText = image.plainText
        let display = altText.isEmpty ? "[image]" : altText
        var attr = AttributedString(display)
        attr.foregroundColor = theme.chrome.textDim
        if !currentIntent.isEmpty {
            attr.inlinePresentationIntent = currentIntent
        }
        return attr
    }

    // MARK: - Breaks

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> AttributedString {
        AttributedString(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> AttributedString {
        AttributedString("\n")
    }

    // MARK: - HTML (render as plain text)

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> AttributedString {
        AttributedString(inlineHTML.rawHTML)
    }
}
