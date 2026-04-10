import Models
import SwiftUI
import Theme

/// Clickable column header row for the PR list. Tapping a column toggles sort.
struct PRColumnHeader: View {
    @Binding var sortField: PRSortField
    @Binding var sortOrder: PRSortOrder
    @Binding var columnWidths: PRColumnWidths
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            columnButton(.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnButton(.repo)
                .frame(width: columnWidths.repo, alignment: .leading)
            columnButton(.author)
                .frame(width: columnWidths.author, alignment: .leading)
            columnButton(.age)
                .frame(width: columnWidths.age, alignment: .leading)
            columnButton(.checks)
                .frame(width: columnWidths.checks, alignment: .leading)
            columnButton(.review)
                .frame(width: columnWidths.review, alignment: .leading)
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
}
