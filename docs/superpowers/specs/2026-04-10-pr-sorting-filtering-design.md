# PR Column Layout, Sorting & Filtering

## Overview

Add sortable columns and a persistent filter bar to the PR dashboard. PRs remain organized in their existing groups (Needs Attention, In Progress, Waiting for Review, Ready, Drafts), but within each group the data is displayed in aligned columns that can be sorted, and a filter bar lets users narrow the list by repo, author, age, checks, review status, and merge status.

## Column Layout

The PR list switches from badge-based rows to a compact column grid. Column headers appear once at the top of the list, below the filter bar and above the first group.

### Columns (left to right)

| Column | Content | Width | Sort Behavior |
|--------|---------|-------|---------------|
| Title | State badge + PR # + title text | Flexible (fills remaining) | Alphabetical by title |
| Repo | Repository short name | Fixed ~100pt, truncates | Alphabetical |
| Author | GitHub username | Fixed ~70pt, truncates | Alphabetical |
| Age | Relative time from `createdAt` | Fixed ~50pt | Oldest/newest by date |
| Checks | Pass/total with colored icon | Fixed ~55pt | By pass ratio, then total |
| Review | Approved / Changes / Pending | Fixed ~55pt | Approved > Pending > Changes |
| Merge | Clean / Conflicts / Behind / Blocked | Fixed ~65pt | Clean > Behind > Conflicts > Blocked |

### Sorting

- Click a column header to sort ascending; click again for descending.
- Active sort column shows ▲ (ascending) or ▼ (descending) indicator.
- Sorting applies within each group — group order is fixed.
- Default sort: Age descending (newest first).
- Sort preference persists via `@AppStorage`.

## Filter Bar

A persistent bar above the column headers, always visible. Contains a row of SwiftUI `Menu` dropdown buttons.

### Filter Dimensions

| Filter | Options |
|--------|---------|
| Repo | "All", then each distinct repo from current PRs (dynamic) |
| Author | "All", then each distinct author from current PRs (dynamic) |
| Age | "Any", "Last 24h", "Last 7 days", "Last 30 days", "Older than 30 days" |
| Checks | "All", "Passing", "Failing", "Pending" |
| Review | "All", "Approved", "Changes Requested", "Pending" |
| Merge | "All", "Clean", "Conflicts", "Behind", "Blocked" |

### Behavior

- Filters are additive (AND logic).
- Active filter buttons are highlighted (accent color).
- A "Clear" button appears when any filter is non-default, resetting all to defaults.
- Filters apply before grouping — empty groups are hidden.
- Group counts update to reflect filtered totals.
- Existing Hide Drafts and Session PRs Only toggles remain in the toolbar (separate from the filter bar).
- Filter selections persist via `@AppStorage`.

## Data Model

### New Types

```swift
enum PRSortField: String, CaseIterable {
    case title, repo, author, age, checks, review, mergeStatus
}

enum PRSortOrder: String {
    case ascending, descending
}

enum PRAgeBucket: String, CaseIterable {
    case any
    case last24h
    case last7d
    case last30d
    case olderThan30d
}

struct PRFilterState {
    var repo: String?              // nil = All
    var author: String?            // nil = All
    var ageBucket: PRAgeBucket = .any
    var checks: CheckStatus?       // nil = All (reuses existing enum)
    var review: ReviewDecision?    // nil = All (reuses existing enum)
    var mergeStatus: MergeStateStatus? // nil = All (reuses existing enum)

    var isActive: Bool { /* true if any filter is non-default */ }
    func matches(_ pr: PullRequest) -> Bool { /* AND logic across all fields */ }
    mutating func clear() { /* reset all to defaults */ }
}
```

### Filtering Pipeline (in order)

1. Tab filter (All / Mine / Review Requested) — existing
2. Hide Drafts toggle — existing
3. Session PRs Only toggle — existing
4. **`PRFilterState.matches()` — NEW**
5. Group into `PRGroup` sections — existing
6. **Sort within each group by `PRSortField` — NEW**

## View Architecture

### Modified Files

- **`PRDashboardView.swift`** — Add `PRFilterBar` above the list, add column header row, refactor PR list to use grid-aligned rows. Add `@AppStorage` for sort/filter state.
- **`PRRowView.swift`** — Refactor body from free-form `HStack` with badges to a grid-aligned row matching column widths.

### New Files

- **`PRFilterBar.swift`** (in `Views/PRDashboard/`) — Persistent filter bar with `Menu` buttons + Clear. Takes `Binding<PRFilterState>` and current PR list for computing dynamic options.
- **`PRColumnHeader.swift`** (in `Views/PRDashboard/`) — Clickable column header row. Takes `Binding<PRSortField>` and `Binding<PRSortOrder>`. Active column shows sort direction indicator.
- **`PRSortFilter.swift`** (in `Views/PRDashboard/` or `Models/`) — Contains `PRSortField`, `PRSortOrder`, `PRAgeBucket`, `PRFilterState` types plus sorting comparator and filter matching logic.

### Unchanged

- `PRDetailDrawer` — untouched
- `PRGroup` enum and `prGroup(for:)` — untouched
- Group collapsibility — untouched
- `PRBadges.swift` — badges reused in column cells
- `ProjectPRsTab` — out of scope

### Layout Hierarchy

```
PRDashboardView
├── Toolbar (tabs, refresh, session toggle, hide drafts)
├── PRFilterBar              ← NEW
├── PRColumnHeader           ← NEW
├── ForEach(groups)
│   ├── Group header (collapsible, with filtered count)
│   └── ForEach(sorted PRs in group)
│       └── PRRowView        ← MODIFIED (grid-aligned)
└── PRDetailDrawer (resizable, on selection)
```

## Edge Cases

- **All PRs filtered out**: Centered message "No PRs match current filters" with Clear button.
- **Empty group after filter**: Group header hidden entirely.
- **Window resize**: Title column flexes; fixed columns hold width. At very narrow widths, columns truncate with ellipsis.

## Theme Integration

- Column headers: `chrome.secondaryText` for labels, `chrome.accent` for active sort indicator.
- Filter bar background: `chrome.surface`.
- Active filter buttons: subtle accent highlight.

## Persistence

All stored in `@AppStorage` with `"pr"` key prefix:
- `prSortField` (String, default: "age")
- `prSortOrder` (String, default: "descending")
- `prFilterRepo` (String, default: "" for All)
- `prFilterAuthor` (String, default: "" for All)
- `prFilterAge` (String, default: "any")
- `prFilterChecks` (String, default: "" for All)
- `prFilterReview` (String, default: "" for All)
- `prFilterMerge` (String, default: "" for All)
