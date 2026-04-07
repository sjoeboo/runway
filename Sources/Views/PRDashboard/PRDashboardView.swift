import Models
import SwiftUI
import Theme

/// PR dashboard with grouped sections, tab counts, and sessions toggle.
public struct PRDashboardView: View {
    let pullRequests: [PullRequest]
    let selectedPRID: String?
    let detail: PRDetail?
    let isLoading: Bool
    let sessionPRIDs: Set<String>
    @Binding var selectedTab: PRTab
    let onSelectPR: (PullRequest?) -> Void
    let onRefresh: () -> Void
    let onApprove: (PullRequest) -> Void
    let onComment: (PullRequest, String) -> Void
    var onRequestChanges: ((PullRequest, String) -> Void)?
    var onMerge: ((PullRequest, MergeStrategy) -> Void)?
    var onToggleDraft: ((PullRequest) -> Void)?
    var onUpdateBranch: ((PullRequest, Bool) -> Void)?
    var onSendToSession: ((PullRequest, String) -> Void)?
    var onReviewPR: ((PullRequest) -> Void)?
    var onEnableAutoMerge: ((PullRequest, MergeStrategy) -> Void)?
    var onDisableAutoMerge: ((PullRequest) -> Void)?

    @AppStorage("prListWidth") private var prListWidth: Double = 380
    @AppStorage("hideDrafts") private var hideDrafts: Bool = false
    @AppStorage("showSessionPRsOnly") private var showSessionPRsOnly: Bool = false
    @AppStorage("prGroupNeedsAttentionExpanded") private var needsAttentionExpanded: Bool = true
    @AppStorage("prGroupInProgressExpanded") private var inProgressExpanded: Bool = true
    @AppStorage("prGroupReadyExpanded") private var readyExpanded: Bool = true
    @AppStorage("prGroupWaitingForReviewExpanded") private var waitingForReviewExpanded: Bool = true
    @AppStorage("prGroupDraftsExpanded") private var draftsExpanded: Bool = false
    @Environment(\.theme) private var theme

    public init(
        pullRequests: [PullRequest] = [],
        selectedPRID: String? = nil,
        detail: PRDetail? = nil,
        isLoading: Bool = false,
        sessionPRIDs: Set<String> = [],
        selectedTab: Binding<PRTab> = .constant(.mine),
        onSelectPR: @escaping (PullRequest?) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {},
        onApprove: @escaping (PullRequest) -> Void = { _ in },
        onComment: @escaping (PullRequest, String) -> Void = { _, _ in },
        onRequestChanges: ((PullRequest, String) -> Void)? = nil,
        onMerge: ((PullRequest, MergeStrategy) -> Void)? = nil,
        onToggleDraft: ((PullRequest) -> Void)? = nil,
        onUpdateBranch: ((PullRequest, Bool) -> Void)? = nil,
        onSendToSession: ((PullRequest, String) -> Void)? = nil,
        onReviewPR: ((PullRequest) -> Void)? = nil,
        onEnableAutoMerge: ((PullRequest, MergeStrategy) -> Void)? = nil,
        onDisableAutoMerge: ((PullRequest) -> Void)? = nil
    ) {
        self.pullRequests = pullRequests
        self.selectedPRID = selectedPRID
        self.detail = detail
        self.isLoading = isLoading
        self.sessionPRIDs = sessionPRIDs
        self._selectedTab = selectedTab
        self.onSelectPR = onSelectPR
        self.onRefresh = onRefresh
        self.onApprove = onApprove
        self.onComment = onComment
        self.onRequestChanges = onRequestChanges
        self.onMerge = onMerge
        self.onToggleDraft = onToggleDraft
        self.onUpdateBranch = onUpdateBranch
        self.onSendToSession = onSendToSession
        self.onReviewPR = onReviewPR
        self.onEnableAutoMerge = onEnableAutoMerge
        self.onDisableAutoMerge = onDisableAutoMerge
    }

    private var selectedPR: PullRequest? {
        pullRequests.first(where: { $0.id == selectedPRID })
    }

    // MARK: - Filtering

    private func applyFilters(to prs: [PullRequest], tab: PRTab) -> [PullRequest] {
        var result = prs

        switch tab {
        case .all:
            break
        case .mine:
            result = result.filter { $0.origin.contains(.mine) }
        case .reviewRequested:
            result = result.filter { $0.origin.contains(.reviewRequested) }
        }

        if showSessionPRsOnly {
            result = result.filter { sessionPRIDs.contains($0.id) }
        }

        return result
    }

    private var filteredPRs: [PullRequest] {
        applyFilters(to: pullRequests, tab: selectedTab)
    }

    private func tabCount(_ tab: PRTab) -> Int {
        var prs = applyFilters(to: pullRequests, tab: tab)
        if hideDrafts { prs = prs.filter { !$0.isDraft } }
        return prs.count
    }

    // MARK: - Grouping

    private func groupedPRs() -> [(group: PRGroup, prs: [PullRequest])] {
        var byGroup: [PRGroup: [PullRequest]] = [:]
        for pr in filteredPRs {
            let g = prGroup(for: pr)
            byGroup[g, default: []].append(pr)
        }
        return PRGroup.allCases.compactMap { g in
            guard let prs = byGroup[g], !prs.isEmpty else { return nil }
            return (g, prs)
        }
    }

    private func isGroupExpanded(_ group: PRGroup) -> Bool {
        switch group {
        case .needsAttention: return needsAttentionExpanded
        case .inProgress: return inProgressExpanded
        case .ready: return readyExpanded
        case .waitingForReview: return waitingForReviewExpanded
        case .drafts: return draftsExpanded
        }
    }

    private func toggleGroupExpanded(_ group: PRGroup) {
        switch group {
        case .needsAttention: needsAttentionExpanded.toggle()
        case .inProgress: inProgressExpanded.toggle()
        case .ready: readyExpanded.toggle()
        case .waitingForReview: waitingForReviewExpanded.toggle()
        case .drafts: draftsExpanded.toggle()
        }
    }

    private func groupColor(_ group: PRGroup) -> Color {
        switch group {
        case .needsAttention: return theme.chrome.red
        case .inProgress: return theme.chrome.yellow
        case .ready: return theme.chrome.green
        case .waitingForReview: return theme.chrome.accent
        case .drafts: return theme.chrome.textDim
        }
    }

    private func groupIcon(_ group: PRGroup) -> String {
        switch group {
        case .needsAttention: return "exclamationmark.circle"
        case .inProgress: return "clock"
        case .ready: return "checkmark.circle"
        case .waitingForReview: return "eye"
        case .drafts: return "circle.dashed"
        }
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 0) {
            // Left: PR list
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 0) {
                    ForEach(PRTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }

                    // Sessions filter toggle
                    Button {
                        showSessionPRsOnly.toggle()
                    } label: {
                        Image(systemName: showSessionPRsOnly ? "terminal.fill" : "terminal")
                            .font(.callout)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(showSessionPRsOnly ? "Showing session PRs only" : "Show only session PRs")
                    .padding(.trailing, 4)

                    Button {
                        hideDrafts.toggle()
                    } label: {
                        Image(systemName: hideDrafts ? "eye.slash" : "eye")
                            .font(.callout)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(hideDrafts ? "Show drafts" : "Hide drafts")
                    .padding(.trailing, 4)

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout)
                    }
                    .buttonStyle(IconButtonStyle())
                    .padding(.trailing, 8)
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
                            .foregroundStyle(.secondary)
                        Text("No pull requests")
                            .foregroundStyle(.secondary)
                        Button("Refresh") { onRefresh() }
                            .controlSize(.small)
                    }
                    Spacer()
                } else {
                    let visibleGroups = groupedPRs().filter { !($0.group == .drafts && hideDrafts) }
                    if visibleGroups.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "pull.request")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No pull requests")
                                .foregroundStyle(.secondary)
                            Button("Refresh") { onRefresh() }
                                .controlSize(.small)
                        }
                        Spacer()
                    } else {
                        List(
                            selection: Binding(
                                get: { selectedPRID },
                                set: { id in
                                    let pr = pullRequests.first(where: { $0.id == id })
                                    onSelectPR(pr)
                                }
                            )
                        ) {
                            ForEach(visibleGroups, id: \.group) { entry in
                                Section {
                                    if isGroupExpanded(entry.group) {
                                        ForEach(entry.prs) { pr in
                                            PRRowView(
                                                pr: pr,
                                                onReview: onReviewPR.map { callback in { callback(pr) } }
                                            )
                                            .tag(pr.id)
                                        }
                                    }
                                } header: {
                                    groupHeader(entry.group, count: entry.prs.count)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 300)
            .frame(maxWidth: selectedPR == nil ? .infinity : CGFloat(prListWidth))

            // Right: PR detail drawer
            if let pr = selectedPR {
                ResizableDivider(width: $prListWidth)
                PRDetailDrawer(
                    pr: pr,
                    detail: detail,
                    onClose: { onSelectPR(nil) },
                    onApprove: { onApprove(pr) },
                    onComment: { body in onComment(pr, body) },
                    onRequestChanges: { body in onRequestChanges?(pr, body) },
                    onMerge: { strategy in onMerge?(pr, strategy) },
                    onToggleDraft: { onToggleDraft?(pr) },
                    onUpdateBranch: onUpdateBranch.map { callback in
                        { rebase in callback(pr, rebase) }
                    },
                    onSendToSession: onSendToSession.map { callback in
                        { context in callback(pr, context) }
                    },
                    onEnableAutoMerge: onEnableAutoMerge.map { callback in
                        { strategy in callback(pr, strategy) }
                    },
                    onDisableAutoMerge: onDisableAutoMerge.map { callback in
                        { callback(pr) }
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { onRefresh() }
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: PRTab) -> some View {
        let count = tabCount(tab)
        return Button(action: {
            selectedTab = tab
        }) {
            Text("\(tab.rawValue) (\(count))")
                .font(.subheadline)
                .fontWeight(selectedTab == tab ? .semibold : .regular)
                .foregroundColor(selectedTab == tab ? theme.chrome.accent : theme.chrome.textDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    // MARK: - Group Header

    private func groupHeader(_ group: PRGroup, count: Int) -> some View {
        Button(action: { toggleGroupExpanded(group) }) {
            HStack(spacing: 6) {
                Image(systemName: groupIcon(group))
                    .font(.callout)
                    .foregroundColor(groupColor(group))
                Text(group.rawValue)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("(\(count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isGroupExpanded(group) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grouping

enum PRGroup: String, CaseIterable {
    case needsAttention = "Needs Attention"
    case inProgress = "In Progress"
    case waitingForReview = "Waiting for Review"
    case ready = "Ready"
    case drafts = "Drafts"
}

/// Determine which group a PR belongs to.
///
/// Evaluation order: drafts first, then needsAttention → inProgress → waitingForReview → ready.
/// Package-internal for testability.
func prGroup(for pr: PullRequest) -> PRGroup {
    // Drafts always go to their own section
    if pr.isDraft { return .drafts }

    // Needs Attention: failed checks, changes requested, conflicts, or blocked
    if pr.checks.hasFailed
        || pr.reviewDecision == .changesRequested
        || pr.mergeable == .conflicting
        || pr.mergeStateStatus == .blocked
    {
        return .needsAttention
    }

    // In Progress: checks not yet all passed
    // Treat unenriched PRs (enrichedAt == nil, total == 0) as in-progress
    let checksEffectivelyPassed = pr.checks.allPassed || (pr.checks.total == 0 && pr.enrichedAt != nil)
    if !checksEffectivelyPassed {
        return .inProgress
    }

    // Waiting for Review: checks passed, but no approval yet
    if pr.reviewDecision == .pending || pr.reviewDecision == .none {
        return .waitingForReview
    }

    // Ready: checks passed + approved
    return .ready
}

// MARK: - PR Tab

public enum PRTab: String, CaseIterable, Sendable {
    case all = "All"
    case mine = "Mine"
    case reviewRequested = "Review Requests"
}

// MARK: - PR Row View

struct PRRowView: View {
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
                        .foregroundStyle(.secondary)
                    Text(pr.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(pr.repo)
                        .font(.caption)
                        .foregroundColor(theme.chrome.cyan)
                    Text(pr.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !pr.headBranch.isEmpty {
                        Text(pr.headBranch)
                            .font(.caption)
                            .foregroundColor(theme.chrome.accent)
                    }
                    Text(pr.ageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CheckSummaryBadge(checks: pr.checks)
                    ReviewDecisionBadge(decision: pr.reviewDecision)
                    MergeStatusBadge(mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus)
                }
            }

            Spacer()

            if pr.additions > 0 || pr.deletions > 0 {
                Text("+\(pr.additions) -\(pr.deletions)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .trailing)
            } else if pr.checks.total == 0 {
                // Unenriched — reserve space with loading indicator
                ProgressView()
                    .controlSize(.mini)
                    .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .opacity(pr.isDraft ? 0.5 : 1.0)
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
