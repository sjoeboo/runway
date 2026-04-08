import Markdown
import SwiftUI
import Theme

/// Walks a parsed markdown Document and renders block-level elements as SwiftUI views.
@MainActor
struct MarkdownRenderer {
    let theme: AppTheme

    // MARK: - Document

    @ViewBuilder
    func render(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                AnyView(renderBlock(child))
            }
        }
    }

    // MARK: - Block Dispatch

    @ViewBuilder
    func renderBlock(_ markup: any Markup) -> some View {
        if let heading = markup as? Heading {
            renderHeading(heading)
        } else if let paragraph = markup as? Paragraph {
            renderParagraph(paragraph)
        } else if let codeBlock = markup as? CodeBlock {
            CodeBlockView(
                code: codeBlock.code.trimmingCharacters(in: .newlines),
                language: codeBlock.language,
                theme: theme
            )
        } else if let blockQuote = markup as? BlockQuote {
            renderBlockQuote(blockQuote)
        } else if let orderedList = markup as? OrderedList {
            renderOrderedList(orderedList)
        } else if let unorderedList = markup as? UnorderedList {
            renderUnorderedList(unorderedList)
        } else if let table = markup as? Markdown.Table {
            TableView(table: table, theme: theme)
        } else if markup is ThematicBreak {
            Divider()
                .background(theme.chrome.border)
                .padding(.vertical, 4)
        } else if let htmlBlock = markup as? HTMLBlock {
            SwiftUI.Text(htmlBlock.rawHTML)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(theme.chrome.textDim)
        } else {
            // Fallback: recurse into children
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(markup.children.enumerated()), id: \.offset) { _, child in
                    AnyView(renderBlock(child))
                }
            }
        }
    }

    // MARK: - Heading

    @ViewBuilder
    private func renderHeading(_ heading: Heading) -> some View {
        SwiftUI.Text(renderInline(heading))
            .font(headingFont(heading.level))
            .foregroundColor(theme.chrome.text)
            .fontWeight(.semibold)
            .padding(.top, heading.level <= 2 ? 4 : 2)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        case 4: .headline
        case 5: .subheadline
        default: .callout
        }
    }

    // MARK: - Paragraph

    @ViewBuilder
    private func renderParagraph(_ paragraph: Paragraph) -> some View {
        // Check for standalone image by walking children explicitly
        if paragraph.childCount == 1, let image = standaloneImage(in: paragraph) {
            renderImage(image)
        } else {
            SwiftUI.Text(renderInline(paragraph))
                .font(.body)
                .foregroundColor(theme.chrome.text)
        }
    }

    private func standaloneImage(in paragraph: Paragraph) -> Markdown.Image? {
        for child in paragraph.children {
            return child as? Markdown.Image
        }
        return nil
    }

    // MARK: - Image

    @ViewBuilder
    private func renderImage(_ image: Markdown.Image) -> some View {
        if let source = image.source, let url = URL(string: source) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure:
                    SwiftUI.Text(image.plainText.isEmpty ? "[image]" : image.plainText)
                        .foregroundColor(theme.chrome.textDim)
                        .italic()
                default:
                    ProgressView()
                        .frame(height: 100)
                }
            }
        } else {
            SwiftUI.Text(image.plainText.isEmpty ? "[image]" : image.plainText)
                .foregroundColor(theme.chrome.textDim)
                .italic()
        }
    }

    // MARK: - Block Quote

    @ViewBuilder
    private func renderBlockQuote(_ blockQuote: BlockQuote) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.chrome.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    AnyView(renderBlock(child))
                }
            }
            .padding(.leading, 12)
        }
        .foregroundColor(theme.chrome.textDim)
    }

    // MARK: - Ordered List

    @ViewBuilder
    private func renderOrderedList(_ list: OrderedList) -> some View {
        let startIndex = Int(list.startIndex)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.children.enumerated()), id: \.offset) { index, child in
                if let item = child as? ListItem {
                    renderListItem(item, bullet: "\(startIndex + index).")
                }
            }
        }
    }

    // MARK: - Unordered List

    @ViewBuilder
    private func renderUnorderedList(_ list: UnorderedList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.children.enumerated()), id: \.offset) { _, child in
                if let item = child as? ListItem {
                    renderListItem(item, bullet: nil)
                }
            }
        }
    }

    // MARK: - List Item

    @ViewBuilder
    private func renderListItem(_ item: ListItem, bullet: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Checkbox, number, or bullet
            if let checkbox = item.checkbox {
                SwiftUI.Image(
                    systemName: checkbox == .checked
                        ? "checkmark.square.fill" : "square"
                )
                .font(.callout)
                .foregroundColor(
                    checkbox == .checked ? theme.chrome.accent : theme.chrome.textDim
                )
            } else if let bullet {
                SwiftUI.Text(bullet)
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
                    .frame(minWidth: 16, alignment: .trailing)
            } else {
                SwiftUI.Text("\u{2022}")
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
            }

            // Item content
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    AnyView(renderBlock(child))
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Inline Helper

    private func renderInline(_ markup: any Markup) -> AttributedString {
        var renderer = InlineRenderer(theme: theme)
        return renderer.visit(markup)
    }
}
