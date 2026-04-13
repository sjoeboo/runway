import Models
import SwiftUI
import Theme

/// Right sidebar showing changed files in the session's worktree.
struct ChangesSidebarView: View {
    let changes: [FileChange]
    let nodes: [FileTreeNode]
    @Binding var mode: ChangesMode
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            fileTree
        }
        .background(theme.chrome.surface.opacity(0.3))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Changes")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(theme.chrome.text)

            Spacer()

            Picker("", selection: $mode) {
                Text("vs Main").tag(ChangesMode.branch)
                Text("Uncommitted").tag(ChangesMode.working)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 6) {
            Text("\(changes.count) file\(changes.count == 1 ? "" : "s")")
            Text("+\(totalAdditions)")
                .foregroundColor(theme.chrome.green)
            Text("-\(totalDeletions)")
                .foregroundColor(theme.chrome.red)
        }
        .font(.callout)
        .foregroundColor(theme.chrome.textDim)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - File Tree

    private var fileTree: some View {
        ScrollView {
            FileTreeView(
                nodes: nodes,
                selectedPath: selectedPath,
                onSelectFile: onSelectFile
            )
            .padding(.vertical, 4)
        }
    }

    private var totalAdditions: Int { changes.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { changes.reduce(0) { $0 + $1.deletions } }
}
