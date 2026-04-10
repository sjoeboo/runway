import Models
import SwiftUI
import Theme

/// Clickable column header row for the PR list. Tapping a column toggles sort.
/// Drag the edges between columns to resize.
struct PRColumnHeader: View {
    @Binding var sortField: PRSortField
    @Binding var sortOrder: PRSortOrder
    @Binding var columnWidths: PRColumnWidths
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            columnButton(.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnDivider(for: .repo)
            columnButton(.repo)
                .frame(width: columnWidths.repo, alignment: .leading)
            columnDivider(for: .author)
            columnButton(.author)
                .frame(width: columnWidths.author, alignment: .leading)
            columnDivider(for: .age)
            columnButton(.age)
                .frame(width: columnWidths.age, alignment: .leading)
            columnDivider(for: .checks)
            columnButton(.checks)
                .frame(width: columnWidths.checks, alignment: .leading)
            columnDivider(for: .review)
            columnButton(.review)
                .frame(width: columnWidths.review, alignment: .leading)
            columnDivider(for: .mergeStatus)
            columnButton(.mergeStatus)
                .frame(width: columnWidths.merge, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.chrome.surface)
    }

    private func columnButton(_ field: PRSortField) -> some View {
        Button {
            if sortField == field {
                sortOrder = sortOrder == .ascending ? .descending : .ascending
            } else {
                sortField = field
                sortOrder = field == .age ? .descending : .ascending
            }
        } label: {
            HStack(spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundColor(
                        sortField == field ? theme.chrome.accent : theme.chrome.textDim
                    )
                if sortField == field {
                    Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(theme.chrome.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// A thin draggable divider between column headers for resizing.
    private func columnDivider(for field: PRSortField) -> some View {
        ColumnResizeHandle(
            width: Binding(
                get: { columnWidths.width(for: field) },
                set: { newWidth in
                    let clamped = Swift.min(
                        Swift.max(newWidth, PRColumnWidths.min(for: field)),
                        PRColumnWidths.max(for: field)
                    )
                    switch field {
                    case .repo: columnWidths.repo = clamped
                    case .author: columnWidths.author = clamped
                    case .age: columnWidths.age = clamped
                    case .checks: columnWidths.checks = clamped
                    case .review: columnWidths.review = clamped
                    case .mergeStatus: columnWidths.merge = clamped
                    case .title: break
                    }
                }
            )
        )
    }
}

// MARK: - Column Resize Handle

/// A thin vertical handle that can be dragged left/right to resize a column.
private struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 0
    @State private var cursorPushed = false
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.clear)
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering, !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !hovering, cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = width
                        }
                        width = dragStartWidth + value.translation.width
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
