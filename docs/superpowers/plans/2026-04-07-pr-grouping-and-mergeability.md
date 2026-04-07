# PR Grouping & Mergeability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine PR dashboard grouping from 3 to 5 categories, add inline merge status badges, and separate draft PRs into their own section.

**Architecture:** Update `PRGroup` enum in the dashboard view to 5 cases with priority-based classification. Add a new `MergeStatusBadge` SwiftUI view following the existing `ReviewDecisionBadge` capsule pattern. Update both `PRDashboardView` and `ProjectPRsTab` to show the new badge.

**Tech Stack:** SwiftUI, Swift Testing framework, SPM targets (Views, Models)

---

### File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Views/PRDashboard/PRDashboardView.swift` | Modify | Update `PRGroup` enum (5 cases), `group(for:)` logic, `@AppStorage` keys, group metadata, draft separation |
| `Sources/Views/Shared/PRBadges.swift` | Modify | Add `MergeStatusBadge` view |
| `Sources/Views/ProjectPage/ProjectPRsTab.swift` | Modify | Add `MergeStatusBadge` to `ProjectPRRowView` |
| `Tests/ModelsTests/PullRequestTests.swift` | Modify | Add grouping logic tests (if grouping moves to model — see Task 1 note) |
| `Tests/ViewsTests/PRGroupingTests.swift` | Create | Tests for the grouping function |

---

### Task 1: Add `PRGroup` enum and grouping function

The grouping logic currently lives inside `PRDashboardView` as a private enum and function. We'll update it in place — the enum stays view-private since it's only used for display grouping.

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:107-165`
- Create: `Tests/ViewsTests/PRGroupingTests.swift`

- [ ] **Step 1: Create the test file with grouping tests**

Create `Tests/ViewsTests/PRGroupingTests.swift`. Since `PRGroup` and `group(for:)` are private to `PRDashboardView`, we need to either make the grouping function testable or test it indirectly. The cleanest approach: extract the grouping logic into a package-internal free function in the same file, so tests in the Views test target can call it.

```swift
import Foundation
import Testing

@testable import Models
@testable import Views

// MARK: - PR Grouping Logic Tests

@Test func draftPRAlwaysGroupedAsDraft() {
    let pr = PullRequest(
        number: 1, title: "WIP", state: .draft, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r", isDraft: true,
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .approved
    )
    #expect(prGroup(for: pr) == .drafts)
}

@Test func failedChecksGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 2, title: "Broken", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 8, failed: 2, pending: 0),
        reviewDecision: .approved
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func changesRequestedGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 3, title: "Fix", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .changesRequested
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func conflictingPRGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 4, title: "Conflict", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .approved,
        mergeable: .conflicting
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func blockedPRGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 5, title: "Blocked", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .approved,
        mergeStateStatus: .blocked
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func pendingChecksGroupedAsInProgress() {
    let pr = PullRequest(
        number: 6, title: "Running", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 3, failed: 0, pending: 5),
        reviewDecision: .pending
    )
    #expect(prGroup(for: pr) == .inProgress)
}

@Test func unenrichedPRGroupedAsInProgress() {
    let pr = PullRequest(
        number: 7, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(),
        reviewDecision: .pending,
        enrichedAt: nil
    )
    #expect(prGroup(for: pr) == .inProgress)
}

@Test func allPassedPendingReviewGroupedAsWaitingForReview() {
    let pr = PullRequest(
        number: 8, title: "Ready for eyes", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .pending
    )
    #expect(prGroup(for: pr) == .waitingForReview)
}

@Test func noChecksAndPendingReviewGroupedAsWaitingForReview() {
    var pr = PullRequest(
        number: 9, title: "No CI", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(),
        reviewDecision: .pending
    )
    pr.enrichedAt = Date() // enriched but no checks configured
    #expect(prGroup(for: pr) == .waitingForReview)
}

@Test func reviewNoneGroupedAsWaitingForReview() {
    let pr = PullRequest(
        number: 10, title: "No reviewers", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .none
    )
    #expect(prGroup(for: pr) == .waitingForReview)
}

@Test func approvedAndPassingGroupedAsReady() {
    let pr = PullRequest(
        number: 11, title: "Ship it", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .approved
    )
    #expect(prGroup(for: pr) == .ready)
}

@Test func approvedAndBehindStillGroupedAsReady() {
    let pr = PullRequest(
        number: 12, title: "Behind but ok", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .approved,
        mergeStateStatus: .behind
    )
    #expect(prGroup(for: pr) == .ready)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PRGroupingTests 2>&1 | head -40`
Expected: Compilation error — `prGroup(for:)` and `.drafts`/`.waitingForReview` don't exist yet.

- [ ] **Step 3: Update PRGroup enum and extract grouping function**

In `Sources/Views/PRDashboard/PRDashboardView.swift`, replace the existing `PRGroup` enum (lines 107-111) and `group(for:)` function (lines 113-121) with:

```swift
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
```

Note: The function is declared at file scope (not inside the struct) with default internal access so `@testable import Views` can see it.

- [ ] **Step 4: Update groupedPRs(), isGroupExpanded, toggleGroupExpanded, groupColor, groupIcon**

In the same file, update the helper methods on `PRDashboardView`:

Replace `isGroupExpanded(_:)` (lines 135-140):
```swift
private func isGroupExpanded(_ group: PRGroup) -> Bool {
    switch group {
    case .needsAttention: return needsAttentionExpanded
    case .inProgress: return inProgressExpanded
    case .waitingForReview: return waitingForReviewExpanded
    case .ready: return readyExpanded
    case .drafts: return draftsExpanded
    }
}
```

Replace `toggleGroupExpanded(_:)` (lines 143-149):
```swift
private func toggleGroupExpanded(_ group: PRGroup) {
    switch group {
    case .needsAttention: needsAttentionExpanded.toggle()
    case .inProgress: inProgressExpanded.toggle()
    case .waitingForReview: waitingForReviewExpanded.toggle()
    case .ready: readyExpanded.toggle()
    case .drafts: draftsExpanded.toggle()
    }
}
```

Replace `groupColor(_:)` (lines 151-157):
```swift
private func groupColor(_ group: PRGroup) -> Color {
    switch group {
    case .needsAttention: return theme.chrome.red
    case .inProgress: return theme.chrome.yellow
    case .waitingForReview: return theme.chrome.accent
    case .ready: return theme.chrome.green
    case .drafts: return theme.chrome.textDim
    }
}
```

Replace `groupIcon(_:)` (lines 159-165):
```swift
private func groupIcon(_ group: PRGroup) -> String {
    switch group {
    case .needsAttention: return "exclamationmark.circle"
    case .inProgress: return "clock"
    case .waitingForReview: return "eye"
    case .ready: return "checkmark.circle"
    case .drafts: return "circle.dashed"
    }
}
```

- [ ] **Step 5: Add @AppStorage properties for new groups**

Add these two properties alongside the existing `@AppStorage` declarations (after line 29):

```swift
@AppStorage("prGroupWaitingForReviewExpanded") private var waitingForReviewExpanded: Bool = true
@AppStorage("prGroupDraftsExpanded") private var draftsExpanded: Bool = false
```

- [ ] **Step 6: Update groupedPRs() to use the new function and handle draft filtering**

Replace `groupedPRs()` (lines 123-133):

```swift
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
```

Also update `applyFilters(to:tab:)` — change the `hideDrafts` filter (line 90-92). Instead of filtering drafts out entirely, we now let them through to be grouped into the Drafts section. The `hideDrafts` toggle should suppress the entire Drafts group instead:

Replace:
```swift
if hideDrafts {
    result = result.filter { !$0.isDraft }
}
```

With: remove these lines entirely. The `hideDrafts` toggle will be handled in the body by skipping the `.drafts` group entry when `hideDrafts` is true.

Then in the `body` (around line 244, inside the `ForEach(groups)`), add a filter:

Replace:
```swift
ForEach(groups, id: \.group) { entry in
```

With:
```swift
ForEach(groups.filter { !($0.group == .drafts && hideDrafts) }, id: \.group) { entry in
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter PRGroupingTests 2>&1 | tail -20`
Expected: All 12 tests pass.

- [ ] **Step 8: Build the full project**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds with no errors.

- [ ] **Step 9: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift Tests/ViewsTests/PRGroupingTests.swift
git commit -m "feat: expand PR grouping to 5 categories with draft separation

Replaces the 3-group model (Needs Attention, In Progress, Ready) with
a 5-group pipeline: Needs Attention, In Progress, Waiting for Review,
Ready, and Drafts. Merge conflicts and blocked status now demote PRs
to Needs Attention. Drafts get their own collapsed section."
```

---

### Task 2: Add MergeStatusBadge

**Files:**
- Modify: `Sources/Views/Shared/PRBadges.swift:160` (append after `ReviewDecisionBadge`)

- [ ] **Step 1: Add MergeStatusBadge to PRBadges.swift**

Append after the `ReviewDecisionBadge` closing brace (after line 160), before `SessionStatusIndicator`:

```swift
// MARK: - MergeStatusBadge

/// Capsule badge showing PR merge status (Clean, Conflicts, Behind, Blocked, etc.).
///
/// Hidden when merge status is unknown or not yet enriched.
public struct MergeStatusBadge: View {
    let mergeable: MergeableState?
    let mergeStateStatus: MergeStateStatus?
    @Environment(\.theme) private var theme

    public init(mergeable: MergeableState?, mergeStateStatus: MergeStateStatus?) {
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
    }

    public var body: some View {
        if let badge = badgeInfo {
            Text(badge.text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(badge.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badge.color.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var badgeInfo: (text: String, color: Color)? {
        // Conflicts override everything
        if mergeable == .conflicting {
            return ("\u{26A0} Conflicts", theme.chrome.red)
        }

        switch mergeStateStatus {
        case .blocked:
            return ("\u{2298} Blocked", theme.chrome.orange)
        case .behind:
            return ("\u{2193} Behind", theme.chrome.yellow)
        case .dirty:
            return ("\u{26A0} Dirty", theme.chrome.orange)
        case .unstable:
            return ("~ Unstable", theme.chrome.yellow)
        case .clean, .hasHooks:
            return ("\u{2713} Clean", theme.chrome.green)
        case .unknown, .none:
            // Also check if mergeable is known even without mergeStateStatus
            if mergeable == .mergeable {
                return ("\u{2713} Mergeable", theme.chrome.green)
            }
            return nil
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/Shared/PRBadges.swift
git commit -m "feat: add MergeStatusBadge capsule component

Shows merge status inline as a colored capsule pill: Clean (green),
Conflicts (red), Behind (yellow), Blocked (orange), etc. Hidden
when merge status is unknown or not yet enriched."
```

---

### Task 3: Wire MergeStatusBadge into PR row views

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:379` (PRRowView metadata HStack)
- Modify: `Sources/Views/ProjectPage/ProjectPRsTab.swift:186` (ProjectPRRowView metadata HStack)

- [ ] **Step 1: Add MergeStatusBadge to PRRowView in PRDashboardView.swift**

In the `PRRowView` body, find the metadata `HStack` (around line 363-380). After the `ReviewDecisionBadge(decision: pr.reviewDecision)` line (line 379), add:

```swift
MergeStatusBadge(mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus)
```

- [ ] **Step 2: Add MergeStatusBadge to ProjectPRRowView in ProjectPRsTab.swift**

In `ProjectPRRowView`, find the metadata `HStack` (around line 175-187). After `ReviewDecisionBadge(decision: pr.reviewDecision)` (line 186), add:

```swift
MergeStatusBadge(mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus)
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 4: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift Sources/Views/ProjectPage/ProjectPRsTab.swift
git commit -m "feat: show merge status badge in PR list rows

Adds MergeStatusBadge inline after check and review badges in both
the PR dashboard and project PR tab row views."
```

---

### Task 4: Final validation

- [ ] **Step 1: Run full build and test suite**

Run: `swift build 2>&1 | tail -10 && swift test 2>&1 | tail -30`
Expected: Build succeeds, all tests pass.

- [ ] **Step 2: Review the diff**

Run: `git log --oneline master..HEAD` to confirm 3 clean commits covering the full spec.

Run: `git diff master..HEAD --stat` to verify only expected files changed.
