# PR Column Sorting & Filtering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add sortable columns and a persistent filter bar to the PR dashboard, keeping the existing group-based layout.

**Architecture:** New sort/filter types live in `Sources/Views/PRDashboard/PRSortFilter.swift`. Two new view files (`PRFilterBar.swift`, `PRColumnHeader.swift`) slot into the existing `PRDashboardView` hierarchy above the grouped list. `PRRowView` is refactored from a free-form HStack to a grid-aligned row. All state persists via `@AppStorage`.

**Tech Stack:** SwiftUI, Swift Testing framework, `@AppStorage` for persistence, existing Models/Theme modules.

---

### Task 1: Add PRSortFilter types with tests

**Files:**
- Create: `Sources/Views/PRDashboard/PRSortFilter.swift`
- Create: `Tests/ViewsTests/PRSortFilterTests.swift`

- [ ] **Step 1: Write failing tests for PRFilterState.matches()**

In `Tests/ViewsTests/PRSortFilterTests.swift`:

```swift
import Foundation
import Testing

@testable import Models
@testable import Views

// MARK: - PRAgeBucket Tests

@Test func ageBucketAnyMatchesEverything() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "backend-api",
        createdAt: Date().addingTimeInterval(-86400 * 60)
    )
    var filter = PRFilterState()
    filter.ageBucket = .any
    #expect(filter.matches(pr))
}

@Test func ageBucketLast24hFiltersOldPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 2)
    )
    let newPR = PullRequest(
        number: 2, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-3600)
    )
    var filter = PRFilterState()
    filter.ageBucket = .last24h
    #expect(!filter.matches(oldPR))
    #expect(filter.matches(newPR))
}

@Test func ageBucketLast7dFiltersOlderPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 10)
    )
    let recentPR = PullRequest(
        number: 2, title: "Recent", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 3)
    )
    var filter = PRFilterState()
    filter.ageBucket = .last7d
    #expect(!filter.matches(oldPR))
    #expect(filter.matches(recentPR))
}

@Test func ageBucketLast30dFiltersOlderPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 45)
    )
    let recentPR = PullRequest(
        number: 2, title: "Recent", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 15)
    )
    var filter = PRFilterState()
    filter.ageBucket = .last30d
    #expect(!filter.matches(oldPR))
    #expect(filter.matches(recentPR))
}

@Test func ageBucketOlderThan30dFiltersRecentPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 45)
    )
    let recentPR = PullRequest(
        number: 2, title: "Recent", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 5)
    )
    var filter = PRFilterState()
    filter.ageBucket = .olderThan30d
    #expect(filter.matches(oldPR))
    #expect(!filter.matches(recentPR))
}

// MARK: - Repo & Author Filter Tests

@Test func repoFilterMatchesExactRepo() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "owner/backend-api"
    )
    var filter = PRFilterState()
    filter.repo = "owner/backend-api"
    #expect(filter.matches(pr))
    filter.repo = "owner/web-app"
    #expect(!filter.matches(pr))
}

@Test func authorFilterMatchesExactAuthor() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r"
    )
    var filter = PRFilterState()
    filter.author = "alice"
    #expect(filter.matches(pr))
    filter.author = "bob"
    #expect(!filter.matches(pr))
}

@Test func nilRepoAndAuthorMatchAll() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r"
    )
    let filter = PRFilterState()
    #expect(filter.repo == nil)
    #expect(filter.author == nil)
    #expect(filter.matches(pr))
}

// MARK: - Checks Filter Tests

@Test func checksFilterMatchesByStatus() {
    let passingPR = PullRequest(
        number: 1, title: "Pass", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0)
    )
    let failingPR = PullRequest(
        number: 2, title: "Fail", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        checks: CheckSummary(passed: 3, failed: 2, pending: 0)
    )
    let pendingPR = PullRequest(
        number: 3, title: "Pending", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        checks: CheckSummary(passed: 0, failed: 0, pending: 3)
    )
    var filter = PRFilterState()

    filter.checks = .passed
    #expect(filter.matches(passingPR))
    #expect(!filter.matches(failingPR))
    #expect(!filter.matches(pendingPR))

    filter.checks = .failed
    #expect(!filter.matches(passingPR))
    #expect(filter.matches(failingPR))
    #expect(!filter.matches(pendingPR))

    filter.checks = .pending
    #expect(!filter.matches(passingPR))
    #expect(!filter.matches(failingPR))
    #expect(filter.matches(pendingPR))
}

// MARK: - Review & Merge Filter Tests

@Test func reviewFilterMatchesByDecision() {
    let approvedPR = PullRequest(
        number: 1, title: "Approved", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .approved
    )
    var filter = PRFilterState()
    filter.review = .approved
    #expect(filter.matches(approvedPR))
    filter.review = .changesRequested
    #expect(!filter.matches(approvedPR))
}

@Test func mergeFilterMatchesClean() {
    let cleanPR = PullRequest(
        number: 1, title: "Clean", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", mergeStateStatus: .clean
    )
    var filter = PRFilterState()
    filter.mergeFilter = .clean
    #expect(filter.matches(cleanPR))
    filter.mergeFilter = .blocked
    #expect(!filter.matches(cleanPR))
}

@Test func mergeFilterConflictsMatchesBothMergeableAndStatus() {
    let conflictingPR = PullRequest(
        number: 1, title: "Conflicts", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", mergeable: .conflicting
    )
    let dirtyPR = PullRequest(
        number: 2, title: "Dirty", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", mergeStateStatus: .dirty
    )
    var filter = PRFilterState()
    filter.mergeFilter = .conflicts
    #expect(filter.matches(conflictingPR))
    #expect(filter.matches(dirtyPR))
}

// MARK: - Combined (AND) Filter Tests

@Test func multipleFiltersApplyAsAND() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "owner/backend-api",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .approved
    )
    var filter = PRFilterState()
    filter.repo = "owner/backend-api"
    filter.author = "alice"
    #expect(filter.matches(pr))

    // Change author to mismatch — AND means both must match
    filter.author = "bob"
    #expect(!filter.matches(pr))
}

// MARK: - isActive Tests

@Test func isActiveReturnsFalseForDefaultFilter() {
    let filter = PRFilterState()
    #expect(!filter.isActive)
}

@Test func isActiveReturnsTrueWhenAnyFilterSet() {
    var filter = PRFilterState()
    filter.repo = "r"
    #expect(filter.isActive)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PRSortFilterTests 2>&1 | tail -20`
Expected: Compilation failure — `PRFilterState` and related types don't exist yet.

- [ ] **Step 3: Implement PRSortFilter types**

Create `Sources/Views/PRDashboard/PRSortFilter.swift`:

```swift
import Foundation
import Models

// MARK: - Sort Types

public enum PRSortField: String, CaseIterable, Sendable {
    case title
    case repo
    case author
    case age
    case checks
    case review
    case mergeStatus

    public var label: String {
        switch self {
        case .title: "Title"
        case .repo: "Repo"
        case .author: "Author"
        case .age: "Age"
        case .checks: "Checks"
        case .review: "Review"
        case .mergeStatus: "Merge"
        }
    }
}

public enum PRSortOrder: String, Sendable {
    case ascending
    case descending
}

// MARK: - Age Bucket

public enum PRAgeBucket: String, CaseIterable, Sendable {
    case any = "Any"
    case last24h = "Last 24h"
    case last7d = "Last 7 days"
    case last30d = "Last 30 days"
    case olderThan30d = "Older than 30 days"

    func matches(createdAt: Date) -> Bool {
        let age = Date().timeIntervalSince(createdAt)
        switch self {
        case .any: return true
        case .last24h: return age <= 86400
        case .last7d: return age <= 86400 * 7
        case .last30d: return age <= 86400 * 30
        case .olderThan30d: return age > 86400 * 30
        }
    }
}

// MARK: - Merge Filter

public enum PRMergeFilter: String, CaseIterable, Sendable {
    case clean = "Clean"
    case conflicts = "Conflicts"
    case behind = "Behind"
    case blocked = "Blocked"

    public func matches(mergeable: MergeableState?, mergeStateStatus: MergeStateStatus?) -> Bool {
        switch self {
        case .clean:
            return mergeStateStatus == .clean || mergeStateStatus == .hasHooks
        case .conflicts:
            return mergeable == .conflicting || mergeStateStatus == .dirty
        case .behind:
            return mergeStateStatus == .behind
        case .blocked:
            return mergeStateStatus == .blocked
        }
    }
}

// MARK: - Filter State

public struct PRFilterState: Sendable {
    public var repo: String?
    public var author: String?
    public var ageBucket: PRAgeBucket = .any
    public var checks: CheckStatus?
    public var review: ReviewDecision?
    public var mergeFilter: PRMergeFilter?

    public init() {}

    public var isActive: Bool {
        repo != nil || author != nil || ageBucket != .any
            || checks != nil || review != nil || mergeFilter != nil
    }

    public func matches(_ pr: PullRequest) -> Bool {
        if let repo, pr.repo != repo { return false }
        if let author, pr.author != author { return false }
        if !ageBucket.matches(createdAt: pr.createdAt) { return false }
        if let checks {
            switch checks {
            case .passed: if !pr.checks.allPassed { return false }
            case .failed: if !pr.checks.hasFailed { return false }
            case .pending:
                if pr.checks.pending == 0 || pr.checks.hasFailed { return false }
            }
        }
        if let review, pr.reviewDecision != review { return false }
        if let mergeFilter {
            if !mergeFilter.matches(mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus) {
                return false
            }
        }
        return true
    }

    public mutating func clear() {
        repo = nil
        author = nil
        ageBucket = .any
        checks = nil
        review = nil
        mergeFilter = nil
    }
}

// MARK: - Sorting

/// Sort an array of PRs by the given field and order.
public func sortPRs(_ prs: [PullRequest], by field: PRSortField, order: PRSortOrder) -> [PullRequest] {
    let sorted = prs.sorted { a, b in
        switch field {
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .repo:
            return a.repo.localizedCaseInsensitiveCompare(b.repo) == .orderedAscending
        case .author:
            return a.author.localizedCaseInsensitiveCompare(b.author) == .orderedAscending
        case .age:
            // Ascending = oldest first (smallest date)
            return a.createdAt < b.createdAt
        case .checks:
            let aRatio = a.checks.total > 0 ? Double(a.checks.passed) / Double(a.checks.total) : 0
            let bRatio = b.checks.total > 0 ? Double(b.checks.passed) / Double(b.checks.total) : 0
            if aRatio != bRatio { return aRatio < bRatio }
            return a.checks.total < b.checks.total
        case .review:
            return reviewSortOrder(a.reviewDecision) < reviewSortOrder(b.reviewDecision)
        case .mergeStatus:
            return mergeSortOrder(a.mergeStateStatus) < mergeSortOrder(b.mergeStateStatus)
        }
    }
    return order == .ascending ? sorted : sorted.reversed()
}

private func reviewSortOrder(_ decision: ReviewDecision) -> Int {
    switch decision {
    case .approved: 0
    case .pending: 1
    case .none: 2
    case .changesRequested: 3
    }
}

private func mergeSortOrder(_ status: MergeStateStatus?) -> Int {
    switch status {
    case .clean, .hasHooks: 0
    case .behind: 1
    case .unstable: 2
    case .dirty: 3
    case .blocked: 4
    case .unknown, .none: 5
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PRSortFilterTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Add sorting tests**

Append to `Tests/ViewsTests/PRSortFilterTests.swift`:

```swift
// MARK: - Sorting Tests

@Test func sortByAgeAscendingReturnsOldestFirst() {
    let old = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 10)
    )
    let new = PullRequest(
        number: 2, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-3600)
    )
    let sorted = sortPRs([new, old], by: .age, order: .ascending)
    #expect(sorted[0].number == 1)
    #expect(sorted[1].number == 2)
}

@Test func sortByAgeDescendingReturnsNewestFirst() {
    let old = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 10)
    )
    let new = PullRequest(
        number: 2, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-3600)
    )
    let sorted = sortPRs([old, new], by: .age, order: .descending)
    #expect(sorted[0].number == 2)
    #expect(sorted[1].number == 1)
}

@Test func sortByRepoAlphabetical() {
    let prA = PullRequest(
        number: 1, title: "A", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "z-repo"
    )
    let prB = PullRequest(
        number: 2, title: "B", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "a-repo"
    )
    let sorted = sortPRs([prA, prB], by: .repo, order: .ascending)
    #expect(sorted[0].number == 2)
    #expect(sorted[1].number == 1)
}

@Test func sortByAuthorAlphabetical() {
    let prA = PullRequest(
        number: 1, title: "A", state: .open, headBranch: "f", baseBranch: "main",
        author: "zara", repo: "r"
    )
    let prB = PullRequest(
        number: 2, title: "B", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r"
    )
    let sorted = sortPRs([prA, prB], by: .author, order: .ascending)
    #expect(sorted[0].number == 2)
    #expect(sorted[1].number == 1)
}

@Test func sortByReviewPutsApprovedFirst() {
    let approved = PullRequest(
        number: 1, title: "A", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .approved
    )
    let changes = PullRequest(
        number: 2, title: "B", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .changesRequested
    )
    let pending = PullRequest(
        number: 3, title: "C", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .pending
    )
    let sorted = sortPRs([changes, pending, approved], by: .review, order: .ascending)
    #expect(sorted[0].number == 1) // approved
    #expect(sorted[1].number == 3) // pending
    #expect(sorted[2].number == 2) // changes
}
```

- [ ] **Step 6: Run all sort/filter tests**

Run: `swift test --filter PRSortFilterTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Views/PRDashboard/PRSortFilter.swift Tests/ViewsTests/PRSortFilterTests.swift
git commit -m "feat: add PRSortFilter types with filtering and sorting logic

Introduces PRSortField, PRSortOrder, PRAgeBucket, PRFilterState,
and sortPRs() function. Full test coverage for filter matching
(repo, author, age, checks, review, merge) and sort ordering."
```

---

### Task 2: Create PRColumnHeader view

**Files:**
- Create: `Sources/Views/PRDashboard/PRColumnHeader.swift`

- [ ] **Step 1: Create the column header view**

Create `Sources/Views/PRDashboard/PRColumnHeader.swift`:

```swift
import Models
import SwiftUI
import Theme

/// Clickable column header row for the PR list. Tapping a column toggles sort.
struct PRColumnHeader: View {
    @Binding var sortField: PRSortField
    @Binding var sortOrder: PRSortOrder
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            columnButton(.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnButton(.repo)
                .frame(width: 100, alignment: .leading)
            columnButton(.author)
                .frame(width: 70, alignment: .leading)
            columnButton(.age)
                .frame(width: 50, alignment: .leading)
            columnButton(.checks)
                .frame(width: 55, alignment: .leading)
            columnButton(.review)
                .frame(width: 55, alignment: .leading)
            columnButton(.mergeStatus)
                .frame(width: 65, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.chrome.surface)
    }

    private func columnButton(_ field: PRSortField) -> some View {
        Button {
            if sortField == field {
                sortOrder = sortOrder == .ascending ? .descending : .ascending
            } else {
                sortField = field
                sortOrder = field == .age ? .descending : .ascending
            }
        } label: {
            HStack(spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundColor(
                        sortField == field ? theme.chrome.accent : theme.chrome.textDim
                    )
                if sortField == field {
                    Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(theme.chrome.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/PRDashboard/PRColumnHeader.swift
git commit -m "feat: add PRColumnHeader view with sort toggle controls

Clickable column headers that toggle sort field and direction.
Active column highlighted with accent color and chevron indicator."
```

---

### Task 3: Create PRFilterBar view

**Files:**
- Create: `Sources/Views/PRDashboard/PRFilterBar.swift`

- [ ] **Step 1: Create the filter bar view**

Create `Sources/Views/PRDashboard/PRFilterBar.swift`:

```swift
import Models
import SwiftUI
import Theme

/// Persistent filter bar with dropdown menus for each filter dimension.
struct PRFilterBar: View {
    @Binding var filter: PRFilterState
    let pullRequests: [PullRequest]
    @Environment(\.theme) private var theme

    /// Distinct repo values from current PRs, sorted alphabetically.
    private var repoOptions: [String] {
        Array(Set(pullRequests.map(\.repo))).sorted()
    }

    /// Distinct author values from current PRs, sorted alphabetically.
    private var authorOptions: [String] {
        Array(Set(pullRequests.map(\.author))).sorted()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Filter:")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)

            filterMenu("Repo", selection: filter.repo ?? "All", isActive: filter.repo != nil) {
                Button("All") { filter.repo = nil }
                Divider()
                ForEach(repoOptions, id: \.self) { repo in
                    Button(repo) { filter.repo = repo }
                }
            }

            filterMenu("Author", selection: filter.author ?? "All", isActive: filter.author != nil) {
                Button("All") { filter.author = nil }
                Divider()
                ForEach(authorOptions, id: \.self) { author in
                    Button(author) { filter.author = author }
                }
            }

            filterMenu("Age", selection: filter.ageBucket.rawValue, isActive: filter.ageBucket != .any) {
                ForEach(PRAgeBucket.allCases, id: \.self) { bucket in
                    Button(bucket.rawValue) { filter.ageBucket = bucket }
                }
            }

            filterMenu(
                "Checks",
                selection: filter.checks?.label ?? "All",
                isActive: filter.checks != nil
            ) {
                Button("All") { filter.checks = nil }
                Divider()
                Button("Passing") { filter.checks = .passed }
                Button("Failing") { filter.checks = .failed }
                Button("Pending") { filter.checks = .pending }
            }

            filterMenu(
                "Review",
                selection: reviewLabel(filter.review),
                isActive: filter.review != nil
            ) {
                Button("All") { filter.review = nil }
                Divider()
                Button("Approved") { filter.review = .approved }
                Button("Changes Requested") { filter.review = .changesRequested }
                Button("Pending") { filter.review = .pending }
            }

            filterMenu(
                "Merge",
                selection: filter.mergeFilter?.rawValue ?? "All",
                isActive: filter.mergeFilter != nil
            ) {
                Button("All") { filter.mergeFilter = nil }
                Divider()
                ForEach(PRMergeFilter.allCases, id: \.self) { mergeFilter in
                    Button(mergeFilter.rawValue) { filter.mergeFilter = mergeFilter }
                }
            }

            if filter.isActive {
                Button("Clear") { filter.clear() }
                    .font(.caption)
                    .foregroundColor(theme.chrome.accent)
                    .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.chrome.surface)
    }

    private func filterMenu<Content: View>(
        _ label: String,
        selection: String,
        isActive: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Text("\(label): \(selection)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? theme.chrome.accent.opacity(0.15) : theme.chrome.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? theme.chrome.accent.opacity(0.4) : theme.chrome.border, lineWidth: 1)
                )
                .foregroundColor(isActive ? theme.chrome.accent : theme.chrome.textDim)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func reviewLabel(_ decision: ReviewDecision?) -> String {
        switch decision {
        case .approved: "Approved"
        case .changesRequested: "Changes Requested"
        case .pending: "Pending"
        case .none: "All"
        }
    }

}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/PRDashboard/PRFilterBar.swift
git commit -m "feat: add PRFilterBar view with dropdown menu filters

Persistent filter bar with Menu dropdowns for repo, author, age,
checks, review, and merge status. Dynamic options for repo/author.
Clear button appears when any filter is active."
```

---

### Task 4: Refactor PRRowView to grid-aligned columns

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:405-482` (PRRowView)

- [ ] **Step 1: Refactor PRRowView to use column-aligned HStack**

Replace the `PRRowView` struct body (lines 410-461 in `PRDashboardView.swift`) with a grid-aligned layout. The HStack widths must match `PRColumnHeader` exactly.

Replace the existing `PRRowView` body with:

```swift
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
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift
git commit -m "refactor: PRRowView to grid-aligned columns

Columns now match PRColumnHeader widths: title (flex), repo (100pt),
author (70pt), age (50pt), checks (55pt), review (55pt), merge (65pt).
Extracts short repo name from owner/repo format."
```

---

### Task 5: Integrate filter bar, column header, and sorting into PRDashboardView

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:1-34` (storage properties)
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:80-123` (filtering/grouping)
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:167-306` (body)

- [ ] **Step 1: Add @AppStorage properties for sort/filter state**

In `PRDashboardView`, after the existing `@AppStorage` lines (line 33), add:

```swift
@AppStorage("prSortField") private var sortFieldRaw: String = PRSortField.age.rawValue
@AppStorage("prSortOrder") private var sortOrderRaw: String = PRSortOrder.descending.rawValue
@AppStorage("prFilterRepo") private var filterRepo: String = ""
@AppStorage("prFilterAuthor") private var filterAuthor: String = ""
@AppStorage("prFilterAge") private var filterAgeRaw: String = PRAgeBucket.any.rawValue
@AppStorage("prFilterChecks") private var filterChecksRaw: String = ""
@AppStorage("prFilterReview") private var filterReviewRaw: String = ""
@AppStorage("prFilterMerge") private var filterMergeRaw: String = ""

```

Add computed property bindings after the `@Environment` line:

```swift
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
```

- [ ] **Step 2: Update filteredPRs to include PRFilterState**

Modify the `filteredPRs` computed property to apply the new filter after existing filters:

```swift
private var filteredPRs: [PullRequest] {
    var result = applyFilters(to: pullRequests, tab: selectedTab)
    let currentFilter = filterState
    if currentFilter.isActive {
        result = result.filter { currentFilter.matches($0) }
    }
    return result
}
```

Update `tabCount` similarly:

```swift
private func tabCount(_ tab: PRTab) -> Int {
    var prs = applyFilters(to: pullRequests, tab: tab)
    if hideDrafts { prs = prs.filter { !$0.isDraft } }
    let currentFilter = filterState
    if currentFilter.isActive {
        prs = prs.filter { currentFilter.matches($0) }
    }
    return prs.count
}
```

- [ ] **Step 3: Update groupedPRs to sort within groups**

Modify `groupedPRs()` to apply sorting:

```swift
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
```

- [ ] **Step 4: Insert PRFilterBar and PRColumnHeader into the body**

In the body, between the `Divider()` (after toolbar, line 216) and the PR list content, insert the filter bar and column header:

```swift
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
```

- [ ] **Step 5: Update the empty state for filtered-out PRs**

Replace the existing empty state block (the `if filteredPRs.isEmpty && !isLoading` check) to handle filter-specific messaging:

```swift
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
}
```

- [ ] **Step 6: Build and run tests**

Run: `swift build 2>&1 | tail -10`
Then: `swift test 2>&1 | tail -20`
Expected: Build succeeds, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift
git commit -m "feat: integrate filter bar, column headers, and sorting into PR dashboard

Adds @AppStorage-backed sort/filter state, PRFilterBar and PRColumnHeader
above the grouped list, sorts within groups, and updates empty states
for filter-specific messaging."
```

---

### Task 6: Run full test suite and verify

**Files:**
- No new files — verification only.

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All 273+ tests pass (existing tests still green, new PRSortFilter tests green).

- [ ] **Step 2: Build release to verify no warnings**

Run: `swift build -c release 2>&1 | tail -10`
Expected: Clean build with no errors.

- [ ] **Step 3: Run the app and verify visually**

Run: `swift run Runway`
Expected: PR dashboard shows filter bar, column headers, and grid-aligned rows. Sorting and filtering work as expected.

- [ ] **Step 4: Final commit if any fixups needed**

If any adjustments were needed during verification, commit them:

```bash
git add -A
git commit -m "fix: address issues found during PR sort/filter verification"
```
