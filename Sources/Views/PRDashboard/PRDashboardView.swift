import GitHubOperations
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
    var onClosePR: ((PullRequest) -> Void)?
    var onAssignToMe: ((PullRequest) -> Void)?
    var onUnassignMe: ((PullRequest) -> Void)?
    var onToggleAssignee: ((PullRequest, String) -> Void)?
    var onLoadCollaborators: ((String) -> Void)?
    var myLoginForHost: ((String?) -> String?)?
    var collaboratorsForRepo: ((String) -> [Collaborator])?

    @AppStorage("prListWidth") private var prListWidth: Double = 380
    @AppStorage("hideDrafts") private var hideDrafts: Bool = false
    @AppStorage("showSessionPRsOnly") private var showSessionPRsOnly: Bool = false
    @AppStorage("prFilterRepo") private var filterRepo: String = ""
    @AppStorage("prFilterAuthor") private var filterAuthor: String = ""
    @AppStorage("prFilterAge") private var filterAgeRaw: String = PRAgeBucket.any.rawValue
    @AppStorage("prFilterChecks") private var filterChecksRaw: String = ""
    @AppStorage("prFilterReview") private var filterReviewRaw: String = ""
    @AppStorage("prFilterMerge") private var filterMergeRaw: String = ""
    @State private var tableSortOrder: [KeyPathComparator<PullRequest>] = [
        KeyPathComparator(\.createdAt, order: .reverse)
    ]
    @Environment(\.theme) private var theme

    private var filterState: PRFilterState {
        get {
            var state = PRFilterState()
            state.repo = filterRepo.isEmpty ? nil : filterRepo
            state.author = filterAuthor.isEmpty ? nil : filterAuthor
            state.ageBucket = PRAgeBucket(rawValue: filterAgeRaw) ?? .any
            state.checks = CheckStatus(rawValue: filterChecksRaw)
            state.review = filterReviewRaw.isEmpty ? nil : ReviewDecision(rawValue: filterReviewRaw)
            state.mergeFilter = filterMergeRaw.isEmpty ? nil : PRMergeFilter(rawValue: filterMergeRaw)
            return state
        }
        nonmutating set {
            filterRepo = newValue.repo ?? ""
            filterAuthor = newValue.author ?? ""
            filterAgeRaw = newValue.ageBucket.rawValue
            filterChecksRaw = newValue.checks?.rawValue ?? ""
            filterReviewRaw = newValue.review?.rawValue ?? ""
            filterMergeRaw = newValue.mergeFilter?.rawValue ?? ""
        }
    }

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
        onDisableAutoMerge: ((PullRequest) -> Void)? = nil,
        onClosePR: ((PullRequest) -> Void)? = nil,
        onAssignToMe: ((PullRequest) -> Void)? = nil,
        onUnassignMe: ((PullRequest) -> Void)? = nil,
        onToggleAssignee: ((PullRequest, String) -> Void)? = nil,
        onLoadCollaborators: ((String) -> Void)? = nil,
        myLoginForHost: ((String?) -> String?)? = nil,
        collaboratorsForRepo: ((String) -> [Collaborator])? = nil
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
        self.onClosePR = onClosePR
        self.onAssignToMe = onAssignToMe
        self.onUnassignMe = onUnassignMe
        self.onToggleAssignee = onToggleAssignee
        self.onLoadCollaborators = onLoadCollaborators
        self.myLoginForHost = myLoginForHost
        self.collaboratorsForRepo = collaboratorsForRepo
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
        var result = applyFilters(to: pullRequests, tab: selectedTab)
        let currentFilter = filterState
        if currentFilter.isActive {
            result = result.filter { currentFilter.matches($0) }
        }
        return result
    }

    /// Pre-compute all tab counts in a single pass over pullRequests.
    /// Previously `tabCount(_ tab:)` was called 3x per body evaluation, each re-filtering the full array.
    private var tabCounts: [PRTab: Int] {
        let currentFilter = filterState
        var counts: [PRTab: Int] = [:]
        for tab in PRTab.allCases {
            var prs = applyFilters(to: pullRequests, tab: tab)
            if hideDrafts { prs = prs.filter { !$0.isDraft } }
            if currentFilter.isActive {
                prs = prs.filter { currentFilter.matches($0) }
            }
            counts[tab] = prs.count
        }
        return counts
    }

    // MARK: - Sorted PRs

    private var sortedPRs: [PullRequest] {
        var prs = filteredPRs
        if hideDrafts { prs = prs.filter { !$0.isDraft } }
        return prs.sorted(using: tableSortOrder)
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 0) {
            // Left: PR table
            prTable
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
                    },
                    onClosePR: onClosePR.map { callback in
                        { callback(pr) }
                    },
                    onAssignToMe: onAssignToMe.map { callback in
                        { callback(pr) }
                    },
                    onUnassignMe: onUnassignMe.map { callback in
                        { callback(pr) }
                    },
                    onToggleAssignee: onToggleAssignee.map { callback in
                        { login in callback(pr, login) }
                    },
                    onLoadCollaborators: onLoadCollaborators.map { callback in
                        { callback(pr.repo) }
                    },
                    myLogin: myLoginForHost?(hostFromURL(pr.url)),
                    collaborators: collaboratorsForRepo?(pr.repo) ?? []
                )
                .frame(maxWidth: .infinity)
            }
        }
        .task { onRefresh() }
    }

    // MARK: - PR Table

    private var prTable: some View {
        Table(
            of: PullRequest.self,
            selection: Binding(
                get: { selectedPRID },
                set: { id in
                    let pr = sortedPRs.first(where: { $0.id == id })
                    onSelectPR(pr)
                }
            ),
            sortOrder: $tableSortOrder
        ) {
            TableColumn("Title", value: \.title) { pr in
                HStack(spacing: 4) {
                    prStateBadge(pr)
                    Text("#\(pr.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pr.title)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            .width(min: 150)

            TableColumn("Repo", value: \.repo) { pr in
                Text(prRepoShortName(pr))
                    .font(.caption)
                    .foregroundColor(theme.chrome.cyan)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 130, max: 250)

            TableColumn("Author", value: \.author) { pr in
                Text(pr.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 90, max: 200)

            TableColumn("Age", value: \.createdAt) { pr in
                Text(pr.ageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 60, max: 80)

            TableColumn("Checks", value: \.checksPassRatio) { pr in
                if pr.checks.total > 0 {
                    Text("\(pr.checks.passed)/\(pr.checks.total)")
                        .font(.caption)
                        .foregroundColor(
                            pr.checks.allPassed
                                ? theme.chrome.green
                                : pr.checks.hasFailed ? theme.chrome.red : theme.chrome.yellow
                        )
                }
            }
            .width(min: 40, ideal: 55, max: 80)

            TableColumn("Review", value: \.reviewSortRank) { pr in
                Text(reviewLabel(pr.reviewDecision))
                    .font(.caption)
                    .foregroundColor(reviewColor(pr.reviewDecision))
            }
            .width(min: 50, ideal: 70, max: 100)

            TableColumn("Merge", value: \.mergeSortRank) { pr in
                Text(mergeLabel(pr))
                    .font(.caption)
                    .foregroundColor(mergeColor(pr))
            }
            .width(min: 50, ideal: 70, max: 100)
        } rows: {
            ForEach(sortedPRs) { pr in
                TableRow(pr)
                    .contextMenu {
                        if let onReviewPR {
                            Button("Open Review Session") { onReviewPR(pr) }
                        }
                        if let onClosePR, pr.state == .open || pr.state == .draft {
                            Divider()
                            Button("Close PR", role: .destructive) { onClosePR(pr) }
                        }
                    }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .safeAreaInset(edge: .top, spacing: 0) {
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

                    Button {
                        showSessionPRsOnly.toggle()
                    } label: {
                        Image(systemName: showSessionPRsOnly ? "terminal.fill" : "terminal")
                            .font(.callout)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(
                        showSessionPRsOnly ? "Showing session PRs only" : "Show only session PRs"
                    )
                    .accessibilityLabel(
                        showSessionPRsOnly
                            ? "Showing session PRs only" : "Show only session PRs"
                    )
                    .padding(.trailing, 4)

                    Button {
                        hideDrafts.toggle()
                    } label: {
                        Image(systemName: hideDrafts ? "eye.slash" : "eye")
                            .font(.callout)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(hideDrafts ? "Show drafts" : "Hide drafts")
                    .accessibilityLabel(hideDrafts ? "Show drafts" : "Hide drafts")
                    .padding(.trailing, 4)

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout)
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Refresh pull requests")
                    .padding(.trailing, 8)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(theme.chrome.surface)

                Divider()

                // Filter bar
                PRFilterBar(
                    filter: Binding(
                        get: { filterState },
                        set: { filterState = $0 }
                    ),
                    pullRequests: filteredPRs
                )

                Divider()
            }
        }
    }

    // MARK: - Cell Helpers

    private func prStateBadge(_ pr: PullRequest) -> some View {
        PRStateDot(state: pr.state)
    }

    private func hostFromURL(_ url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host else { return nil }
        return host == "github.com" ? nil : host
    }

    private func prRepoShortName(_ pr: PullRequest) -> String {
        if let idx = pr.repo.lastIndex(of: "/") {
            return String(pr.repo[pr.repo.index(after: idx)...])
        }
        return pr.repo
    }

    private func reviewLabel(_ decision: ReviewDecision) -> String {
        switch decision {
        case .approved: "Approved"
        case .changesRequested: "Changes"
        case .pending: "Review"
        case .none: ""
        }
    }

    private func reviewColor(_ decision: ReviewDecision) -> Color {
        switch decision {
        case .approved: theme.chrome.green
        case .changesRequested: theme.chrome.orange
        case .pending: theme.chrome.yellow
        case .none: .clear
        }
    }

    private func mergeLabel(_ pr: PullRequest) -> String {
        if pr.mergeable == .conflicting { return "Conflicts" }
        switch pr.mergeStateStatus {
        case .blocked: return "Blocked"
        case .behind: return "Behind"
        case .clean, .hasHooks: return "Clean"
        case .dirty: return "Dirty"
        case .unstable: return "Unstable"
        default: return ""
        }
    }

    private func mergeColor(_ pr: PullRequest) -> Color {
        if pr.mergeable == .conflicting { return theme.chrome.red }
        switch pr.mergeStateStatus {
        case .blocked, .dirty: return theme.chrome.orange
        case .behind, .unstable: return theme.chrome.yellow
        case .clean, .hasHooks: return theme.chrome.green
        default: return .clear
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: PRTab) -> some View {
        TabBarButton(
            title: tab.rawValue,
            count: tabCounts[tab] ?? 0,
            isActive: selectedTab == tab
        ) {
            selectedTab = tab
        }
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
