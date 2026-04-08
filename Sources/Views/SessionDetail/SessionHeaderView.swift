import Models
import SwiftUI
import Theme

/// Two-row header showing session identity (row 1) and git/PR context (row 2).
public struct SessionHeaderView: View {
    let session: Session
    var linkedPR: PullRequest?
    var onSelectPR: ((PullRequest) -> Void)?
    var changesVisible: Bool = false
    var onToggleChanges: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    public init(
        session: Session,
        linkedPR: PullRequest? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        changesVisible: Bool = false,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.onSelectPR = onSelectPR
        self.changesVisible = changesVisible
        self.onToggleChanges = onToggleChanges
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // Row 1 — Session Identity
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        statusDot
                        Text(session.title)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(session.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        // Changes sidebar toggle
                        if onToggleChanges != nil {
                            Button(action: { onToggleChanges?() }) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.body)
                                    .foregroundColor(changesVisible ? theme.chrome.accent : theme.chrome.textDim)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle changes sidebar (⌘3)")
                            .accessibilityLabel("Toggle changes sidebar")
                        }

                        // Tool + permission mode badge
                        Text("\(session.tool.displayName.lowercased()) · \(session.permissionMode.badgeLabel)")
                            .font(.caption)
                            .foregroundColor(session.permissionMode.badgeForeground(chrome: theme.chrome))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(session.permissionMode.badgeBackground(chrome: theme.chrome))
                            .clipShape(Capsule())
                    }
                }

                // Row 2 — Git & PR Context (only if branch is set)
                if let branch = session.worktreeBranch {
                    HStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(branch)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(theme.chrome.cyan)

                            if let pr = linkedPR {
                                Text("→")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text(pr.baseBranch)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let pr = linkedPR {
                            HStack(spacing: 8) {
                                // PR number — opens in browser
                                Button {
                                    if let onSelectPR {
                                        onSelectPR(pr)
                                    } else if let url = URL(string: pr.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text("#\(pr.number)")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(pr.numberColor(chrome: theme.chrome))
                                }
                                .buttonStyle(LinkButtonStyle())
                                .help(onSelectPR != nil ? "View PR details" : "Open PR in browser")

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
                                    .font(.callout)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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

    fileprivate func badgeForeground(chrome: ChromePalette) -> Color {
        switch self {
        case .default: chrome.textDim
        case .acceptEdits: chrome.orange
        case .bypassAll: chrome.red
        }
    }

    fileprivate func badgeBackground(chrome: ChromePalette) -> Color {
        switch self {
        case .default: chrome.surface.opacity(0.6)
        case .acceptEdits: chrome.orange.opacity(0.15)
        case .bypassAll: chrome.red.opacity(0.15)
        }
    }
}
