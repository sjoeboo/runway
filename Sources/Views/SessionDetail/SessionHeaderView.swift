import Models
import SwiftUI
import Theme

/// Two-row header showing session identity (row 1) and git/PR context (row 2).
public struct SessionHeaderView: View {
    let session: Session
    var linkedPR: PullRequest?
    var prDetail: PRDetail? = nil
    var parentSession: Session? = nil
    var onSelectPR: ((PullRequest) -> Void)?
    var onSelectSession: ((String) -> Void)? = nil
    var changesVisible: Bool = false
    var onToggleChanges: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    public init(
        session: Session,
        linkedPR: PullRequest? = nil,
        prDetail: PRDetail? = nil,
        parentSession: Session? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        onSelectSession: ((String) -> Void)? = nil,
        changesVisible: Bool = false,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.prDetail = prDetail
        self.parentSession = parentSession
        self.onSelectPR = onSelectPR
        self.onSelectSession = onSelectSession
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
                        // Tool + permission mode badge
                        Text(toolBadgeText)
                            .font(.caption)
                            .foregroundColor(
                                session.useHappy ? theme.chrome.cyan : session.permissionMode.badgeForeground(chrome: theme.chrome)
                            )
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                session.useHappy
                                    ? theme.chrome.cyan.opacity(0.15) : session.permissionMode.badgeBackground(chrome: theme.chrome)
                            )
                            .clipShape(Capsule())
                    }
                }

                if let parent = parentSession {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Forked from")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            onSelectSession?(parent.id)
                        } label: {
                            Text("\"\(parent.title)\"")
                                .font(.caption)
                                .foregroundStyle(theme.chrome.accent)
                        }
                        .buttonStyle(.plain)
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

                                // Inline comment count badge
                                if let detail = prDetail {
                                    let inlineCount = detail.comments.filter { $0.path != nil }.count
                                    if inlineCount > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "text.bubble")
                                                .font(.caption2)
                                            Text("\(inlineCount)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(theme.chrome.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(theme.chrome.accent.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                }

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

    // MARK: - Computed Properties

    private var toolBadgeText: String {
        var parts = [session.tool.displayName.lowercased()]
        if session.useHappy {
            parts.append("happy")
        }
        parts.append(session.permissionMode.badgeLabel)
        return parts.joined(separator: " · ")
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
