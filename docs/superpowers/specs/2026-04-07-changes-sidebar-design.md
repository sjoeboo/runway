# Changes Sidebar Design

**Date:** 2026-04-07
**Status:** Draft
**Feature:** Right-side collapsible sidebar showing changed files in a session's worktree

## Overview

Add a collapsible right sidebar to the session detail view that displays changed files in a tree structure with per-file addition/deletion counts. Clicking a file replaces the terminal with the existing DiffView showing that file's diff. Supports two modes: branch changes (all changes on this branch vs base) and working changes (uncommitted only).

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sidebar placement | Inside detail column via HStack + ResizableDivider | Reuses existing ResizableDivider; no NavigationSplitView restructuring; scoped to sessions only |
| Diff display | Replace terminal area | DiffView needs full width; viewing diffs while terminal runs isn't needed |
| Toggle mechanism | Header button + Cmd+3 shortcut | Discoverable via button, fast via shortcut; Cmd+1/2 already used |
| File tree content | Changed files only (not full repo tree) | Agent sessions may touch a handful of files in a large repo; compact and focused |
| Change modes | Branch + Working with toggle | Branch shows session's full output; Working shows uncommitted state |

## Layout & Interaction

### Open State

```
┌─────────────────────────────────────────────────────────────────┐
│ SessionHeaderView                                    [⎘ toggle] │
├──────────────────────────────────┬──┬────────────────────────────┤
│                                  │  │ Changes    [Branch|Working]│
│                                  │  │ 8 files  +127 -34         │
│       Terminal / DiffView        │██│ ▼ src/auth/               │
│                                  │██│   M middleware.ts  +45 -12 │
│                                  │██│   A jwt.ts         +38    │
│                                  │██│   D legacy-auth.ts    -22 │
│                                  │██│ ▼ tests/auth/             │
│                                  │██│   M middleware.test +32 -8 │
│                                  │██│   A jwt.test.ts    +22    │
│                                  │██│   M package.json    +2 -1 │
├──────────────────────────────────┴──┴────────────────────────────┤
│ SendTextBar                                                      │
└─────────────────────────────────────────────────────────────────┘
                                  ██ = ResizableDivider
```

### Closed State (Default)

```
┌─────────────────────────────────────────────────────────────────┐
│ SessionHeaderView                                    [⎘ toggle] │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                     Terminal (full width)                         │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ SendTextBar                                                      │
└─────────────────────────────────────────────────────────────────┘
```

### Interactions

- **Toggle sidebar:** Click header button or press Cmd+3. Animated expand/collapse.
- **Switch mode:** Click "Branch" or "Working" segmented control in sidebar header.
- **Expand/collapse directory:** Click directory row to toggle children visibility.
- **View file diff:** Click a file row → terminal area replaced with DiffView for that file, with a back button to return to terminal.
- **Resize:** Drag ResizableDivider between terminal and sidebar.
- **Width persistence:** Sidebar width saved to `@AppStorage("changesSidebarWidth")`, restored on reopen.

### Status Indicators

| Indicator | Color | Meaning |
|-----------|-------|---------|
| A | Green | Added (new file) |
| M | Yellow | Modified |
| D | Red | Deleted (filename struck through) |
| R | Cyan | Renamed |

## Data Architecture

### New Git Operations (WorktreeManager)

**`changedFiles(path:base:)`**
- Branch mode: `git diff --numstat --name-status <base>...HEAD` in the session's worktree path
- Working mode: `git diff --numstat --name-status HEAD`
- Parses output into `[FileChange]`
- Combines `--numstat` (for +/- counts) with `--name-status` (for A/M/D/R status)
- Base branch is determined via the existing `WorktreeManager.detectDefaultBranch()` method, which reads `refs/remotes/origin/HEAD` with fallback to checking local main/master

**`fileDiff(path:file:base:)`**
- Branch mode: `git diff <base>...HEAD -- <file>`
- Working mode: `git diff HEAD -- <file>`
- Returns raw unified diff string, passed directly to `DiffView(patch:)`

### New Model — FileChange (Models target)

```swift
public struct FileChange: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let status: FileChangeStatus  // .added, .modified, .deleted, .renamed
    public let additions: Int
    public let deletions: Int
}

public enum FileChangeStatus: Sendable {
    case added, modified, deleted, renamed
}
```

### Tree Construction — FileTreeNode (Models target)

```swift
public enum FileTreeNode: Identifiable {
    case directory(name: String, children: [FileTreeNode], additions: Int, deletions: Int)
    case file(FileChange)

    public var id: String { ... }
}
```

A pure function `buildFileTree([FileChange]) -> [FileTreeNode]` splits paths by `/`, groups into directories, and recursively builds the tree. Directories aggregate +/- counts from children. Single-child directory chains are collapsed (e.g., `src/auth/` shown as one node, not `src/` → `auth/`).

### State in RunwayStore

```swift
// UI state
var changesVisible: Bool = false          // sidebar open/closed
var changesMode: ChangesMode = .branch    // .branch or .working
var viewingDiffFile: FileChange? = nil    // when set, DiffView replaces terminal

// Data
var sessionChanges: [String: [FileChange]] = [:]  // keyed by session ID
```

### Refresh Strategy

- Fetch changes when sidebar is opened and when mode is toggled.
- Refresh on a 10-second timer while sidebar is visible.
- No refresh when sidebar is collapsed.
- Cancel any in-flight fetch when session changes or sidebar closes.

## Component Breakdown

### New Files

| File | Target | Purpose |
|------|--------|---------|
| `Sources/Views/SessionDetail/ChangesSidebarView.swift` | Views | Sidebar container: header with mode toggle, summary stats, scrollable file tree |
| `Sources/Views/SessionDetail/FileTreeView.swift` | Views | Recursive tree rendering with disclosure groups, status badges, +/- counts, file selection |
| `Sources/Models/FileChange.swift` | Models | `FileChange`, `FileChangeStatus`, `FileTreeNode`, `ChangesMode`, and `buildFileTree()` |

### Modified Files

| File | Change |
|------|--------|
| `Sources/GitOperations/WorktreeManager.swift` | Add `changedFiles(path:base:)` and `fileDiff(path:file:base:)` methods |
| `Sources/Views/SessionDetail/SessionDetailView.swift` | Wrap terminal + changes sidebar in HStack with ResizableDivider; conditional DiffView when `viewingDiffFile` is set |
| `Sources/Views/SessionDetail/SessionHeaderView.swift` | Add changes sidebar toggle button (right side of header) |
| `Sources/App/RunwayStore.swift` | Add state properties, refresh timer, `toggleChangesSidebar()`, `fetchChanges()`, `selectDiffFile()` |
| `Sources/App/RunwayApp.swift` | Add Cmd+3 keyboard shortcut binding |

### Reused As-Is

| Component | Usage |
|-----------|-------|
| `DiffView` | Initialized with `DiffView(patch:)` for single-file unified diff display |
| `ResizableDivider` | Placed between terminal and changes sidebar |
| `ShellRunner.runGit()` | Subprocess execution for git commands |
| Theme environment | `theme.chrome.*` colors for consistent styling |

## Scope Exclusions

- No staging or committing from the sidebar — read-only view only
- No inline editing or conflict resolution
- No file content preview for unmodified files
- No blame or history view
- No changes sidebar on project pages or PR dashboard — session detail only
