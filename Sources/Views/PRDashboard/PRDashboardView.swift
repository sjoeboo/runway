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
    @AppStorage("prSortField") private var sortFieldRaw: String = PRSortField.age.rawValue
    @AppStorage("prSortOrder") private var sortOrderRaw: String = PRSortOrder.descending.rawValue
    @AppStorage("prFilterRepo") private var filterRepo: String = ""
    @AppStorage("prFilterAuthor") private var filterAuthor: String = ""
    @AppStorage("prFilterAge") private var filterAgeRaw: String = PRAgeBucket.any.rawValue
    @AppStorage("prFilterChecks") private var filterChecksRaw: String = ""
    @AppStorage("prFilterReview") private var filterReviewRaw: String = ""
    @AppStorage("prFilterMerge") private var filterMergeRaw: String = ""
    @Environment(\.theme) private var theme

    private var sortField: PRSortField {
        get { PRSortField(rawValue: sortFieldRaw) ?? .age }
        nonmutating set { sortFieldRaw = newValue.rawValue }
    }

    private var sortOrder: PRSortOrder {
        get { PRSortOrder(rawValue: sortOrderRaw) ?? .descending }
        nonmutating set { sortOrderRaw = newValue.rawValue }
    }

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
        var result = applyFilters(to: pullRequests, tab: selectedTab)
        let currentFilter = filterState
        if currentFilter.isActive {
            result = result.filter { currentFilter.matches($0) }
        }
        return result
    }

    private func tabCount(_ tab: PRTab) -> Int {
        var prs = applyFilters(to: pullRequests, tab: tab)
        if hideDrafts { prs = prs.filter { !$0.isDraft } }
        let currentFilter = filterState
        if currentFilter.isActive {
            prs = prs.filter { currentFilter.matches($0) }
        }
        return prs.count
    }

    // MARK: - Grouping

    private func groupedPRs() -> [(group: PRGroup, prs: [PullRequest])] {
        var byGroup: [PRGroup: [PullRequest]] = [:]
        for pr in filteredPRs {
            let g = prGroup(for: pr)
            byGroup[g, default: []].append(pr)
        }
        let currentSortField = sortField
        let currentSortOrder = sortOrder
        return PRGroup.allCases.compactMap { g in
            guard var prs = byGroup[g], !prs.isEmpty else { return nil }
            prs = sortPRs(prs, by: currentSortField, order: currentSortOrder)
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

                // Filter bar
                PRFilterBar(
                    filter: Binding(
                        get: { filterState },
                        set: { filterState = $0 }
                    ),
                    pullRequests: filteredPRs
                )

                Divider()

                // Column headers
                PRColumnHeader(
                    sortField: Binding(
                        get: { sortField },
                        set: { sortField = $0 }
                    ),
                    sortOrder: Binding(
                        get: { sortOrder },
                        set: { sortOrder = $0 }
                    )
                )

                Divider()

                // PR list
                if filteredPRs.isEmpty && !isLoading {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "pull.request")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        if filterState.isActive {
                            Text("No PRs match current filters")
                                .foregroundStyle(.secondary)
                            Button("Clear Filters") { filterState = PRFilterState() }
                                .controlSize(.small)
                        } else {
                            Text("No pull requests")
                                .foregroundStyle(.secondary)
                            Button("Refresh") { onRefresh() }
                                .controlSize(.small)
                        }
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
        .task { onRefresh() }
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: PRTab) -> some View {
        let count = tabCount(tab)
        return Button(action: {
            selectedTab = tab
        }) {
            Text("\(tab.rawValue) (\(count))")
                .font(.callout)
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
        HStack(spacing: 0) {
            // Title column (flexible)
            HStack(spacing: 4) {
                stateBadge
                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pr.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Repo column
            Text(repoShortName)
                .font(.caption)
                .foregroundColor(theme.chrome.cyan)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            // Author column
            Text(pr.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)

            // Age column
            Text(pr.ageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            // Checks column
            CheckSummaryBadge(checks: pr.checks)
                .frame(width: 55, alignment: .leading)

            // Review column
            ReviewDecisionBadge(decision: pr.reviewDecision)
                .frame(width: 55, alignment: .leading)

            // Merge column
            MergeStatusBadge(mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus)
                .frame(width: 65, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .opacity(pr.isDraft ? 0.5 : 1.0)
        .contextMenu {
            if let onReview {
                Button("Open Review Session") { onReview() }
            }
        }
    }

    /// Extract short repo name from "owner/repo" format.
    private var repoShortName: String {
        if let slashIndex = pr.repo.lastIndex(of: "/") {
            return String(pr.repo[pr.repo.index(after: slashIndex)...])
        }
        return pr.repo
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
