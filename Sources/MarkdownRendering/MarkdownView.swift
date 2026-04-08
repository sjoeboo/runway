import SwiftUI
import Theme

/// Rendering mode for markdown content.
public enum MarkdownRenderMode {
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
        // Placeholder — will be implemented in Task 7
        Text(source)
    }
}
