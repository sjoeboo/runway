# PR Grouping & Mergeability Design

## Summary

Refine the PR dashboard grouping from 3 categories to 5, splitting the catch-all "In Progress" group into meaningful pipeline stages and adding merge status visibility to all PR rows. Draft PRs get their own collapsed section outside the main pipeline.

## Current State

The PR dashboard groups PRs into three buckets:

- **Needs Attention** (red): failed checks OR changes requested
- **In Progress** (yellow): everything else (catch-all)
- **Ready** (green): all checks passed AND approved

The problem: "In Progress" conflates PRs waiting on CI with PRs that have passed all checks but are waiting on human review. The model already has `mergeable` and `mergeStateStatus` fields from GitHub enrichment, but they aren't surfaced in the list view or used in grouping.

## Design

### New Grouping Model

Replace `PRGroup` with 5 groups, evaluated in priority order (first match wins):

| Group | Icon | Color | Condition |
|-------|------|-------|-----------|
| **Needs Attention** | `exclamationmark.circle` | red | Failed checks, changes requested, merge conflicts (`.conflicting`), or merge blocked (`.blocked`) |
| **In Progress** | `clock` | yellow | Checks still running or pending (not all passed) |
| **Waiting for Review** | `eye` | blue (`theme.chrome.accent`) | All checks passed, review is `.pending` or `.none` |
| **Ready** | `checkmark.circle` | green | All checks passed AND review approved |
| **Drafts** | `circle.dashed` | dim (`.textDim`) | `isDraft == true` — always routed here regardless of other status |

**Evaluation order**: Drafts are checked first (always routed to the Drafts section). For non-draft PRs, evaluate Needs Attention → In Progress → Waiting for Review → Ready. First match wins.

**Edge cases**:
- PR with approved review but failed checks → Needs Attention (failed checks take priority)
- PR with approved review but merge conflicts → Needs Attention (conflicts take priority)
- PR with all checks passed, approved, but merge blocked → Needs Attention (blocked takes priority)
- PR with all checks passed, approved, but behind → Ready (behind is just a badge, not a demotion)
- PR with no checks at all and pending review → Waiting for Review (treat `checks.total == 0` like all-passed for grouping, since some repos don't use CI)
- Unenriched PR (no enrichment data yet) → In Progress (safe default while loading)

### Merge Status Badge

A new `MergeStatusBadge` view, styled as a capsule pill consistent with the existing `ReviewDecisionBadge` capsule style. Placed inline in the PR row metadata line, after `CheckSummaryBadge` and `ReviewDecisionBadge`.

| `mergeStateStatus` | `mergeable` | Badge | Color |
|---------------------|-------------|-------|-------|
| `.clean` | `.mergeable` | `✓ Clean` | green |
| `.behind` | any | `↓ Behind` | yellow |
| `.blocked` | any | `⊘ Blocked` | orange |
| any | `.conflicting` | `⚠ Conflicts` | red |
| `.unstable` | any | `~ Unstable` | yellow |
| `.dirty` | any | `⚠ Dirty` | orange |
| `.hasHooks` | `.mergeable` | `✓ Clean` | green (hooks don't block) |
| `.unknown` / `nil` | `.unknown` / `nil` | (hidden) | — |

The badge is only shown when merge status is known (after enrichment). When both `mergeable` and `mergeStateStatus` are nil/unknown, the badge is hidden.

**Priority**: `conflicting` overrides `mergeStateStatus` (a PR can be `.behind` + `.conflicting` — show conflicts).

### AppStorage Changes

Add two new persistence keys for the new group sections:

- `@AppStorage("prGroupWaitingForReviewExpanded")` — default `true`
- `@AppStorage("prGroupDraftsExpanded")` — default `false` (collapsed by default)

### Draft Handling

When the Drafts group exists, the "Hide drafts" toggle (`hideDrafts`) in the toolbar controls whether the Drafts section is shown at all. When `hideDrafts` is true, the entire Drafts section is hidden. When false, it's shown (collapsed by default).

This replaces the current behavior where `hideDrafts` filters drafts out of all groups.

### Files to Modify

| File | Change |
|------|--------|
| `Sources/Views/PRDashboard/PRDashboardView.swift` | Update `PRGroup` enum (5 cases), `group(for:)` logic, add `@AppStorage` for new groups, update `groupColor`/`groupIcon`/`isGroupExpanded`/`toggleGroupExpanded`, separate draft filtering from `groupedPRs()` |
| `Sources/Views/Shared/PRBadges.swift` | Add `MergeStatusBadge` view with capsule style |
| `Sources/Views/PRDashboard/PRDashboardView.swift` (PRRowView) | Add `MergeStatusBadge` to the metadata HStack after `ReviewDecisionBadge` |
| `Sources/Views/ProjectPage/ProjectPRsTab.swift` | Add `MergeStatusBadge` to project PR rows for consistency |

### Not In Scope

- Changing the PR detail drawer (it already shows merge status)
- Changing the sidebar session row badges
- Adding merge actions to the list view (merge button stays in the drawer)
- Changing the enrichment pipeline or polling intervals
