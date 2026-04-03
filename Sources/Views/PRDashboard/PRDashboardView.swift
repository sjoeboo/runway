import Models
import SwiftUI
import Theme

/// PR dashboard with tab-filtered list and detail drawer.
public struct PRDashboardView: View {
    let pullRequests: [PullRequest]
    let selectedPRID: String?
    let detail: PRDetail?
    let isLoading: Bool
    let onSelectPR: (PullRequest?) -> Void
    let onFilterChange: (PRTab) -> Void
    let onRefresh: () -> Void
    let onApprove: (PullRequest) -> Void
    let onComment: (PullRequest, String) -> Void

    @State private var selectedTab: PRTab = .mine
    @AppStorage("prListWidth") private var prListWidth: Double = 380
    @Environment(\.theme) private var theme

    public init(
        pullRequests: [PullRequest] = [],
        selectedPRID: String? = nil,
        detail: PRDetail? = nil,
        isLoading: Bool = false,
        onSelectPR: @escaping (PullRequest?) -> Void = { _ in },
        onFilterChange: @escaping (PRTab) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {},
        onApprove: @escaping (PullRequest) -> Void = { _ in },
        onComment: @escaping (PullRequest, String) -> Void = { _, _ in }
    ) {
        self.pullRequests = pullRequests
        self.selectedPRID = selectedPRID
        self.detail = detail
        self.isLoading = isLoading
        self.onSelectPR = onSelectPR
        self.onFilterChange = onFilterChange
        self.onRefresh = onRefresh
        self.onApprove = onApprove
        self.onComment = onComment
    }

    private var selectedPR: PullRequest? {
        pullRequests.first(where: { $0.id == selectedPRID })
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left: PR list
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(PRTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 12)
                    }

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(theme.chrome.surface)

                Divider()

                // PR list
                if filteredPRs.isEmpty && !isLoading {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "pull.request")
                            .font(.largeTitle)
                            .foregroundColor(theme.chrome.textDim)
                        Text("No pull requests")
                            .foregroundColor(theme.chrome.textDim)
                        Button("Refresh") { onRefresh() }
                            .controlSize(.small)
                    }
                    Spacer()
                } else {
                    List(
                        filteredPRs,
                        selection: Binding(
                            get: { selectedPRID },
                            set: { id in
                                let pr = pullRequests.first(where: { $0.id == id })
                                onSelectPR(pr)
                            }
                        )
                    ) { pr in
                        PRRowView(pr: pr)
                            .tag(pr.id)
                    }
                }
            }
            .frame(minWidth: 300)
            .frame(maxWidth: selectedPR == nil ? .infinity : CGFloat(prListWidth))

            // Right: PR detail drawer
            if let pr = selectedPR {
                Divider()
                PRDetailDrawer(
                    pr: pr,
                    detail: detail,
                    onClose: { onSelectPR(nil) },
                    onApprove: { onApprove(pr) },
                    onComment: { body in onComment(pr, body) }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { onRefresh() }
    }

    private var filteredPRs: [PullRequest] {
        // All filtering is done server-side by PRManager (--author @me, --review-requested @me)
        // Local filtering just passes through since each tab triggers a server re-fetch
        pullRequests
    }

    private func tabButton(_ tab: PRTab) -> some View {
        Button(action: {
            selectedTab = tab
            switch tab {
            case .all: onFilterChange(tab)
            case .mine: onFilterChange(tab)
            case .reviewRequested: onFilterChange(tab)
            }
        }) {
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

public enum PRTab: String, CaseIterable, Sendable {
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
                    Text(pr.repo)
                        .font(.caption)
                        .foregroundColor(theme.chrome.cyan)
                    Text(pr.author)
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    if !pr.headBranch.isEmpty {
                        Text(pr.headBranch)
                            .font(.caption)
                            .foregroundColor(theme.chrome.accent)
                    }
                    checksSummary
                    reviewBadge
                }
            }

            Spacer()

            if pr.additions > 0 || pr.deletions > 0 {
                Text("+\(pr.additions) -\(pr.deletions)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
            }
        }
        .padding(.vertical, 4)
        .opacity(pr.isDraft ? 0.5 : 1.0)
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
