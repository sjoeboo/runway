import Models
import SwiftUI
import Theme

/// Renders a tree of FileTreeNode with collapsible directories and file selection.
struct FileTreeView: View {
    let nodes: [FileTreeNode]
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(nodes) { node in
                nodeRow(node)
            }
        }
    }

    @ViewBuilder
    private func nodeRow(_ node: FileTreeNode) -> some View {
        switch node {
        case .directory(let name, _, let children, _, let dels):
            DirectoryRow(
                name: name,
                children: children,
                additions: node.additions,
                deletions: dels,
                selectedPath: selectedPath,
                onSelectFile: onSelectFile
            )
        case .file(let fc):
            FileRow(
                change: fc,
                isSelected: fc.path == selectedPath,
                onSelect: { onSelectFile(fc) }
            )
        }
    }
}

// MARK: - DirectoryRow

private struct DirectoryRow: View {
    let name: String
    let children: [FileTreeNode]
    let additions: Int
    let deletions: Int
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @State private var isExpanded = true
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(children) { child in
                    Group {
                        switch child {
                        case .directory(let childName, _, let grandchildren, let adds, let dels):
                            DirectoryRow(
                                name: childName,
                                children: grandchildren,
                                additions: adds,
                                deletions: dels,
                                selectedPath: selectedPath,
                                onSelectFile: onSelectFile
                            )
                        case .file(let fc):
                            FileRow(
                                change: fc,
                                isSelected: fc.path == selectedPath,
                                onSelect: { onSelectFile(fc) }
                            )
                        }
                    }
                    .padding(.leading, 16)
                }
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
            .cornerRadius(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
