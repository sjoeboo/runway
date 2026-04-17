# Menu Bar Session Status Counts — Design

**Date:** 2026-04-16
**Branch:** `feature-menu-bar-status`
**Status:** Approved

## Problem

The app window's toolbar (the top bar holding the Sessions/PRs picker, title, and action buttons) already surfaces live counts for two session statuses — `running` (green bolt) and `waiting` (orange raised hand) — via `toolbarSessionCounts` in `Sources/App/RunwayApp.swift:584-603`.

Two gaps today:

1. **Incomplete coverage.** `idle` and `error` sessions are invisible in the top bar even though they are part of the everyday picture (idle = agent waiting for user, error = needs attention).
2. **Theme drift.** `toolbarSessionCounts` is the only place in the app using hardcoded `.green` / `.orange` system colors. Every other status surface uses `SessionStatusIndicator` (`Sources/Views/Shared/PRBadges.swift:275-348`) which is theme-aware (`theme.chrome.green` / `.yellow` / `.red` / `.textDim`).

## Goal

Extend the toolbar's status cluster to show counts for `running`, `waiting`, `idle`, and `error`, using the existing `SessionStatusIndicator` component so the visual vocabulary matches the sidebar and session rows.

## Non-Goals

- Click-to-filter sidebar from the toolbar chips (deferred).
- `starting` and `stopped` counts — transient/terminal states, low signal in the top bar.
- Count-change animation.
- Extracting `toolbarSessionCounts` into its own file/module.

## Design

### Component Structure

Replace the body of `toolbarSessionCounts` (currently two `Label`s) with a four-chip `HStack`. Each chip is:

```swift
HStack(spacing: 3) {
    SessionStatusIndicator(status: .running, size: 7)
    Text("\(count)")
        .font(.caption)
        .foregroundStyle(theme.chrome.text)
}
.accessibilityElement(children: .combine)
.accessibilityLabel("\(count) running sessions")
```

The outer group is `HStack(spacing: 8)` mounted in the same `ToolbarItem(placement: .automatic)` at `Sources/App/RunwayApp.swift:579-581`.

### Statuses and Order

Left-to-right: `running → waiting → idle → error`. This keeps the most actionable (`running`, items needing input) leftmost and errors rightmost for contrast with the rest of the toolbar.

### Visual Spec

| Status | Indicator (from `SessionStatusIndicator` at size 7) | Count color |
|--------|-----------------------------------------------------|-------------|
| running | Filled green circle (`theme.chrome.green`) | `theme.chrome.text` |
| waiting | Filled yellow circle (`theme.chrome.yellow`) | `theme.chrome.text` |
| idle | Open circle, stroked (`theme.chrome.textDim`, 1.5pt) | `theme.chrome.text` |
| error | Filled red circle (`theme.chrome.red`) | `theme.chrome.text` |

At `size: 7` every status renders as a 7×7 shape per the existing `SessionStatusIndicator` logic — no `ProgressView` or SF Symbol paths hit at this size.

### Count Computation

Compute all four counts in a single pass rather than four separate `filter { … }.count` calls:

```swift
var running = 0, waiting = 0, idle = 0, error = 0
for session in store.sessions {
    switch session.status {
    case .running: running += 1
    case .waiting: waiting += 1
    case .idle:    idle += 1
    case .error:   error += 1
    default:       break
    }
}
```

### Zero-Count Behavior

- A chip is omitted entirely (not rendered at 0 opacity) when its count is 0.
- If all four counts are 0, the entire `HStack` group renders as `EmptyView` — matches today's behavior where the toolbar item disappears when there's nothing to show.

### Accessibility

- Each chip's `HStack` gets `.accessibilityElement(children: .combine)` plus `.accessibilityLabel("\(count) \(statusName) sessions")`.
- The outer group gets `.help(...)` summarising non-zero counts, replacing the current `"\(running) running, \(waiting) waiting"` tooltip. Format: `"2 running, 1 waiting, 3 idle"` (skips zeros).
- `SessionStatusIndicator` already exposes its own `.help` and `.accessibilityLabel`; setting a parent label on the chip doesn't conflict since the accessibility tree is collapsed via `.combine`.

## Files Affected

| File | Change |
|------|--------|
| `Sources/App/RunwayApp.swift` | Rewrite `toolbarSessionCounts` (~20 lines → ~40 lines). No new properties: `ContentView` (which owns this method) already has `@Environment(\.theme) private var theme` at line 130. |

No other files need to change. `SessionStatusIndicator` is already `public` and exported from the `Views` module which `RunwayApp` imports.

## Testing

- **Manual:** Start sessions in each of the four states, confirm each chip appears, disappears when count → 0, and updates live as statuses change. Switch themes (light/dark/Noctis/Tokyo Night variants) and confirm dot colors track the theme.
- **Automated:** No existing pattern for toolbar snapshot tests in this codebase. A unit test on a helper that returns the four counts from a `[Session]` would be cheap but the computation is trivial enough to skip. Defer to any reviewer preference.

## Risks & Open Questions

- **Toolbar horizontal space.** Four chips plus the existing "New Session" and session-scoped buttons could crowd narrow windows. Each chip is ~20pt wide (dot + 1-digit count + spacing), so worst case ~100pt added. Acceptable at the 1200pt default window size; may need a priority/collapse rule later.
- **Error visibility.** An `error` count > 0 is important but the chip looks identical in weight to the others. If this proves too subtle, a follow-up could add a subtle badge or pulse. Not in scope now.

## Out of Scope (Future Work)

- Click a chip → filter sidebar to that status.
- `starting` spinner count (usually 0 or 1 and transient).
- `stopped` count (usually high and noisy; lives in the sidebar anyway).
- Animated count transitions.
