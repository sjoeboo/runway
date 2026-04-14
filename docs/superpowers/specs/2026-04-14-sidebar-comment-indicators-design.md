# Sidebar Comment Indicators

Surface new PR comments (since last commit, from others) as an accent-colored badge in the session sidebar row.

## Problem

When reviewers leave comments on a PR, there's no way to see "action needed" without opening the PR detail drawer. Users want a quick visual signal in the sidebar that feedback exists to address.

## Design Decisions

- **"New" = comments since last commit on the PR branch, excluding the PR author's own comments.** This is the natural "do I have feedback to address?" heuristic — after you push, any new comments from others are likely review feedback.
- **Piggyback on existing `enrichChecks()` polling** rather than adding a new API call. The enrichment cycle already runs for each linked PR and uses `gh pr view --json`. Adding `comments` and `commits` to that query costs almost nothing.
- **Accent-colored badge** to visually distinguish "action needed" from informational badges (checks use green/red, review uses green/orange). The comment badge uses `theme.chrome.accent`.

## Architecture

### Data Flow

```
gh pr view --json ...,comments,commits
    |
    v
PRManager.enrichChecks()
    - Parse lastCommitDate from commits(last)
    - Filter comments: createdAt > lastCommitDate AND author != prAuthor
    - Return count in PREnrichResult
    |
    v
PRCoordinator.applyEnrichment()
    - Sets pr.commentsSinceLastCommit
    - Sets pr.lastCommitDate
    |
    v
SessionRowView
    - CommentCountBadge(count: pr.commentsSinceLastCommit)
    - Shows "bubble.left.fill N" in accent color when count > 0
```

### Layer Changes

| Layer | File | Change |
|-------|------|--------|
| Model | `PullRequest.swift` | Add `commentsSinceLastCommit: Int` (default 0) and `lastCommitDate: Date?` to `PullRequest` |
| Model | `PullRequest.swift` | Add same fields to `PREnrichResult` |
| GitHub Ops | `PRManager.swift` | Add `createdAt` to `GHComment`, pass through in `fetchDetail()` mapping |
| GitHub Ops | `PRManager.swift` | Expand `enrichChecks()` `--json` to include `comments,commits` |
| GitHub Ops | `PRManager.swift` | Add `GHCommit` struct for decoding commit dates |
| GitHub Ops | `PRManager.swift` | Compute filtered comment count in `enrichChecks()` |
| Coordinator | `PRCoordinator.swift` | Apply `commentsSinceLastCommit` and `lastCommitDate` in `applyEnrichment()` |
| View | `PRBadges.swift` | New `CommentCountBadge` view |
| View | `ProjectTreeView.swift` | Insert `CommentCountBadge` in `SessionRowView` after `ReviewDecisionBadge` |

### Model Changes

**PullRequest struct** — two new fields:
```swift
public var commentsSinceLastCommit: Int = 0
public var lastCommitDate: Date?
```

**PREnrichResult** — two new fields:
```swift
public var commentsSinceLastCommit: Int = 0
public var lastCommitDate: Date?
```

### GHComment.createdAt Fix (Prerequisite)

The existing `GHComment` struct does not decode `createdAt` from the `gh` JSON response. The `PRComment` model has a `createdAt: Date` field but it defaults to `Date()` — meaning all comments currently get the fetch timestamp, not their real creation time. This doesn't affect the detail drawer (comments are displayed in return order), but our feature requires accurate timestamps.

**Fix:** Add `createdAt` to `GHComment`:
```swift
private struct GHComment: Decodable {
    let author: GHAuthor?
    let body: String?
    let id: String?
    let createdAt: Date?  // new — ISO 8601 from gh CLI
}
```

And pass it through in the `mappedComments` mapping in `fetchDetail()`:
```swift
PRComment(id: comment.id ?? "0", author: comment.author?.login ?? "",
          body: comment.body ?? "", createdAt: comment.createdAt ?? Date())
```

This is a small bugfix that benefits both the existing detail view and the new sidebar feature.

### enrichChecks() Query Expansion

Current `--json` fields:
```
statusCheckRollup,reviewDecision,headRefName,baseRefName,
additions,deletions,changedFiles,mergeable,mergeStateStatus,autoMergeRequest
```

New fields added:
```
...,comments,commits
```

**New decoding struct:**
```swift
struct GHCommit: Decodable {
    let committedDate: String?
}
```

**Comment count computation** (inside `enrichChecks()`):
```swift
let lastCommitDate = commits?.last.flatMap { ISO8601DateFormatter().date(from: $0.committedDate) }
let commentsSinceLastCommit = comments?
    .filter { comment in
        guard let date = comment.createdAt, let commitDate = lastCommitDate else { return false }
        return date > commitDate && comment.author?.login != prAuthor
    }
    .count ?? 0
```

### CommentCountBadge View

```swift
struct CommentCountBadge: View {
    let count: Int
    @Environment(\.theme) private var theme

    var body: some View {
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

**Placement** in `SessionRowView`, after `ReviewDecisionBadge`:
```swift
CheckSummaryBadge(checks: pr.checks)
ReviewDecisionBadge(decision: pr.reviewDecision, style: .iconOnly)
CommentCountBadge(count: pr.commentsSinceLastCommit)  // new
```

## Edge Cases

| Case | Behavior |
|------|----------|
| PR with no commits | `lastCommitDate` nil, count stays 0, badge hidden |
| PR author's own comments | Excluded by `author != prAuthor` filter |
| Review + inline comments | Both included in `gh` `comments` field, both count |
| Enrichment hasn't run yet | Defaults to 0, badge hidden until first enrichment |
| Session with no linked PR | Entire PR badge HStack not rendered, no change needed |

## Testing

- **ModelsTests**: Verify `PullRequest` new field defaults
- **GitHubOperationsTests**: Test comment filtering logic with mixed authors and timestamps
- **ViewsTests**: Test `CommentCountBadge` renders when count > 0, hidden when 0

No new test targets required.
