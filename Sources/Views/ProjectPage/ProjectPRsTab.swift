import Models
import SwiftUI
import Theme

// MARK: - ProjectPRsTab

public struct ProjectPRsTab: View {
    let pullRequests: [PullRequest]
    let onSelectPR: (PullRequest) -> Void
    let onRefresh: () -> Void
    var selectedPRID: String?
    var detail: PRDetail?
    var onApprove: ((PullRequest) -> Void)?
    var onComment: ((PullRequest, String) -> Void)?
    var onRequestChanges: ((PullRequest, String) -> Void)?
    var onMerge: ((PullRequest, MergeStrategy) -> Void)?
    var onToggleDraft: ((PullRequest) -> Void)?
    var onUpdateBranch: ((PullRequest, Bool) -> Void)?
    var onReviewPR: ((PullRequest) -> Void)?

    @AppStorage("hideDrafts") private var hideDrafts: Bool = false
    @Environment(\.theme) private var theme

    public init(
        pullRequests: [PullRequest],
        onSelectPR: @escaping (PullRequest) -> Void,
        onRefresh: @escaping () -> Void,
        selectedPRID: String? = nil,
        detail: PRDetail? = nil,
        onApprove: ((PullRequest) -> Void)? = nil,
        onComment: ((PullRequest, String) -> Void)? = nil,
        onRequestChanges: ((PullRequest, String) -> Void)? = nil,
        onMerge: ((PullRequest, MergeStrategy) -> Void)? = nil,
        onToggleDraft: ((PullRequest) -> Void)? = nil,
        onUpdateBranch: ((PullRequest, Bool) -> Void)? = nil,
        onReviewPR: ((PullRequest) -> Void)? = nil
    ) {
        self.pullRequests = pullRequests
        self.onSelectPR = onSelectPR
        self.onRefresh = onRefresh
        self.selectedPRID = selectedPRID
        self.detail = detail
        self.onApprove = onApprove
        self.onComment = onComment
        self.onRequestChanges = onRequestChanges
        self.onMerge = onMerge
        self.onToggleDraft = onToggleDraft
        self.onUpdateBranch = onUpdateBranch
        self.onReviewPR = onReviewPR
    }

    private var selectedPR: PullRequest? {
        pullRequests.first(where: { $0.id == selectedPRID })
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
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    hideDrafts.toggle()
                } label: {
                    Image(systemName: hideDrafts ? "eye.slash" : "eye")
                        .font(.callout)
                }
                .buttonStyle(IconButtonStyle())
                .help(hideDrafts ? "Show drafts" : "Hide drafts")

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout)
                }
                .buttonStyle(IconButtonStyle())
                .help("Refresh pull requests")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filteredPRs.isEmpty {
                emptyStateView
            } else if let pr = selectedPR {
                HStack(spacing: 0) {
                    prList
                        .frame(maxWidth: 320)
                    Divider()
                    PRDetailDrawer(
                        pr: pr,
                        detail: detail,
                        onClose: { onSelectPR(pr) },
                        onApprove: { onApprove?(pr) },
                        onComment: { body in onComment?(pr, body) },
                        onRequestChanges: { body in onRequestChanges?(pr, body) },
                        onMerge: { strategy in onMerge?(pr, strategy) },
                        onToggleDraft: { onToggleDraft?(pr) },
                        onUpdateBranch: onUpdateBranch.map { callback in
                            { rebase in callback(pr, rebase) }
                        }
                    )
                }
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
                .foregroundStyle(.secondary)
            Text("No pull requests")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var prList: some View {
        List {
            ForEach(filteredPRs) { pr in
                ProjectPRRowView(pr: pr, onReview: onReviewPR.map { callback in { callback(pr) } })
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
    var onReview: (() -> Void)?
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
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if !pr.headBranch.isEmpty {
                        Text(pr.headBranch)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(theme.chrome.cyan)
                    }
                    Text(pr.ageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CheckSummaryBadge(checks: pr.checks)
                    ReviewDecisionBadge(decision: pr.reviewDecision)
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
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let onReview {
                Button("Open Review Session") { onReview() }
            }
        }
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

}
