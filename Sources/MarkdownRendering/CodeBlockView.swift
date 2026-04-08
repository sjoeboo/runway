import HighlightSwift
import SwiftUI
import Theme

/// Renders a fenced code block with syntax highlighting, language label, and copy button.
struct CodeBlockView: View {
    let code: String
    let language: String?
    let theme: AppTheme

    @State private var highlighted: AttributedString?
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label bar (only if language specified)
            if let language, !language.isEmpty {
                HStack {
                    Spacer()
                    Text(language)
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                SwiftUI.Text(highlighted ?? plainAttributed)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.chrome.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if isHovering {
                copyButton
                    .padding(6)
            }
        }
        .onHover { isHovering = $0 }
        .task(id: code) {
            await highlightCode()
        }
    }

    /// Plain monospace AttributedString shown before highlighting completes.
    private var plainAttributed: AttributedString {
        var attr = AttributedString(code)
        attr.foregroundColor = theme.chrome.text
        return attr
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
                .padding(4)
                .background(theme.chrome.surface.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func highlightCode() async {
        let themeBridge = MarkdownThemeBridge(theme: theme)
        let highlight = Highlight()
        do {
            if let language, !language.isEmpty {
                highlighted = try await highlight.attributedText(
                    code, language: language, colors: themeBridge.highlightColors
                )
            } else {
                highlighted = try await highlight.attributedText(
                    code, colors: themeBridge.highlightColors
                )
            }
        } catch {
            // Keep plain text on failure — no crash, no spinner
        }
    }
}
