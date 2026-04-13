import GitOperations
import Models
import SwiftUI
import Theme

/// Shows commit history for a session's worktree branch with rollback capability.
/// Displayed as a popover from the session header's branch name area.
public struct CommitHistoryView: View {
    let session: Session
    let worktreeManager: WorktreeManager
    let defaultBranch: String
    var onRollback: ((String) -> Void)?

    @State private var commits: [(hash: String, subject: String)] = []
    @State private var isLoading = true
    @State private var confirmRollbackHash: String?

    @Environment(\.theme) private var theme

    public init(
        session: Session,
        worktreeManager: WorktreeManager,
        defaultBranch: String = "main",
        onRollback: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.worktreeManager = worktreeManager
        self.defaultBranch = defaultBranch
        self.onRollback = onRollback
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Commits")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.chrome.text)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if commits.isEmpty && !isLoading {
                Text("No commits on this branch yet")
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(commits.enumerated()), id: \.offset) { index, commit in
                            commitRow(commit, isLatest: index == 0)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 360)
        .background(theme.chrome.background)
        .task {
            await loadCommits()
        }
        .alert(
            "Roll back to this commit?",
            isPresented: Binding(
                get: { confirmRollbackHash != nil },
                set: { if !$0 { confirmRollbackHash = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { confirmRollbackHash = nil }
            Button("Roll Back", role: .destructive) {
                if let hash = confirmRollbackHash {
                    onRollback?(hash)
                    confirmRollbackHash = nil
                }
            }
        } message: {
            if let hash = confirmRollbackHash,
                let commit = commits.first(where: { $0.hash == hash })
            {
                Text(
                    "This will reset the working tree to \(commit.hash). Uncommitted changes will be lost."
                )
            }
        }
    }

    private func commitRow(
        _ commit: (hash: String, subject: String), isLatest: Bool
    ) -> some View {
        HStack(spacing: 8) {
            // Commit hash
            Text(commit.hash)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(theme.chrome.accent)
                .frame(width: 60, alignment: .leading)

            // Commit message
            Text(commit.subject)
                .font(.callout)
                .foregroundColor(theme.chrome.text)
                .lineLimit(1)

            Spacer()

            if isLatest {
                Text("HEAD")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(theme.chrome.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(theme.chrome.green.opacity(0.12))
                    .clipShape(Capsule())
            } else if onRollback != nil {
                Button {
                    confirmRollbackHash = commit.hash
                } label: {
                    Text("Roll back")
                        .font(.caption)
                        .foregroundColor(theme.chrome.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Roll back to commit \(commit.hash)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isLatest ? theme.chrome.accent.opacity(0.05) : .clear)
    }

    private func loadCommits() async {
        isLoading = true
        commits = await worktreeManager.commitLog(
            path: session.path,
            baseBranch: defaultBranch
        )
        isLoading = false
    }
}
