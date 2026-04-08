import Markdown
import SwiftUI
import Theme

/// Renders a GFM table as a native SwiftUI Grid.
struct TableView: View {
    let table: Markdown.Table
    let theme: AppTheme

    var body: some View {
        let alignments = table.columnAlignments
        let headerCells = extractCells(from: table.head)
        let bodyRows = extractBodyRows()

        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            GridRow {
                ForEach(Array(headerCells.enumerated()), id: \.offset) { index, cell in
                    cellView(cell, isHeader: true, alignment: columnAlignment(alignments, index))
                }
            }

            // Separator
            Divider()
                .background(theme.chrome.border)

            // Body rows
            ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        cellView(cell, isHeader: false, alignment: columnAlignment(alignments, index))
                    }
                }
                Divider()
                    .background(theme.chrome.border)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.chrome.border, lineWidth: 1)
        )
    }

    // MARK: - Cell Rendering

    @ViewBuilder
    private func cellView(
        _ cell: Markdown.Table.Cell,
        isHeader: Bool,
        alignment: Alignment
    ) -> some View {
        let attributed = renderCellContent(cell)
        SwiftUI.Text(attributed)
            .font(isHeader ? .callout.bold() : .callout)
            .foregroundColor(theme.chrome.text)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHeader ? theme.chrome.surface : Color.clear)
    }

    // MARK: - Helpers

    private func renderCellContent(_ cell: Markdown.Table.Cell) -> AttributedString {
        var renderer = InlineRenderer(theme: theme)
        return renderer.visit(cell)
    }

    private func extractCells(from head: Markdown.Table.Head) -> [Markdown.Table.Cell] {
        head.children.compactMap { $0 as? Markdown.Table.Cell }
    }

    private func extractBodyRows() -> [[Markdown.Table.Cell]] {
        table.body.children.compactMap { $0 as? Markdown.Table.Row }.map { row in
            row.children.compactMap { $0 as? Markdown.Table.Cell }
        }
    }

    private func columnAlignment(
        _ alignments: [Markdown.Table.ColumnAlignment?], _ index: Int
    ) -> Alignment {
        guard index < alignments.count, let align = alignments[index] else {
            return .leading
        }
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
