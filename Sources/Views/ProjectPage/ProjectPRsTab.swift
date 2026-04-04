import Models
import SwiftUI
import Theme

// MARK: - ProjectPRsTab

public struct ProjectPRsTab: View {
    let pullRequests: [PullRequest]
    let onSelectPR: (PullRequest) -> Void
    let onRefresh: () -> Void

    @AppStorage("hideDrafts") private var hideDrafts: Bool = false
    @Environment(\.theme) private var theme

    public init(
        pullRequests: [PullRequest],
        onSelectPR: @escaping (PullRequest) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.pullRequests = pullRequests
        self.onSelectPR = onSelectPR
        self.onRefresh = onRefresh
    }

    private var filteredPRs: [PullRequest] {
        let sorted = pullRequests.sorted { $0.updatedAt > $1.updatedAt }
        return hideDrafts ? sorted.filter { !$0.isDraft } : sorted
    }

    private var openCount: Int {
        pullRequests.filter { $0.state == .open || $0.state == .draft }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("\(openCount) pull request\(openCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)

                Spacer()

                Button {
                    hideDrafts.toggle()
                } label: {
                    Image(systemName: hideDrafts ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(hideDrafts ? "Show drafts" : "Hide drafts")

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh pull requests")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filteredPRs.isEmpty {
                emptyStateView
            } else {
                prList
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.largeTitle)
                .foregroundColor(theme.chrome.textDim)
            Text("No pull requests")
                .font(.headline)
                .foregroundColor(theme.chrome.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var prList: some View {
        List {
            ForEach(filteredPRs) { pr in
                ProjectPRRowView(pr: pr)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectPR(pr) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .opacity(pr.isDraft ? 0.5 : 1.0)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - PR Row

private struct ProjectPRRowView: View {
    let pr: PullRequest
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            stateBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("#\(pr.number)")
                        .font(.caption)
                        .foregroundColor(theme.chrome.purple)
                    Text(pr.title)
                        .font(.body)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if !pr.headBranch.isEmpty {
                        Text(pr.headBranch)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(theme.chrome.cyan)
                    }
                    checksSummary
                    reviewBadge
                }
            }

            Spacer()

            if pr.additions > 0 || pr.deletions > 0 {
                HStack(spacing: 2) {
                    Text("+\(pr.additions)")
                        .foregroundColor(theme.chrome.green)
                    Text("-\(pr.deletions)")
                        .foregroundColor(theme.chrome.red)
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch pr.state {
        case .open:
            Circle().fill(theme.chrome.green).frame(width: 8, height: 8)
        case .draft:
            Circle().stroke(theme.chrome.textDim, lineWidth: 1.5).frame(width: 8, height: 8)
        case .merged:
            Circle().fill(theme.chrome.purple).frame(width: 8, height: 8)
        case .closed:
            Circle().fill(theme.chrome.red).frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private var checksSummary: some View {
        if pr.checks.total > 0 {
            HStack(spacing: 2) {
                if pr.checks.allPassed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(theme.chrome.green)
                } else if pr.checks.hasFailed {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.chrome.red)
                } else {
                    Image(systemName: "circle.fill")
                        .foregroundColor(theme.chrome.yellow)
                }
                Text("\(pr.checks.passed)/\(pr.checks.total)")
            }
            .font(.caption2)
        }
    }

    @ViewBuilder
    private var reviewBadge: some View {
        switch pr.reviewDecision {
        case .approved:
            Label("Approved", systemImage: "checkmark")
                .font(.caption2)
                .foregroundColor(theme.chrome.green)
        case .changesRequested:
            Label("Changes", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundColor(theme.chrome.orange)
        case .pending:
            Label("Review", systemImage: "clock")
                .font(.caption2)
                .foregroundColor(theme.chrome.yellow)
        case .none:
            EmptyView()
        }
    }
}
