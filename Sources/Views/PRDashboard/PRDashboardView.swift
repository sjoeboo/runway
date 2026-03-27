import SwiftUI
import Models
import Theme

/// PR dashboard with tab-filtered list and detail drawer.
public struct PRDashboardView: View {
    @State private var selectedTab: PRTab = .mine
    @State private var selectedPR: PullRequest?
    let pullRequests: [PullRequest]
    @Environment(\.theme) private var theme

    public init(pullRequests: [PullRequest] = []) {
        self.pullRequests = pullRequests
    }

    public var body: some View {
        HSplitView {
            // Left: PR list
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(PRTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(theme.chrome.surface)

                Divider()

                // PR list
                List(filteredPRs, selection: Binding(
                    get: { selectedPR?.id },
                    set: { id in selectedPR = pullRequests.first(where: { $0.id == id }) }
                )) { pr in
                    PRRowView(pr: pr)
                        .tag(pr.id)
                }
            }

            // Right: PR detail drawer
            if let pr = selectedPR {
                PRDetailDrawer(
                    pr: pr,
                    onClose: { selectedPR = nil }
                )
                .frame(minWidth: 400)
            }
        }
    }

    private var filteredPRs: [PullRequest] {
        switch selectedTab {
        case .all:
            pullRequests
        case .mine:
            pullRequests.filter { $0.author == currentUser }
        case .reviewRequested:
            pullRequests // TODO: filter by review-requested
        }
    }

    private var currentUser: String {
        // Will be populated from gh auth status
        ""
    }

    private func tabButton(_ tab: PRTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Text(tab.rawValue)
                .font(.subheadline)
                .fontWeight(selectedTab == tab ? .semibold : .regular)
                .foregroundColor(selectedTab == tab ? theme.chrome.accent : theme.chrome.textDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

enum PRTab: String, CaseIterable {
    case all = "All"
    case mine = "Mine"
    case reviewRequested = "Review Requests"
}

struct PRRowView: View {
    let pr: PullRequest
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            stateBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("#\(pr.number)")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    Text(pr.title)
                        .font(.body)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(pr.author)
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    Text(pr.headBranch)
                        .font(.caption)
                        .foregroundColor(theme.chrome.accent)
                    checksSummary
                    reviewBadge
                }
            }

            Spacer()

            Text("+\(pr.additions) -\(pr.deletions)")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
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
