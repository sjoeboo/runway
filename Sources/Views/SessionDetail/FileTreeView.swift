import Models
import SwiftUI
import Theme

/// Renders a tree of FileTreeNode with collapsible directories and file selection.
///
/// Uses a flattened representation with `LazyVStack` so SwiftUI only instantiates
/// visible rows — critical when hundreds of files are changed.
struct FileTreeView: View {
    let nodes: [FileTreeNode]
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(nodes) { node in
                NodeRowView(
                    node: node,
                    depth: 0,
                    selectedPath: selectedPath,
                    onSelectFile: onSelectFile,
                    defaultExpanded: nodes.flatCount <= 80
                )
            }
        }
    }
}

// MARK: - NodeRowView

/// A single directory or file row that lazily renders its children.
/// Each directory manages its own `@State isExpanded`, so collapsing
/// a folder removes all descendant views from the hierarchy.
private struct NodeRowView: View {
    let node: FileTreeNode
    let depth: Int
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    let defaultExpanded: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        switch node {
        case .directory(let name, _, let children, _, let dels):
            DirectoryRow(
                name: name,
                children: children,
                additions: node.additions,
                deletions: dels,
                depth: depth,
                selectedPath: selectedPath,
                onSelectFile: onSelectFile,
                defaultExpanded: defaultExpanded
            )
        case .file(let fc):
            FileRow(
                change: fc,
                isSelected: fc.path == selectedPath,
                onSelect: { onSelectFile(fc) }
            )
            .padding(.leading, CGFloat(depth) * 16)
        }
    }
}

// MARK: - DirectoryRow

private struct DirectoryRow: View {
    let name: String
    let children: [FileTreeNode]
    let additions: Int
    let deletions: Int
    let depth: Int
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    let defaultExpanded: Bool
    @State private var isExpanded: Bool?
    @Environment(\.theme) private var theme

    private var expanded: Bool { isExpanded ?? defaultExpanded }

    var body: some View {
        Button(action: { isExpanded = !expanded }) {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(theme.chrome.textDim)
                    .frame(width: 14)
                Image(systemName: "folder.fill")
                    .font(.callout)
                    .foregroundColor(theme.chrome.accent)
                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(theme.chrome.textDim)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .padding(.leading, CGFloat(depth) * 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse folder \(name)" : "Expand folder \(name)")

        if expanded {
            ForEach(children) { child in
                NodeRowView(
                    node: child,
                    depth: depth + 1,
                    selectedPath: selectedPath,
                    onSelectFile: onSelectFile,
                    defaultExpanded: defaultExpanded
                )
            }
        }
    }
}

// MARK: - FileRow

private struct FileRow: View {
    let change: FileChange
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(change.status.rawValue)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(statusColor)
                    .frame(width: 18)

                Text(filename)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(change.status == .deleted ? theme.chrome.textDim : theme.chrome.text)
                    .strikethrough(change.status == .deleted)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 3) {
                    if change.additions > 0 {
                        Text("+\(change.additions)")
                            .foregroundColor(theme.chrome.green)
                    }
                    if change.deletions > 0 {
                        Text("-\(change.deletions)")
                            .foregroundColor(theme.chrome.red)
                    }
                }
                .font(.system(.callout, design: .monospaced))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(isSelected ? theme.chrome.accent.opacity(0.15) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filename), \(change.status.rawValue), +\(change.additions) -\(change.deletions)")
    }

    private var filename: String {
        if let lastSlash = change.path.lastIndex(of: "/") {
            return String(change.path[change.path.index(after: lastSlash)...])
        }
        return change.path
    }

    private var statusColor: Color {
        switch change.status {
        case .added: theme.chrome.green
        case .modified: theme.chrome.yellow
        case .deleted: theme.chrome.red
        case .renamed: theme.chrome.cyan
        }
    }
}
