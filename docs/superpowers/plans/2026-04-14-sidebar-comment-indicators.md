# Sidebar Comment Indicators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an accent-colored badge in the sidebar session row indicating the count of PR comments from others since the last commit, so users can see at a glance when feedback needs attention.

**Architecture:** Add `commentsSinceLastCommit` and `lastCommitDate` fields to `PullRequest` and `PREnrichResult`. Expand the existing `enrichChecks()` gh query to also fetch `comments` and `commits`, compute the filtered count in `PRManager`, and display it via a new `CommentCountBadge` view in the sidebar row. Also fix the existing `GHComment` struct to decode `createdAt` (currently missing, affecting detail view comment timestamps).

**Tech Stack:** Swift, SwiftUI, gh CLI (JSON output), Swift Testing framework

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Models/PullRequest.swift` | Modify | Add `commentsSinceLastCommit` and `lastCommitDate` fields to `PullRequest` |
| `Sources/GitHubOperations/PRManager.swift` | Modify | Add `createdAt` to `GHComment`, add `GHCommit` struct, expand `GHEnrichResponse` and `enrichChecks()`, update `GHPRDetailResponse.toPRDetail()` comment mapping |
| `Sources/App/PRCoordinator.swift` | Modify | Apply new fields in `applyEnrichment()` |
| `Sources/Views/Shared/PRBadges.swift` | Modify | Add `CommentCountBadge` view |
| `Sources/Views/Sidebar/ProjectTreeView.swift` | Modify | Insert `CommentCountBadge` in `SessionRowView` |
| `Tests/ModelsTests/PullRequestTests.swift` | Modify | Test new field defaults |
| `Tests/GitHubOperationsTests/PRManagerTests.swift` | Modify | Test `PREnrichResult` new field defaults |

---

### Task 1: Add model fields to PullRequest

**Files:**
- Modify: `Sources/Models/PullRequest.swift:4-73`
- Test: `Tests/ModelsTests/PullRequestTests.swift`

- [ ] **Step 1: Write failing test for new PullRequest defaults**

Add to `Tests/ModelsTests/PullRequestTests.swift`:

```swift
@Test func pullRequestCommentFieldDefaults() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f",
        baseBranch: "main", author: "me", repo: "r")
    #expect(pr.commentsSinceLastCommit == 0)
    #expect(pr.lastCommitDate == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PullRequestTests/pullRequestCommentFieldDefaults`
Expected: FAIL — `PullRequest` has no member `commentsSinceLastCommit`

- [ ] **Step 3: Add fields to PullRequest struct**

In `Sources/Models/PullRequest.swift`, add two new properties after `autoMergeEnabled` (line 26):

```swift
public var commentsSinceLastCommit: Int
public var lastCommitDate: Date?
```

Add matching parameters to the `init` (after `autoMergeEnabled: Bool = false` on line 49), with defaults:

```swift
commentsSinceLastCommit: Int = 0,
lastCommitDate: Date? = nil
```

And the assignments in the init body (after `self.autoMergeEnabled = autoMergeEnabled` on line 72):

```swift
self.commentsSinceLastCommit = commentsSinceLastCommit
self.lastCommitDate = lastCommitDate
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PullRequestTests/pullRequestCommentFieldDefaults`
Expected: PASS

- [ ] **Step 5: Run full model tests to check for regressions**

Run: `swift test --filter ModelsTests`
Expected: All tests pass — existing callers use defaults

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/PullRequest.swift Tests/ModelsTests/PullRequestTests.swift
git commit -m "feat: add commentsSinceLastCommit and lastCommitDate to PullRequest model"
```

---

### Task 2: Fix GHComment to decode createdAt and add GHCommit struct

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift:728-748` (GHComment)
- Modify: `Sources/GitHubOperations/PRManager.swift:659-661` (toPRDetail mapping)

- [ ] **Step 1: Add `createdAt` to GHComment**

In `Sources/GitHubOperations/PRManager.swift`, update the `GHComment` struct (line 728):

```swift
private struct GHComment: Decodable {
    let author: GHAuthor?
    let body: String?
    let createdAt: Date?

    let id: String?

    enum CodingKeys: String, CodingKey {
        case id, author, body, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decodeIfPresent(GHAuthor.self, forKey: .author)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = "\(intID)"
        } else {
            id = try container.decodeIfPresent(String.self, forKey: .id)
        }
    }
}
```

- [ ] **Step 2: Update toPRDetail() comment mapping to pass createdAt**

In `Sources/GitHubOperations/PRManager.swift`, update the `mappedComments` mapping (line 659-661):

```swift
let mappedComments: [PRComment] = (comments ?? []).map { comment in
    PRComment(
        id: comment.id ?? "0",
        author: comment.author?.login ?? "",
        body: comment.body ?? "",
        createdAt: comment.createdAt ?? Date()
    )
}
```

- [ ] **Step 3: Add GHCommit struct**

Add this struct after the `GHComment` struct (after line 748):

```swift
private struct GHCommit: Decodable {
    let committedDate: Date?
}
```

- [ ] **Step 4: Run existing tests to verify no regressions**

Run: `swift test --filter GitHubOperationsTests`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift
git commit -m "fix: decode createdAt in GHComment, add GHCommit struct"
```

---

### Task 3: Expand enrichChecks() to compute comment count

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift:1-35` (PREnrichResult)
- Modify: `Sources/GitHubOperations/PRManager.swift:122-135` (enrichChecks method)
- Modify: `Sources/GitHubOperations/PRManager.swift:751-781` (GHEnrichResponse)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write failing test for PREnrichResult new defaults**

Add to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
@Test func prEnrichResultCommentDefaults() {
    let result = PREnrichResult()
    #expect(result.commentsSinceLastCommit == 0)
    #expect(result.lastCommitDate == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GitHubOperationsTests/prEnrichResultCommentDefaults`
Expected: FAIL — `PREnrichResult` has no member `commentsSinceLastCommit`

- [ ] **Step 3: Add fields to PREnrichResult**

In `Sources/GitHubOperations/PRManager.swift`, add to the `PREnrichResult` struct (after `autoMergeEnabled` on line 15):

```swift
public var commentsSinceLastCommit: Int
public var lastCommitDate: Date?
```

Update the init (after `autoMergeEnabled: Bool = false` on line 22) to add:

```swift
commentsSinceLastCommit: Int = 0,
lastCommitDate: Date? = nil
```

And the init body (after `self.autoMergeEnabled = autoMergeEnabled` on line 33):

```swift
self.commentsSinceLastCommit = commentsSinceLastCommit
self.lastCommitDate = lastCommitDate
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GitHubOperationsTests/prEnrichResultCommentDefaults`
Expected: PASS

- [ ] **Step 5: Expand GHEnrichResponse to decode comments and commits**

In `Sources/GitHubOperations/PRManager.swift`, update the `GHEnrichResponse` struct (line 751) to add two new fields:

```swift
let comments: [GHComment]?
let commits: [GHCommit]?
```

Update `toEnrichResult()` to accept an `excludeAuthor` parameter and compute the filtered count. Change the signature and add the computation before the `return`:

```swift
func toEnrichResult(excludeAuthor: String? = nil) -> PREnrichResult {
    // ... existing checks/review parsing unchanged ...

    let lastCommitDate = commits?.last?.committedDate
    let commentsSinceLastCommit = Self.countCommentsSinceCommit(
        comments: comments, lastCommitDate: lastCommitDate, excludeAuthor: excludeAuthor
    )

    return PREnrichResult(
        checks: checks, reviewDecision: review,
        headBranch: headRefName ?? "", baseBranch: baseRefName ?? "",
        additions: additions ?? 0, deletions: deletions ?? 0, changedFiles: changedFiles ?? 0,
        mergeable: MergeableState(rawValue: mergeable ?? ""),
        mergeStateStatus: MergeStateStatus(rawValue: mergeStateStatus ?? ""),
        autoMergeEnabled: autoMergeRequest != nil,
        commentsSinceLastCommit: commentsSinceLastCommit,
        lastCommitDate: lastCommitDate
    )
}
```

Add a static helper method on `GHEnrichResponse`:

```swift
private static func countCommentsSinceCommit(
    comments: [GHComment]?,
    lastCommitDate: Date?,
    excludeAuthor: String?
) -> Int {
    guard let comments, let commitDate = lastCommitDate else { return 0 }
    return comments.filter { comment in
        guard let createdAt = comment.createdAt else { return false }
        if createdAt <= commitDate { return false }
        if let exclude = excludeAuthor, comment.author?.login == exclude { return false }
        return true
    }.count
}
```

- [ ] **Step 6: Update enrichChecks() method to pass author and expand JSON fields**

Update the `enrichChecks()` method (line 122-135) to:

1. Add `author` parameter:
```swift
public func enrichChecks(repo: String, number: Int, author: String? = nil, host: String? = nil) async throws -> PREnrichResult
```

2. Expand the `--json` field list to include `comments,commits`:
```swift
"statusCheckRollup,reviewDecision,headRefName,baseRefName,additions,deletions,changedFiles,mergeable,mergeStateStatus,autoMergeRequest,comments,commits",
```

3. Pass the author through to `toEnrichResult`:
```swift
return resp.toEnrichResult(excludeAuthor: author)
```

- [ ] **Step 7: Run all tests**

Run: `swift test --filter GitHubOperationsTests`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat: expand enrichChecks to compute comment count since last commit"
```

---

### Task 4: Apply enrichment in PRCoordinator

**Files:**
- Modify: `Sources/App/PRCoordinator.swift:195-209` (applyEnrichment)
- Modify: `Sources/App/PRCoordinator.swift:148-155` (enrichPRs task group, pass author)

- [ ] **Step 1: Update applyEnrichment to include new fields**

In `Sources/App/PRCoordinator.swift`, add two lines to `applyEnrichment()` (after `pr.autoMergeEnabled = result.autoMergeEnabled` on line 207):

```swift
pr.commentsSinceLastCommit = result.commentsSinceLastCommit
pr.lastCommitDate = result.lastCommitDate
```

- [ ] **Step 2: Pass PR author to enrichChecks call**

In `Sources/App/PRCoordinator.swift`, update the `enrichChecks` call inside the task group in `enrichPRs()` (around line 151) to pass the author:

```swift
let result = try? await prManager.enrichChecks(
    repo: pr.repo, number: pr.number, author: pr.author, host: host
)
```

Also update the `reEnrichPR` method's `enrichChecks` call (around line 184):

```swift
let result = try? await prManager.enrichChecks(
    repo: pr.repo, number: pr.number, author: pr.author, host: host
)
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/App/PRCoordinator.swift
git commit -m "feat: apply comment count enrichment in PRCoordinator"
```

---

### Task 5: Add CommentCountBadge view and wire into sidebar

**Files:**
- Modify: `Sources/Views/Shared/PRBadges.swift` (add new view after line 160)
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift:463` (insert badge)

- [ ] **Step 1: Add CommentCountBadge to PRBadges.swift**

In `Sources/Views/Shared/PRBadges.swift`, add after the `ReviewDecisionBadge` closing brace (after line 160):

```swift
// MARK: - CommentCountBadge

/// Accent-colored badge showing the count of PR comments from others since the last commit.
///
/// Hidden when count is zero. Used in sidebar session rows as an "action needed" signal.
public struct CommentCountBadge: View {
    let count: Int
    @Environment(\.theme) private var theme

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "bubble.left.fill")
                Text("\(count)")
            }
            .font(.caption2)
            .foregroundColor(theme.chrome.accent)
        }
    }
}
```

- [ ] **Step 2: Insert CommentCountBadge in SessionRowView**

In `Sources/Views/Sidebar/ProjectTreeView.swift`, add after the `ReviewDecisionBadge` line (line 463):

```swift
CommentCountBadge(count: pr.commentsSinceLastCommit)
```

So the badge section reads:
```swift
CheckSummaryBadge(checks: pr.checks)
ReviewDecisionBadge(decision: pr.reviewDecision, style: .iconOnly)
CommentCountBadge(count: pr.commentsSinceLastCommit)
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/Shared/PRBadges.swift Sources/Views/Sidebar/ProjectTreeView.swift
git commit -m "feat: add CommentCountBadge to sidebar session rows"
```

---

### Task 6: Final validation

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All 329+ tests pass

- [ ] **Step 2: Run lint and format check**

Run: `make check`
Expected: Build + test + lint + format all pass

- [ ] **Step 3: Fix any lint/format issues**

Run: `make fix` if needed, then re-run `make check`

- [ ] **Step 4: Final commit if any formatting changes**

```bash
git add -A
git commit -m "style: format and lint fixes"
```
