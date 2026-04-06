# PR Dashboard Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul the PR dashboard with grouped triage sections, hybrid parallel fetch, client-side tab filtering with counts, Sessions toggle, TTL-based re-enrichment with immediate action feedback, and markdown rendering in PR detail.

**Architecture:** Incremental refactor — evolve existing `PullRequest` model, `PRManager`, `RunwayStore`, and `PRDashboardView` in place. No new view files. The data flows: PRManager fetches mine + review-requested in parallel → RunwayStore merges/deduplicates with origin tags → PRDashboardView filters client-side by tab → groups into Needs Attention / In Progress / Ready sections.

**Tech Stack:** SwiftUI, Swift Package Manager, GRDB/SQLite, `gh` CLI

---

### Task 1: Add `PROrigin` and `enrichedAt` to PullRequest Model

**Files:**
- Modify: `Sources/Models/PullRequest.swift`
- Modify: `Tests/ModelsTests/PullRequestTests.swift`

- [ ] **Step 1: Write failing tests for new fields**

Add to `Tests/ModelsTests/PullRequestTests.swift`:

```swift
// MARK: - PROrigin

@Test func prOriginRawValues() {
    #expect(PROrigin.mine.rawValue == "mine")
    #expect(PROrigin.reviewRequested.rawValue == "reviewRequested")
}

// MARK: - PullRequest Origin & Enrichment

@Test func pullRequestOriginDefaults() {
    let pr = PullRequest(number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main", author: "me", repo: "r")
    #expect(pr.origin.isEmpty)
    #expect(pr.enrichedAt == nil)
}

@Test func pullRequestNeedsEnrichmentWhenNil() {
    let pr = PullRequest(number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main", author: "me", repo: "r")
    #expect(pr.needsEnrichment == true)
}

@Test func pullRequestNeedsEnrichmentWhenStale() {
    var pr = PullRequest(number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main", author: "me", repo: "r")
    pr.enrichedAt = Date().addingTimeInterval(-600)  // 10 minutes ago
    #expect(pr.needsEnrichment == true)
}

@Test func pullRequestDoesNotNeedEnrichmentWhenFresh() {
    var pr = PullRequest(number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main", author: "me", repo: "r")
    pr.enrichedAt = Date().addingTimeInterval(-60)  // 1 minute ago
    #expect(pr.needsEnrichment == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PullRequestTests 2>&1 | tail -20`
Expected: compilation errors — `PROrigin`, `origin`, `enrichedAt`, `needsEnrichment` not defined.

- [ ] **Step 3: Add `PROrigin` enum and new fields to `PullRequest`**

In `Sources/Models/PullRequest.swift`, add after the `CheckSummary` struct:

```swift
// MARK: - PR Origin

public enum PROrigin: String, Codable, Sendable, Hashable {
    case mine
    case reviewRequested
}
```

Add two fields to `PullRequest` after `updatedAt`:

```swift
    public var enrichedAt: Date?
    public var origin: Set<PROrigin>
```

Add the parameters to the `init` with defaults:

```swift
        enrichedAt: Date? = nil,
        origin: Set<PROrigin> = []
```

And assign them in the init body:

```swift
        self.enrichedAt = enrichedAt
        self.origin = origin
```

Add the computed property after the init:

```swift
    public var needsEnrichment: Bool {
        guard let enrichedAt else { return true }
        return Date().timeIntervalSince(enrichedAt) > 300
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PullRequestTests 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/PullRequest.swift Tests/ModelsTests/PullRequestTests.swift
git commit -m "feat: add PROrigin, enrichedAt, and needsEnrichment to PullRequest model"
```

---

### Task 2: Add `fetchAllPRs()` to PRManager

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift`
- Modify: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write test for fetchAllPRs merging logic**

The actual `gh` calls can't be unit tested (they need auth), but we can test that `PRFilter` still works and add a test for the new method's existence. Add to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - PROrigin Integration

@Test func prOriginSetOperations() {
    // Verify Set<PROrigin> works as expected for dedup logic
    var origins: Set<PROrigin> = [.mine]
    origins.insert(.reviewRequested)
    #expect(origins.count == 2)
    #expect(origins.contains(.mine))
    #expect(origins.contains(.reviewRequested))
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter PRManagerTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 3: Add `fetchAllPRs()` method to PRManager**

In `Sources/GitHubOperations/PRManager.swift`, add after the existing `fetchPRs` method (around line 61):

```swift
    /// Fetch both "mine" and "review-requested" PRs in parallel, merge and deduplicate.
    /// Each PR gets an `origin` set indicating which queries returned it.
    public func fetchAllPRs() async throws -> [PullRequest] {
        async let minePRs = fetchPRs(filter: .mine)
        async let reviewPRs = fetchPRs(filter: .reviewRequested)

        let (mine, review) = try await (minePRs, reviewPRs)

        // Merge: deduplicate by ID, combine origins
        var merged: [String: PullRequest] = [:]
        for var pr in mine {
            pr.origin = [.mine]
            merged[pr.id] = pr
        }
        for var pr in review {
            pr.origin = [.reviewRequested]
            if var existing = merged[pr.id] {
                existing.origin.insert(.reviewRequested)
                merged[pr.id] = existing
            } else {
                merged[pr.id] = pr
            }
        }

        return Array(merged.values)
    }
```

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `swift test --filter PRManagerTests 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat: add fetchAllPRs() for parallel mine + review-requested fetch with dedup"
```

---

### Task 3: Update RunwayStore for Hybrid Fetch, TTL Enrichment, and Action Re-enrichment

**Files:**
- Modify: `Sources/App/RunwayStore.swift`

- [ ] **Step 1: Replace `prFilter` with `prTab` and add `sessionPRIDs`**

In `Sources/App/RunwayStore.swift`, replace line 28:

```swift
    var prFilter: PRFilter = .mine
```

with:

```swift
    var prTab: PRTab = .mine
```

Add after `sessionPRs` (around line 53):

```swift
    /// Set of PR IDs linked to active Runway sessions — used for the Sessions filter toggle.
    var sessionPRIDs: Set<String> {
        Set(sessionPRs.values.map(\.id))
    }
```

- [ ] **Step 2: Update `fetchPRs()` to use `fetchAllPRs()`**

Replace the entire `fetchPRs` method (lines 602-630) with:

```swift
    func fetchPRs() async {
        isLoadingPRs = true
        defer { isLoadingPRs = false }

        do {
            let freshPRs = try await prManager.fetchAllPRs()
            prLastFetched = Date()

            // Merge: keep enriched data from cache/previous enrichment where available
            let existingByID = Dictionary(pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            pullRequests = freshPRs.map { fresh in
                guard var existing = existingByID[fresh.id] else { return fresh }
                // Update fields that search refreshes
                existing.title = fresh.title
                existing.state = fresh.state
                existing.isDraft = fresh.isDraft
                existing.author = fresh.author
                existing.origin = fresh.origin
                return existing
            }

            Task { await enrichPRs() }
        } catch {
            print("[Runway] Failed to fetch PRs: \(error)")
            statusMessage = .error("PR fetch failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 3: Update `enrichPRs()` to use TTL instead of `checks.total == 0`**

Replace the filter condition in `enrichPRs()` (line 636):

```swift
        let toEnrich = pullRequests.filter { $0.needsEnrichment }
```

Add `enrichedAt = Date()` after each enrichment result is applied. In the merge loop (around line 673-684), after `updated[i].changedFiles = result.changedFiles`, add:

```swift
            updated[i].enrichedAt = Date()
```

- [ ] **Step 4: Add `reEnrichPR()` method**

Add after the `enrichPRs()` method:

```swift
    /// Re-enrich a single PR immediately (called after user actions like approve/merge).
    private func reEnrichPR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        guard let result = try? await prManager.enrichChecks(
            repo: pr.repo, number: pr.number, host: host
        ) else { return }

        if let idx = pullRequests.firstIndex(where: { $0.id == pr.id }) {
            pullRequests[idx].checks = result.checks
            pullRequests[idx].reviewDecision = result.reviewDecision
            if !result.headBranch.isEmpty {
                pullRequests[idx].headBranch = result.headBranch
                pullRequests[idx].baseBranch = result.baseBranch
            }
            pullRequests[idx].additions = result.additions
            pullRequests[idx].deletions = result.deletions
            pullRequests[idx].changedFiles = result.changedFiles
            pullRequests[idx].enrichedAt = Date()
        }

        try? database?.cachePRs(pullRequests)
    }
```

- [ ] **Step 5: Update action methods to call `reEnrichPR` instead of `fetchPRs`**

Update `approvePR` (line 792-800):

```swift
    func approvePR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.approve(repo: pr.repo, number: pr.number, host: host)
            statusMessage = .success("Approved #\(pr.number)")
            await reEnrichPR(pr)
        } catch {
            statusMessage = .error("Approve failed: \(error.localizedDescription)")
        }
    }
```

Update `requestChangesOnPR` (line 814-824):

```swift
    func requestChangesOnPR(_ pr: PullRequest, body: String) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.requestChanges(repo: pr.repo, number: pr.number, body: body, host: host)
            statusMessage = .success("Requested changes on #\(pr.number)")
            prDetail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number, host: host)
            await reEnrichPR(pr)
        } catch {
            statusMessage = .error("Request changes failed: \(error.localizedDescription)")
        }
    }
```

Update `mergePR` (line 826-835):

```swift
    func mergePR(_ pr: PullRequest, strategy: MergeStrategy = .squash) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.merge(repo: pr.repo, number: pr.number, strategy: strategy, host: host)
            statusMessage = .success("Merged #\(pr.number)")
            await fetchPRs()  // Merged PRs disappear from the list, so full refresh
        } catch {
            statusMessage = .error("Merge failed: \(error.localizedDescription)")
        }
    }
```

Update `togglePRDraft` (line 837-846):

```swift
    func togglePRDraft(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.toggleDraft(repo: pr.repo, number: pr.number, makeDraft: !pr.isDraft, host: host)
            statusMessage = .success(pr.isDraft ? "Marked #\(pr.number) as ready" : "Converted #\(pr.number) to draft")
            await fetchPRs()  // Draft status changes list membership, so full refresh
        } catch {
            statusMessage = .error("Draft toggle failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 6: Update poll to not reference `prFilter`**

In `startPRPoll()` (line 753), change:

```swift
                let fingerprint = await self.prManager.prFingerprint(filter: self.prFilter)
```

to:

```swift
                let fingerprint = await self.prManager.prFingerprint(filter: .mine)
```

Also update the initial fingerprint seed (line 96 area) if it references `prFilter` — change to `.mine`.

- [ ] **Step 7: Build to verify**

Run: `swift build 2>&1 | tail -20`
Expected: builds successfully. Any compilation errors from `prFilter` removal should be addressed (check `RunwayApp.swift` for references).

- [ ] **Step 8: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: hybrid fetch, TTL enrichment, and immediate re-enrich after actions"
```

---

### Task 4: Update RunwayApp Wiring

**Files:**
- Modify: `Sources/App/RunwayApp.swift`

- [ ] **Step 1: Update PR dashboard wiring to remove filter callback and add new params**

In `Sources/App/RunwayApp.swift`, find the `PRDashboardView` instantiation (around line 309). Replace the current wiring:

```swift
            PRDashboardView(
                pullRequests: store.pullRequests,
                selectedPRID: store.selectedPRID,
                detail: store.prDetail,
                isLoading: store.isLoadingPRs,
                sessionPRIDs: store.sessionPRIDs,
                selectedTab: Binding(
                    get: { store.prTab },
                    set: { store.prTab = $0 }
                ),
                onSelectPR: { pr in Task { await store.selectPR(pr) } },
                onRefresh: { Task { await store.fetchPRs() } },
                onApprove: { pr in Task { await store.approvePR(pr) } },
                onComment: { pr, body in Task { await store.commentOnPR(pr, body: body) } },
                onRequestChanges: { pr, body in Task { await store.requestChangesOnPR(pr, body: body) } },
                onMerge: { pr, strategy in Task { await store.mergePR(pr, strategy: strategy) } },
                onToggleDraft: { pr in Task { await store.togglePRDraft(pr) } },
                onSendToSession: { pr, _ in
                    if let sessionID = store.sessionPRs.first(where: { $0.value.id == pr.id })?.key {
                        store.selectSession(sessionID)
                        store.showSendBar = true
                    }
                },
                onReviewPR: { pr in store.reviewPR(pr) }
            )
```

Note: the `onFilterChange` callback is removed — tab switching is now client-side. The `selectedTab` binding and `sessionPRIDs` are new.

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -20`
Expected: will fail because `PRDashboardView` doesn't accept the new params yet. That's expected — Task 5 fixes it.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/RunwayApp.swift
git commit -m "feat: wire sessionPRIDs and tab binding to PR dashboard"
```

---

### Task 5: Refactor PRDashboardView — Grouped Sections, Tab Counts, Sessions Toggle

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift`

- [ ] **Step 1: Update `PRDashboardView` properties and init**

Replace the properties and init of `PRDashboardView` with:

```swift
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
    var onSendToSession: ((PullRequest, String) -> Void)?
    var onReviewPR: ((PullRequest) -> Void)?

    @AppStorage("prListWidth") private var prListWidth: Double = 380
    @AppStorage("hideDrafts") private var hideDrafts: Bool = false
    @AppStorage("showSessionPRsOnly") private var showSessionPRsOnly: Bool = false
    @AppStorage("prGroup_needsAttention") private var needsAttentionExpanded: Bool = true
    @AppStorage("prGroup_inProgress") private var inProgressExpanded: Bool = true
    @AppStorage("prGroup_ready") private var readyExpanded: Bool = true
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
        onSendToSession: ((PullRequest, String) -> Void)? = nil,
        onReviewPR: ((PullRequest) -> Void)? = nil
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
        self.onSendToSession = onSendToSession
        self.onReviewPR = onReviewPR
    }
```

- [ ] **Step 2: Add filtering and grouping logic**

Replace the `visiblePRs` computed property and add grouping types:

```swift
    private var selectedPR: PullRequest? {
        pullRequests.first(where: { $0.id == selectedPRID })
    }

    /// Filtering chain: tab → sessions → drafts
    private var filteredPRs: [PullRequest] {
        var prs = pullRequests

        // Tab filter
        switch selectedTab {
        case .mine:
            prs = prs.filter { $0.origin.contains(.mine) }
        case .reviewRequested:
            prs = prs.filter { $0.origin.contains(.reviewRequested) }
        case .all:
            break
        }

        // Sessions filter
        if showSessionPRsOnly {
            prs = prs.filter { sessionPRIDs.contains($0.id) }
        }

        // Draft filter
        if hideDrafts {
            prs = prs.filter { !$0.isDraft }
        }

        return prs
    }

    private func tabCount(_ tab: PRTab) -> Int {
        var prs = pullRequests
        switch tab {
        case .mine: prs = prs.filter { $0.origin.contains(.mine) }
        case .reviewRequested: prs = prs.filter { $0.origin.contains(.reviewRequested) }
        case .all: break
        }
        if showSessionPRsOnly { prs = prs.filter { sessionPRIDs.contains($0.id) } }
        if hideDrafts { prs = prs.filter { !$0.isDraft } }
        return prs.count
    }

    private enum PRGroup: String, CaseIterable {
        case needsAttention = "Needs Attention"
        case ready = "Ready"
        case inProgress = "In Progress"
    }

    private func group(for pr: PullRequest) -> PRGroup {
        // Priority order: needs attention first, then ready, everything else is in progress
        if pr.checks.hasFailed || pr.reviewDecision == .changesRequested {
            return .needsAttention
        }
        if pr.checks.allPassed && pr.reviewDecision == .approved {
            return .ready
        }
        return .inProgress
    }

    private func groupedPRs() -> [(group: PRGroup, prs: [PullRequest])] {
        let sorted = filteredPRs.sorted { $0.createdAt > $1.createdAt }
        let grouped = Dictionary(grouping: sorted) { group(for: $0) }
        // Return in display order, omitting empty groups
        return [PRGroup.needsAttention, .inProgress, .ready]
            .compactMap { g in
                guard let prs = grouped[g], !prs.isEmpty else { return nil }
                return (g, prs)
            }
    }

    private func isGroupExpanded(_ group: PRGroup) -> Bool {
        switch group {
        case .needsAttention: needsAttentionExpanded
        case .inProgress: inProgressExpanded
        case .ready: readyExpanded
        }
    }

    private func toggleGroupExpanded(_ group: PRGroup) {
        switch group {
        case .needsAttention: needsAttentionExpanded.toggle()
        case .inProgress: inProgressExpanded.toggle()
        case .ready: readyExpanded.toggle()
        }
    }

    private func groupColor(_ group: PRGroup) -> Color {
        switch group {
        case .needsAttention: theme.chrome.red
        case .inProgress: theme.chrome.yellow
        case .ready: theme.chrome.green
        }
    }

    private func groupIcon(_ group: PRGroup) -> String {
        switch group {
        case .needsAttention: "exclamationmark.triangle.fill"
        case .inProgress: "clock.fill"
        case .ready: "checkmark.circle.fill"
        }
    }
```

- [ ] **Step 3: Update the body to use grouped sections**

Replace the `body` computed property:

```swift
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

                    Button {
                        showSessionPRsOnly.toggle()
                    } label: {
                        Image(systemName: showSessionPRsOnly ? "play.rectangle.fill" : "play.rectangle")
                            .font(.caption)
                            .foregroundColor(showSessionPRsOnly ? theme.chrome.accent : theme.chrome.textDim)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(showSessionPRsOnly ? "Show all PRs" : "Show only session PRs")
                    .padding(.trailing, 4)

                    Button {
                        hideDrafts.toggle()
                    } label: {
                        Image(systemName: hideDrafts ? "eye.slash" : "eye")
                            .font(.caption)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(hideDrafts ? "Show drafts" : "Hide drafts")
                    .padding(.trailing, 4)

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(IconButtonStyle())
                    .padding(.trailing, 8)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(theme.chrome.surface)

                Divider()

                // PR list
                let groups = groupedPRs()
                if groups.isEmpty && !isLoading {
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
                    List(selection: Binding(
                        get: { selectedPRID },
                        set: { id in
                            let pr = pullRequests.first(where: { $0.id == id })
                            onSelectPR(pr)
                        }
                    )) {
                        ForEach(groups, id: \.group) { section in
                            Section {
                                if isGroupExpanded(section.group) {
                                    ForEach(section.prs) { pr in
                                        PRRowView(pr: pr, onReview: onReviewPR.map { callback in { callback(pr) } })
                                            .tag(pr.id)
                                    }
                                }
                            } header: {
                                groupHeader(section.group, count: section.prs.count)
                            }
                        }
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
                    onComment: { body in onComment(pr, body) },
                    onRequestChanges: { body in onRequestChanges?(pr, body) },
                    onMerge: { strategy in onMerge?(pr, strategy) },
                    onToggleDraft: { onToggleDraft?(pr) },
                    onSendToSession: onSendToSession.map { callback in
                        { context in callback(pr, context) }
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { onRefresh() }
    }
```

- [ ] **Step 4: Update `tabButton` to show counts and use binding**

Replace the `tabButton` method:

```swift
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
    }
```

- [ ] **Step 5: Add groupHeader view**

Add after `tabButton`:

```swift
    private func groupHeader(_ group: PRGroup, count: Int) -> some View {
        Button {
            toggleGroupExpanded(group)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: groupIcon(group))
                    .font(.caption2)
                    .foregroundColor(groupColor(group))
                Text(group.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(groupColor(group))
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(theme.chrome.textDim)
                Spacer()
                Image(systemName: isGroupExpanded(group) ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(theme.chrome.textDim)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 6: Remove the old `onFilterChange` from PRTab enum area**

The `PRTab` enum stays but remove the `onFilterChange` callback from the struct properties since tabs are now client-side. The enum definition is fine:

```swift
public enum PRTab: String, CaseIterable, Sendable {
    case all = "All"
    case mine = "Mine"
    case reviewRequested = "Review Requests"
}
```

- [ ] **Step 7: Build and verify**

Run: `swift build 2>&1 | tail -20`
Expected: builds successfully.

- [ ] **Step 8: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift
git commit -m "feat: grouped PR sections, client-side tab filtering with counts, sessions toggle"
```

---

### Task 6: Add Markdown Rendering to PR Detail Drawer

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDetailDrawer.swift`

- [ ] **Step 1: Add markdown text helper**

In `PRDetailDrawer.swift`, add a private helper method before the `stripHTML` method:

```swift
    /// Render a markdown string as styled Text using AttributedString.
    /// Falls back to plain text if markdown parsing fails.
    private func markdownText(_ source: String) -> Text {
        if let attributed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(source)
    }

    /// Render a full markdown document (PR body — supports block elements like headings, lists).
    private func markdownBody(_ source: String) -> Text {
        if let attributed = try? AttributedString(markdown: source) {
            return Text(attributed)
        }
        return Text(source)
    }
```

- [ ] **Step 2: Update overviewTab to use markdown rendering**

Replace the `overviewTab` computed property:

```swift
    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let body = detail?.body, !body.isEmpty {
                    markdownBody(body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
                } else {
                    Text("No description provided")
                        .foregroundColor(theme.chrome.textDim)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
```

- [ ] **Step 3: Update review and comment cards to use markdown**

In `reviewCard`, replace the body text rendering:

```swift
                if !review.body.isEmpty {
                    markdownText(review.body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                }
```

In `commentCard`, replace the body text rendering:

```swift
            markdownText(comment.body)
                .font(.body)
                .foregroundColor(theme.chrome.text)
                .textSelection(.enabled)
```

- [ ] **Step 4: Build to verify**

Run: `swift build 2>&1 | tail -20`
Expected: builds successfully.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/PRDashboard/PRDetailDrawer.swift
git commit -m "feat: markdown rendering for PR body, review bodies, and comments"
```

---

### Task 7: Database Migration v10 for enrichedAt and origin

**Files:**
- Modify: `Sources/Persistence/Database.swift`

Note: The PR cache stores `PullRequest` as JSON blobs, so `enrichedAt` and `origin` are automatically included when encoding/decoding since they're `Codable` fields on `PullRequest`. No schema change is needed for the `pr_cache` table itself — the JSON blob already handles new fields gracefully (missing fields decode to their defaults: `nil` for `enrichedAt`, `[]` for `origin`).

However, we should verify this works correctly.

- [ ] **Step 1: Write a test to verify cached PRs round-trip with new fields**

Add to `Tests/PersistenceTests/DatabaseTests.swift`:

```swift
@Test func prCacheRoundTripsNewFields() throws {
    let db = try Database(inMemory: true)

    var pr = PullRequest(
        number: 99, title: "Test", state: .open, headBranch: "feature", baseBranch: "main",
        author: "alice", repo: "owner/repo"
    )
    pr.enrichedAt = Date()
    pr.origin = [.mine, .reviewRequested]

    try db.cachePR(pr)

    let cached = try db.cachedPRs(maxAge: 3600)
    #expect(cached.count == 1)
    #expect(cached.first?.enrichedAt != nil)
    #expect(cached.first?.origin == [.mine, .reviewRequested])
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter DatabaseTests/prCacheRoundTripsNewFields 2>&1 | tail -20`
Expected: PASS — JSON encoding/decoding handles the new `Codable` fields automatically.

- [ ] **Step 3: Commit**

```bash
git add Tests/PersistenceTests/DatabaseTests.swift
git commit -m "test: verify PR cache round-trips enrichedAt and origin fields"
```

---

### Task 8: Full Build and Integration Test

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: all tests pass.

- [ ] **Step 2: Run full build**

Run: `swift build 2>&1 | tail -20`
Expected: builds with no errors.

- [ ] **Step 3: Fix any compilation errors**

Address any remaining references to `prFilter` or `onFilterChange` that weren't caught in earlier tasks. Common places to check:
- `Sources/App/RunwayApp.swift` — any remaining `PRFilter` references
- `Sources/App/RunwayStore.swift` — the `loadState()` or initial fingerprint code

- [ ] **Step 4: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve remaining compilation issues from PR dashboard refactor"
```
