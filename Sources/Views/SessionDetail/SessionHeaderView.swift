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
                                        .foregroundColor(theme.chrome.purple)
                                }
                                .buttonStyle(.plain)
                                .help("Open PR in browser")

                                // Check summary
                                if pr.checks.total > 0 {
                                    HStack(spacing: 3) {
                                        Group {
                                            if pr.checks.allPassed {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(theme.chrome.green)
                                            } else if pr.checks.hasFailed {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(theme.chrome.red)
                                            } else {
                                                Image(systemName: "clock.fill")
                                                    .foregroundColor(theme.chrome.yellow)
                                            }
                                        }
                                        .font(.caption2)
                                        Text("\(pr.checks.passed)/\(pr.checks.total)")
                                            .font(.caption)
                                            .foregroundColor(theme.chrome.textDim)
                                    }
                                }

                                // Review decision badge
                                reviewBadge(for: pr.reviewDecision)

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

    @ViewBuilder
    private var statusDot: some View {
        switch session.status {
        case .running:
            Circle()
                .fill(theme.chrome.green)
                .frame(width: 7, height: 7)
        case .waiting:
            Circle()
                .fill(theme.chrome.yellow)
                .frame(width: 7, height: 7)
        case .starting:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.45)
                .frame(width: 7, height: 7)
        case .error:
            Circle()
                .fill(theme.chrome.red)
                .frame(width: 7, height: 7)
        case .idle, .stopped:
            Circle()
                .strokeBorder(theme.chrome.textDim, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        }
    }

    // MARK: - Review Badge

    @ViewBuilder
    private func reviewBadge(for decision: ReviewDecision) -> some View {
        switch decision {
        case .approved:
            Text("Approved")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(theme.chrome.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.chrome.green.opacity(0.15))
                .clipShape(Capsule())
        case .changesRequested:
            Text("Changes")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(theme.chrome.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.chrome.orange.opacity(0.15))
                .clipShape(Capsule())
        case .pending:
            Text("Review")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(theme.chrome.yellow)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.chrome.yellow.opacity(0.15))
                .clipShape(Capsule())
        case .none:
            EmptyView()
        }
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
