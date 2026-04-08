import Markdown
import SwiftUI
import Theme

/// Rendering mode for markdown content.
public enum MarkdownRenderMode: Sendable {
    /// Full block-level rendering: headings, code blocks, tables, lists, etc.
    case full
    /// Inline-only rendering: bold, italic, code, links within flowing text.
    case inline
}

/// Renders a markdown string as native SwiftUI views using the app's theme.
public struct MarkdownView: View {
    let source: String
    let theme: AppTheme
    let mode: MarkdownRenderMode

    public init(source: String, theme: AppTheme, mode: MarkdownRenderMode = .full) {
        self.source = source
        self.theme = theme
        self.mode = mode
    }

    public var body: some View {
        let document = Document(parsing: source)
        switch mode {
        case .full:
            MarkdownRenderer(theme: theme).render(document)
        case .inline:
            inlineView(document)
        }
    }

    /// Inline mode: render all content as flowing text with inline formatting only.
    @ViewBuilder
    private func inlineView(_ document: Document) -> some View {
        let attributed = renderDocumentInline(document)
        Text(attributed)
            .font(.body)
            .foregroundColor(theme.chrome.text)
    }

    /// Walk all top-level children and concatenate their inline content.
    private func renderDocumentInline(_ document: Document) -> AttributedString {
        var renderer = InlineRenderer(theme: theme)
        var result = AttributedString()
        var first = true
        for child in document.children {
            if !first {
                result += AttributedString("\n")
            }
            result += renderer.visit(child)
            first = false
        }
        return result
    }
}
