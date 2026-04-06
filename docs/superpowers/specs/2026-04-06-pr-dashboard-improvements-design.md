# PR Dashboard Improvements — Design Spec

## Summary

Overhaul the PR dashboard to handle large PR volumes with better triage, instant filtering, and fresh status data. Key changes: hybrid parallel fetch (mine + review-requested), client-side grouped sections (Needs Attention / In Progress / Ready), Sessions toggle, tab sync fix, and TTL-based re-enrichment with immediate feedback after user actions.

## Approach

Incremental refactor of existing `PRDashboardView`, `RunwayStore`, and `PRManager`. No new view files — grouping logic layers onto the existing list. Detail drawer, row views, badges, and project PR tab are untouched.

---

## 1. Data Model Changes

### PullRequest (Sources/Models/PullRequest.swift)

Add two fields:

```swift
public var enrichedAt: Date?        // When checks/review were last fetched
public var origin: Set<PROrigin>    // Which fetch queries returned this PR
```

New enum:

```swift
public enum PROrigin: String, Codable, Sendable {
    case mine
    case reviewRequested
}
```

Computed property for TTL:

```swift
public var needsEnrichment: Bool {
    guard let enrichedAt else { return true }
    return Date().timeIntervalSince(enrichedAt) > 300 // 5 minutes
}
```

### Persistence (GRDB migration v9)

Add `enrichedAt` and `origin` columns to the PR cache table.

---

## 2. Fetch Strategy

### PRManager (Sources/GitHubOperations/PRManager.swift)

New method replacing filtered fetches:

```
fetchAllPRs() async throws -> [PullRequest]
```

- Runs `fetchPRs(filter: .mine)` and `fetchPRs(filter: .reviewRequested)` in parallel via TaskGroup
- Merges results, deduplicating by PR ID
- PRs appearing in both queries get `origin: [.mine, .reviewRequested]`
- PRs from only one query get the corresponding single origin

`PRFilter` enum remains internally for building `gh` CLI args but is no longer exposed in the public fetch API.

### RunwayStore (Sources/App/RunwayStore.swift)

- `fetchPRs()` calls `fetchAllPRs()` instead of the single filtered variant
- `prFilter` property removed from store — filtering is view-side only
- New `prTab: PRTab` property (replaces the view's local `@State`)
- Poll fingerprint uses `.mine` as the canary query

---

## 3. Re-enrichment

### TTL-based (5-minute)

`enrichPRs()` changes its filter condition:

- **Old:** `$0.checks.total == 0`
- **New:** `$0.needsEnrichment` (nil `enrichedAt` OR older than 5 minutes)

After enrichment, set `enrichedAt = Date()` on each enriched PR.

On each poll cycle (30s):
- Fingerprint changed → full re-fetch + enrich
- Fingerprint unchanged → still re-enrich any PRs past their TTL

### Immediate after actions

After `approvePR`, `commentOnPR`, `requestChangesOnPR`, `mergePR`, `togglePRDraft`:

1. Execute the `gh` command
2. Call new `reEnrichPR(_ pr: PullRequest)` — single `enrichChecks()` call for that PR
3. Update the PR in the `pullRequests` array with fresh data + `enrichedAt = Date()`
4. UI updates automatically via `@Observable`

---

## 4. Grouping Logic

PRs are bucketed into three groups. Groups are evaluated in priority order — a PR lands in the first group whose conditions match:

### 1. Needs Attention (red) — evaluated first
- `checks.hasFailed` OR `reviewDecision == .changesRequested`

### 2. Ready (green) — evaluated second
- `checks.allPassed` AND `reviewDecision == .approved`

### 3. In Progress (yellow) — everything else
- Catches: checks running, review pending, unenriched PRs, and any other intermediate state
- `checks.allPassed` AND `reviewDecision == .approved`

### Edge cases
| Scenario | Group |
|----------|-------|
| Checks passed, no review yet | In Progress |
| Approved, checks failing | Needs Attention |
| Approved, checks running | In Progress |
| Draft PRs | Normal grouping, dimmed. Hidden if "hide drafts" toggle active |

### Within each group
Sorted by `createdAt` descending (newest first).

### Group headers
- Collapsible (tap to toggle)
- Collapse state persisted via `@AppStorage`
- Empty groups hidden entirely

---

## 5. Tab Filtering

### Tabs: All | Mine | Review Requests

Pure client-side filters over the merged PR list:

- **All** — every PR fetched (mine + review-requested, deduplicated)
- **Mine** — `origin.contains(.mine)`
- **Review Requests** — `origin.contains(.reviewRequested)`

Grouping applies within the filtered set.

### Tab counts

Displayed inline: `Mine (12) | Review Requests (4) | All (14)`. Counts update instantly (client-side). Respect "hide drafts" toggle in counts.

### Tab sync fix

`selectedTab` moves from `@State` in `PRDashboardView` to `store.prTab`. Eliminates the bug where SwiftUI view recreation resets the tab to `.mine` while the data is from a different filter.

---

## 6. Sessions Toggle

Toolbar toggle icon (SF Symbol, e.g. `play.rectangle` or `terminal`) next to the existing draft visibility toggle.

When active:
- Filters to PRs whose ID exists in the session PR set
- Works across all tabs (composable with Mine/Review Requests)
- Icon shows accent color when active, dim when inactive
- Tooltip: "Show only session PRs" / "Show all PRs"

### Data flow

`RunwayStore` exposes:
```swift
var sessionPRIDs: Set<String> {
    Set(sessionPRs.values.map(\.id))
}
```

Passed to `PRDashboardView` as `sessionPRIDs: Set<String>`.

`PRDashboardView` gets `@AppStorage("showSessionPRsOnly")` toggle state.

---

## 7. View Changes

### PRDashboardView (Sources/Views/PRDashboard/PRDashboardView.swift)

**Toolbar:**
- Tab buttons get counts: `Mine (12)`
- Sessions toggle icon added between draft toggle and refresh
- No sort dropdown — grouping handles organization

**List body:**
- Flat `List` replaced with grouped `ForEach` over three sections
- Each section: collapsible header (colored icon + name + count + chevron) + PR rows
- Empty sections hidden

**New init parameters:**
- `sessionPRIDs: Set<String>`
- `selectedTab: Binding<PRTab>` (from store, not local `@State`)

**Filtering chain:**
`pullRequests` → tab filter → sessions filter → draft filter → group → sort within groups

### Unchanged files
- `PRRowView` — rows display identically
- `PRDetailDrawer` — detail panel untouched
- `PRBadges` — badges are fine as-is
- `ProjectPRsTab` — project-scoped view has its own fetch
- `PullRequest+ViewHelpers` — `ageText` etc. unchanged

---

## 8. Files Modified

| File | Change |
|------|--------|
| `Sources/Models/PullRequest.swift` | Add `enrichedAt`, `origin`, `PROrigin`, `needsEnrichment` |
| `Sources/GitHubOperations/PRManager.swift` | Add `fetchAllPRs()`, keep `PRFilter` internal |
| `Sources/App/RunwayStore.swift` | Hybrid fetch, TTL enrichment, `reEnrichPR()`, `prTab`, `sessionPRIDs`, remove `prFilter` |
| `Sources/App/RunwayApp.swift` | Wire new dashboard params (`sessionPRIDs`, tab binding) |
| `Sources/Views/PRDashboard/PRDashboardView.swift` | Grouped sections, tab counts, sessions toggle, fix tab sync |
| `Sources/Persistence/` | Migration v9: `enrichedAt` + `origin` columns |

## 9. Not In Scope

- Sort dropdown within groups (keep it simple — age sort only)
- Changes to PR detail drawer
- Changes to project PR tab
- Changes to sidebar session PR badges
- New PR notification system
