import GitHubOperations
import SwiftUI
import Theme

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if index == 0 {
                currentRowWidth = size.width
                rowHeight = size.height
            } else if currentRowWidth + horizontalSpacing + size.width <= containerWidth {
                currentRowWidth += horizontalSpacing + size.width
                rowHeight = max(rowHeight, size.height)
            } else {
                totalHeight += rowHeight + verticalSpacing
                currentRowWidth = size.width
                rowHeight = size.height
            }
        }
        totalHeight += rowHeight

        return CGSize(width: containerWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if index == 0 {
                currentX = bounds.minX
                rowHeight = size.height
            } else if currentX + horizontalSpacing + size.width <= bounds.maxX {
                currentX += horizontalSpacing
            } else {
                currentX = bounds.minX
                currentY += rowHeight + verticalSpacing
                rowHeight = size.height
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Label Chip

private struct LabelChip: View {
    let label: IssueLabel
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.theme) private var theme

    private var chipColor: Color {
        Color(hex: label.color) ?? theme.chrome.accent
    }

    var body: some View {
        Button(action: onTap) {
            Text(label.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chipColor.opacity(isSelected ? 0.25 : 0.1))
                .overlay(Capsule().strokeBorder(chipColor, lineWidth: isSelected ? 1.5 : 0.5))
                .clipShape(Capsule())
                .foregroundColor(chipColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NewIssueSheet

public struct NewIssueSheet: View {
    let labels: [IssueLabel]
    let onCreate: (String, String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var title: String = ""
    @State private var issueBody: String = ""
    @State private var selectedLabels: Set<String> = []

    public init(
        labels: [IssueLabel],
        onCreate: @escaping (String, String, [String]) -> Void
    ) {
        self.labels = labels
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Issue")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Title field
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextField("Issue title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Body text area
            VStack(alignment: .leading, spacing: 4) {
                Text("Body")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextEditor(text: $issueBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.chrome.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Labels
            if !labels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Labels")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(labels) { label in
                            LabelChip(
                                label: label,
                                isSelected: selectedLabels.contains(label.name)
                            ) {
                                if selectedLabels.contains(label.name) {
                                    selectedLabels.remove(label.name)
                                } else {
                                    selectedLabels.insert(label.name)
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Issue") {
                    onCreate(title.trimmingCharacters(in: .whitespacesAndNewlines), issueBody, Array(selectedLabels))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
}
