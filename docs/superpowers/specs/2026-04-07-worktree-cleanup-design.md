# Orphaned Worktree Cleanup on Startup

**Date:** 2026-04-07
**Status:** Approved

## Problem

When sessions are deleted with "Delete Session Only" (the default), the worktree directory remains on disk under `{project.path}/.worktrees/`. Over time these accumulate, consuming significant disk space with no UI indication. There is no orphan detection or automatic cleanup — unlike tmux sessions, which are reconciled on startup.

## Design

### New Method: `RunwayStore.cleanOrphanedWorktrees()`

An async method called from `loadState()` after the existing tmux orphan cleanup block (~line 200).

**Algorithm:**

1. Collect all session paths where `worktreeBranch != nil` into a `Set<String>` — these are "owned" worktrees
2. For each project:
   - Run `git worktree prune` to clear stale references (directories manually deleted)
   - Call `worktreeManager.listWorktrees(repoPath:)` to get live worktrees from git
   - Filter to only worktrees under `{project.path}/.worktrees/` (skip the main repo entry)
   - Any worktree whose path is NOT in the owned set is orphaned
3. For each orphan:
   - Check if the branch is merged into the project's default branch
   - Call `worktreeManager.removeWorktree(repoPath:worktreePath:deleteBranch:)` with `deleteBranch: true` only if merged
4. Aggregate results and show a single status message (only if count > 0)

**Error handling:** Each removal uses `try?` — one failing worktree does not block others. Errors are logged to stdout.

### New Methods on `WorktreeManager`

- **`pruneWorktrees(repoPath:)`** — runs `git worktree prune`
- **`isBranchMerged(repoPath:branch:into:)`** — runs `git branch --merged {into}`, returns `Bool` indicating whether `branch` appears in output

### Integration Point

In `RunwayStore.loadState()`, immediately after the tmux orphan cleanup block:

```swift
// Clean up orphaned worktrees (exist on disk but not in DB)
await cleanOrphanedWorktrees()
```

All required state (`sessions`, `projects`, `worktreeManager`) is loaded at this point.

### Status Message

Uses existing `statusMessage` property with `.info` level:

- 1 orphan: `"Cleaned up 1 orphaned worktree"`
- N orphans: `"Cleaned up N orphaned worktrees (M branches preserved — unmerged)"`

The parenthetical only appears when some branches were preserved due to being unmerged.

## Scope

- No UI changes beyond the status message
- No new database schema
- No periodic/background cleanup — startup only
- No changes to the existing "Delete Session & Worktree" flow

## Files Modified

| File | Change |
|------|--------|
| `Sources/GitOperations/WorktreeManager.swift` | Add `pruneWorktrees()` and `isBranchMerged()` |
| `Sources/App/RunwayStore.swift` | Add `cleanOrphanedWorktrees()`, call from `loadState()` |
| `Tests/GitOperationsTests/WorktreeManagerTests.swift` | Tests for new methods |
