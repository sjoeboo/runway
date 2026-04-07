# Issue Detail View Design

**Date**: 2026-04-07
**Scope**: Extend GitHub Issues support to view/edit issues and comments, matching PR detail parity
**Approach**: Mirror PR architecture (Approach A) — `IssueDetail` lazy-loaded struct, `IssueDetailDrawer` view, extended `IssueManager` and `RunwayStore`

## Overview

Currently, Issues in Runway are list-only: you can see issue titles, states, and labels in `ProjectIssuesTab`, and create new issues via `NewIssueSheet`. Clicking an issue opens it in the browser. PRs, by contrast, have a full detail drawer with tabs (Overview, Conversation, Diff) and action buttons (approve, comment, merge, etc.).

This design extends Issues to full parity: a detail drawer with body display, full GitHub timeline, comments, and all mutation actions (edit, close/reopen, label/assignee management).

## Architecture Decision

**Mirror PR pattern** — follow the exact same architecture as PRs:
- Separate `IssueDetail` struct lazy-loaded on selection (mirrors `PRDetail`)
- `IssueDetailDrawer` view with tabs (mirrors `PRDetailDrawer`)
- New methods on `IssueManager` + `RunwayStore`
- Project-scoped only (inside `ProjectIssuesTab`), no top-level dashboard

This keeps the codebase consistent. Anyone who understands the PR detail flow immediately understands the Issue detail flow.

## Models (`Sources/Models/GitHubIssue.swift`)

### Changes to `GitHubIssue`

Add a `repo` field for explicit repo tracking (currently embedded in `id` but not stored separately):

```swift
public struct GitHubIssue: Identifiable, Codable, Sendable {
    // ... existing fields ...
    public var repo: String    // "owner/repo" — NEW, mirrors PullRequest.repo
}
```

Backwards-compatible with existing `issue_cache` JSON blobs: if `repo` is missing during decode, derive from `id` (`"owner/repo#123"` → `"owner/repo"`).

### New: `IssueDetail`

Lazy-loaded when an issue is selected, mirrors `PRDetail`:

```swift
public struct IssueDetail: Codable, Sendable {
    public var body: String
    public var comments: [IssueComment]
    public var timelineEvents: [IssueTimelineEvent]
    public var labels: [IssueDetailLabel]
    public var assignees: [String]
    public var milestone: String?
    public var stateReason: String?    // "completed", "not_planned", "reopened"
}
```

### New: `IssueComment`

```swift
public struct IssueComment: Identifiable, Codable, Sendable {
    public let id: String
    public var author: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
}
```

### New: `IssueTimelineEvent`

Represents all GitHub timeline events:

```swift
public struct IssueTimelineEvent: Identifiable, Codable, Sendable {
    public let id: String
    public var event: String        // "labeled", "unlabeled", "assigned", "closed",
                                    // "reopened", "cross-referenced", "renamed",
                                    // "milestoned", etc.
    public var actor: String
    public var createdAt: Date
    public var label: IssueDetailLabel?
    public var assignee: String?
    public var source: IssueReference?
    public var rename: IssueRename?
}

public struct IssueDetailLabel: Codable, Sendable {
    public var name: String
    public var color: String
}

public struct IssueReference: Codable, Sendable {
    public var type: String     // "issue" or "pullRequest"
    public var number: Int
    public var title: String
    public var url: String
}

public struct IssueRename: Codable, Sendable {
    public var from: String
    public var to: String
}
```

### New: `CloseReason`

```swift
public enum CloseReason: String, Codable, Sendable, CaseIterable {
    case completed
    case notPlanned = "not planned"

    public var displayName: String {
        switch self {
        case .completed: "Completed"
        case .notPlanned: "Not planned"
        }
    }

    public var cliFlag: String {
        switch self {
        case .completed: "--reason completed"
        case .notPlanned: "--reason \"not planned\""
        }
    }
}
```

## Operations Layer (`Sources/GitHubOperations/IssueManager.swift`)

### Detail Fetching

New method: `fetchDetail(repo:number:host:) -> IssueDetail`

Two `gh` CLI calls (same pattern as `PRManager.fetchDetail`):

1. **`gh issue view {number} --repo {repo} --json body,comments,labels,assignees,milestone,stateReason`** — body, comments, metadata
2. **`gh api repos/{repo}/issues/{number}/timeline --paginate`** — full timeline events (REST API, since `gh issue view` doesn't expose timeline)

Comments come from both sources. Use comments from call 1 (richer data), non-comment events from call 2.

**Timeline API parsing notes:**
- Each timeline event has an `event` field (e.g. `"labeled"`, `"closed"`, `"cross-referenced"`)
- Cross-reference events nest the source under `source.issue` (which may be a PR despite the key name) — extract `number`, `title`, `html_url`, and detect type from `pull_request` key presence
- The `actor` field is an object with a `login` key
- Generate stable IDs from `"{event}-{actor}-{created_at}"` since the timeline API doesn't provide IDs
- Filter out `"commented"` events from the timeline (use the richer comments from `gh issue view` instead)

### Mutations

| Method | `gh` CLI Command |
|--------|-----------------|
| `editIssue(repo, number, host, title?, body?)` | `gh issue edit {number} --repo {repo} [--title ...] [--body ...]` |
| `addComment(repo, number, host, body)` | `gh issue comment {number} --repo {repo} --body ...` |
| `closeIssue(repo, number, host, reason)` | `gh issue close {number} --repo {repo} [--reason ...]` |
| `reopenIssue(repo, number, host)` | `gh issue reopen {number} --repo {repo}` |
| `updateLabels(repo, number, host, add, remove)` | `gh issue edit {number} --repo {repo} [--add-label ...] [--remove-label ...]` |
| `updateAssignees(repo, number, host, add, remove)` | `gh issue edit {number} --repo {repo} [--add-assignee ...] [--remove-assignee ...]` |

### Detail Cache

In-memory cache on `IssueManager` actor with 5-minute TTL, same pattern as `PRManager.detailCache`:

```swift
private var detailCache: [String: (detail: IssueDetail, fetchedAt: Date)] = [:]
private let detailTTL: TimeInterval = 300
```

Cache eviction after any mutation on that issue.

## Store Layer (`Sources/App/RunwayStore.swift`)

### New State

```swift
var selectedIssueID: String?
var issueDetail: IssueDetail?
var isLoadingIssueDetail: Bool = false
```

### New Methods

```swift
func selectIssue(_ issue: GitHubIssue?) async      // loads detail with cache check
func editIssue(_ issue: GitHubIssue, title: String?, body: String?) async
func commentOnIssue(_ issue: GitHubIssue, body: String) async
func closeIssue(_ issue: GitHubIssue, reason: CloseReason) async
func reopenIssue(_ issue: GitHubIssue) async
func updateIssueLabels(_ issue: GitHubIssue, add: [String], remove: [String]) async
func updateIssueAssignees(_ issue: GitHubIssue, add: [String], remove: [String]) async
```

Each mutation follows the pattern: call `IssueManager` method → set `statusMessage` → refetch detail → refetch issue list (to update list-level state).

## Views

### New: `IssueDetailDrawer` (`Sources/Views/ProjectPage/IssueDetailDrawer.swift`)

Mirrors `PRDetailDrawer` structure:

**Header:**
- State badge (Open green / Closed gray)
- Issue number, title, author, age
- Label pills (colored, using `IssueDetailLabel` data from detail)
- Assignee list

**Action bar:**
- Close (with reason menu: Completed / Not Planned) or Reopen — depending on state
- Edit — opens `EditIssueSheet`
- Labels — opens `ManageLabelsSheet`
- Assignees — opens `ManageAssigneesSheet`
- Open in Browser

**Tabs:**
- **Overview** — renders issue body as markdown (same `renderMarkdown` helper as `PRDetailDrawer`)
- **Timeline** — chronologically interleaved stream:
  - **Comments**: blue left-border cards with author, markdown body, timestamp
  - **Events**: compact inline rows with icon, actor, action description, timestamp
    - Label added/removed (shows colored pill)
    - Assigned/unassigned
    - Closed/reopened (with reason)
    - Cross-referenced (clickable link to PR/issue)
    - Renamed, milestoned, etc.
  - **Comment input** at bottom: TextEditor + Comment button

### New: `EditIssueSheet` (`Sources/Views/ProjectPage/EditIssueSheet.swift`)

Modal sheet opened from "Edit" button:
- Title text field (pre-filled)
- Body text editor (monospaced, pre-filled, same style as `NewIssueSheet`)
- Save / Cancel buttons

### New: `ManageLabelsSheet` (`Sources/Views/ProjectPage/ManageLabelsSheet.swift`)

Popover/sheet for toggling labels:
- Checkbox list of available labels (reuses `IssueLabel` data already fetched by `fetchLabels`)
- Current labels pre-checked
- Save applies add/remove diff

### New: `ManageAssigneesSheet` (`Sources/Views/ProjectPage/ManageAssigneesSheet.swift`)

Sheet for managing assignees:
- Text field to add by username
- List of current assignees with remove button

### Modified: `ProjectIssuesTab`

Changes from flat list to split-pane layout (like `ProjectPRsTab`):
- **Left pane**: issue list (existing, with selection highlight — blue left border)
- **Right pane**: `IssueDetailDrawer` (when an issue is selected)
- `onOpenIssue` callback replaced with `onSelectIssue` (no longer opens browser)
- New callbacks for all detail actions

### Modified: `ProjectPageView`

New optional callbacks piped through for issue detail + actions, mirroring the existing PR callback pattern:

```swift
var selectedIssueID: String?
var issueDetail: IssueDetail?
var onSelectIssue: ((GitHubIssue?) -> Void)?
var onEditIssue: ((GitHubIssue, String?, String?) -> Void)?
var onCommentOnIssue: ((GitHubIssue, String) -> Void)?
var onCloseIssue: ((GitHubIssue, CloseReason) -> Void)?
var onReopenIssue: ((GitHubIssue) -> Void)?
var onUpdateIssueLabels: ((GitHubIssue, [String], [String]) -> Void)?
var onUpdateIssueAssignees: ((GitHubIssue, [String], [String]) -> Void)?
```

## Persistence

**No new database migration needed.** The existing `issue_cache` table stores JSON blobs and the `repo` field addition is backwards-compatible. Issue detail is cached in-memory only (5-min TTL on `IssueManager`), same as PR detail.

## Files Changed Summary

| File | Change |
|------|--------|
| `Sources/Models/GitHubIssue.swift` | Add `repo` field, add `IssueDetail`, `IssueComment`, `IssueTimelineEvent`, `CloseReason`, supporting types |
| `Sources/GitHubOperations/IssueManager.swift` | Add `fetchDetail`, `editIssue`, `addComment`, `closeIssue`, `reopenIssue`, `updateLabels`, `updateAssignees`, detail cache, GH JSON parsing |
| `Sources/App/RunwayStore.swift` | Add `selectedIssueID`, `issueDetail`, `isLoadingIssueDetail` state + 7 action methods |
| `Sources/Views/ProjectPage/IssueDetailDrawer.swift` | **New** — detail drawer with header, actions, Overview + Timeline tabs |
| `Sources/Views/ProjectPage/EditIssueSheet.swift` | **New** — edit title/body modal |
| `Sources/Views/ProjectPage/ManageLabelsSheet.swift` | **New** — label toggle sheet |
| `Sources/Views/ProjectPage/ManageAssigneesSheet.swift` | **New** — assignee management sheet |
| `Sources/Views/ProjectPage/ProjectIssuesTab.swift` | Convert to split-pane layout, replace `onOpenIssue` with `onSelectIssue`, add detail callbacks |
| `Sources/Views/ProjectPage/ProjectPageView.swift` | Add issue detail callbacks, wire through to `ProjectIssuesTab` |
| `Sources/App/RunwayApp.swift` (or content view) | Wire `RunwayStore` issue methods to `ProjectPageView` callbacks |
