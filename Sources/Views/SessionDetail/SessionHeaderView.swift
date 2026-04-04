import Models
import SwiftUI
import Theme

/// Two-row header showing session identity (row 1) and git/PR context (row 2).
public struct SessionHeaderView: View {
    let session: Session
    var linkedPR: PullRequest?
    @Environment(\.theme) private var theme

    public init(session: Session, linkedPR: PullRequest? = nil) {
        self.session = session
        self.linkedPR = linkedPR
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // Row 1 — Session Identity
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        statusDot
                        Text(session.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(theme.chrome.text)
                        Text(session.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                    }

                    Spacer()

                    // Tool + permission mode badge
                    Text("\(session.tool.displayName.lowercased()) · \(session.permissionMode.badgeLabel)")
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.chrome.surface.opacity(0.6))
                        .clipShape(Capsule())
                }

                // Row 2 — Git & PR Context (only if branch is set)
                if let branch = session.worktreeBranch {
                    HStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundColor(theme.chrome.textDim)
                            Text(branch)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(theme.chrome.cyan)

                            if let pr = linkedPR {
                                Text("→")
                                    .font(.caption)
                                    .foregroundColor(theme.chrome.textDim)
                                Text(pr.baseBranch)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(theme.chrome.textDim)
                            }
                        }

                        Spacer()

                        if let pr = linkedPR {
                            HStack(spacing: 8) {
                                // PR number — opens in browser
                                Button {
                                    if let url = URL(string: pr.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text("#\(pr.number)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(pr.numberColor(chrome: theme.chrome))
                                }
                                .buttonStyle(.plain)
                                .help("Open PR in browser")

                                // Check summary
                                CheckSummaryBadge(checks: pr.checks, style: .inline)

                                // Review decision badge
                                ReviewDecisionBadge(decision: pr.reviewDecision, style: .capsule)

                                // Diff stats
                                if pr.additions > 0 || pr.deletions > 0 {
                                    HStack(spacing: 3) {
                                        Text("+\(pr.additions)")
                                            .foregroundColor(theme.chrome.green)
                                        Text("−\(pr.deletions)")
                                            .foregroundColor(theme.chrome.red)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(theme.chrome.surface.opacity(0.3))

            Divider()
        }
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        SessionStatusIndicator(status: session.status, size: 7)
    }
}

// MARK: - PermissionMode badge label

extension PermissionMode {
    fileprivate var badgeLabel: String {
        switch self {
        case .default: "default"
        case .acceptEdits: "accept-edits"
        case .bypassAll: "bypass-all"
        }
    }
}
