# PR Review Session Feature

Create sessions from a PR number — resolve the PR, create a worktree on its branch, launch a Claude session, and pre-fill a review prompt.

## Entry Points

### 1. Keyboard Shortcut (⌘⇧R)

Small popover dialog with a text field for PR number. Uses the currently selected project's `ghRepo` as the target repository. If no project is selected (or the selected project has no `ghRepo`), the dialog includes a project dropdown to pick one before resolving.

On Enter: resolves the PR via `PRManager.resolvePR()`, then opens `ReviewPRSheet` for confirmation.

### 2. PR Dashboard "Review" Button

Green "Review" button on each PR row in the dashboard. Also available in the right-click context menu as "Open Review Session".

Clicks open `ReviewPRSheet` directly — the PR is already resolved from the dashboard data.

## Components

### PRManager.resolvePR() — GitHubOperations target

New public method on the existing `PRManager` actor.

```swift
public func resolvePR(repo: String, number: Int, host: String? = nil) async throws -> PullRequest
```

Calls `gh pr view <N> --repo <repo> --json number,title,state,headRefName,baseRefName,author,url,isDraft,additions,deletions,changedFiles,createdAt,updatedAt,reviewDecision,statusCheckRollup`.

Reuses existing `parseSinglePR()` and `GHPRItem` decoding. No new JSON models.

New error type:

```swift
public enum PRResolveError: Error, LocalizedError {
    case notFound(number: Int, repo: String)
    case noProject
}
```

### WorktreeManager.checkoutWorktree() — GitOperations target

New public method on the existing `WorktreeManager` actor.

```swift
public func checkoutWorktree(repoPath: String, branch: String) async throws -> String
```

Steps:
1. Fetch the branch from origin: `git fetch origin <branch>`
2. Create worktree tracking the remote branch: `git worktree add --track -b <branch> <path> origin/<branch>`
3. Worktree path: `<repoPath>/.worktrees/<sanitized-branch>`

Fallback: if the local branch already exists (e.g., previously reviewed this PR), falls back to `git worktree add <path> <branch>` to reuse the existing local branch.

### ReviewPRSheet — Views target

New SwiftUI view presented as a `.sheet`. Content:

- **PR info banner**: state badge, number, title, author, branch name
- **Session name** (editable text field): defaults to `"Review: <PR title>"`
- **Project picker**: auto-detected from PR repo matching project `ghRepo`, shown with "Auto-detected" indicator. Changeable via dropdown if multiple projects match or auto-detection fails.
- **Initial prompt** (editable text field): defaults to `"Review this PR"`
- **Cancel / Create Review Session** buttons

The sheet receives a `PullRequest` and a list of projects. It returns the confirmed session name, project ID, and initial prompt via a callback.

### RunwayStore Changes — App target

**New state:**

```swift
var showReviewPRDialog: Bool = false      // ⌘⇧R quick entry popover
var showReviewPRSheet: Bool = false       // Confirmation sheet
var reviewPRCandidate: PullRequest? = nil // PR being confirmed
```

**New method — `handleReviewPR()`:**

```swift
func handleReviewPR(pr: PullRequest, sessionName: String, projectID: String?, initialPrompt: String) async
```

Flow:
1. Look up project by `projectID`
2. Call `worktreeManager.checkoutWorktree(repoPath: project.path, branch: pr.headBranch)`
3. Create `Session` with `tool: .claude`, `worktreeBranch: pr.headBranch`, `prNumber: pr.number`
4. Resolve permission mode from project override or default
5. Create tmux session (same pattern as `handleNewSessionRequest`)
6. Append session, save to DB, set as selected
7. Link PR immediately: `sessionPRs[session.id] = pr`
8. Pre-fill initial prompt via `tmuxManager.sendKeys()` without trailing newline (user hits Enter)

**New method — `reviewPR(_:)`** (SidebarActions conformance):

Sets `reviewPRCandidate = pr` and `showReviewPRSheet = true`.

### SidebarActions Protocol — Views target

Add one method:

```swift
func reviewPR(_ pr: PullRequest)
```

Used by the PR dashboard "Review" button and context menu.

### Session Model — Models target

Add one optional field:

```swift
public var prNumber: Int?
```

Used for persistent PR-session linking that survives restarts. The existing `linkSessionPRs()` polling continues to work for worktree-based detection; `prNumber` is an additional persistent link.

### Database Migration v9 — Persistence target

Add `prNumber` column (nullable integer) to the sessions table.

### RunwayApp — App target

- Register `⌘⇧R` keyboard shortcut that sets `store.showReviewPRDialog = true`
- Add `.sheet` modifier for `ReviewPRSheet` bound to `store.showReviewPRSheet`
- Add popover/small dialog for the quick PR number entry bound to `store.showReviewPRDialog`

## Behaviors

- **Project auto-detection**: Match PR's `repo` field against all projects' `ghRepo`. If exactly one match, auto-select it. If multiple matches, show picker. If no match, show picker with all projects (user creates association manually).
- **Session naming**: Default `"Review: <PR title>"`, editable. Truncate long PR titles to keep session name reasonable.
- **Initial prompt**: Pre-filled in the terminal (typed via `sendKeys` without newline). User sees the prompt text and decides when to send it. Default: `"Review this PR"`.
- **PR linking**: Immediately set `sessionPRs[sessionID] = pr` on creation. Also persist `prNumber` on the Session record so the link survives app restart (the existing `linkSessionPRs()` polling will re-establish the `sessionPRs` mapping from the worktree branch on next launch).
- **Worktree path**: `<project.path>/.worktrees/<sanitized-branch-name>`, consistent with existing worktree placement.
- **Error handling**: If PR resolution fails (not found, network error), show error in `statusMessage`. If worktree creation fails (branch conflict, disk error), show error and abort — don't create a session without a worktree.

## Files to Create/Modify

| Action | File | Target |
|--------|------|--------|
| NEW | `Sources/Views/Shared/ReviewPRSheet.swift` | Views |
| MOD | `Sources/GitHubOperations/PRManager.swift` | GitHubOperations |
| MOD | `Sources/GitOperations/WorktreeManager.swift` | GitOperations |
| MOD | `Sources/App/RunwayStore.swift` | App |
| MOD | `Sources/App/RunwayApp.swift` | App |
| MOD | `Sources/Models/Session.swift` | Models |
| MOD | `Sources/Views/Sidebar/ProjectTreeView.swift` | Views (SidebarActions protocol) |
| MOD | `Sources/Persistence/Database.swift` | Persistence (migration v9) |
| MOD | `Sources/Views/PRDashboard/PRDashboardView.swift` | Views (add Review button to `PRRowView`) |
| MOD | `Sources/Views/ProjectPage/ProjectPRsTab.swift` | Views (add Review action to `ProjectPRRowView`) |

`PRResolveError` goes in `Sources/GitHubOperations/PRManager.swift` alongside the existing `GHError` enum.
