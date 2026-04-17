# Menu Bar Session Status Counts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the app window's toolbar status cluster to show live counts for `running`, `waiting`, `idle`, and `error` sessions, using the existing theme-aware `SessionStatusIndicator` component.

**Architecture:** The counting logic lives as a pure function in the `Models` module (unit-testable). The view in `Sources/App/RunwayApp.swift` consumes it and renders one chip per non-zero status using `SessionStatusIndicator` + a count `Text`. All colors flow through the `Theme` environment — no hardcoded system colors.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Testing (`@Test` / `#expect`), SwiftPM.

**Spec:** `docs/superpowers/specs/2026-04-16-menu-bar-status-counts-design.md`

---

## File Structure

| File | Role | Action |
|------|------|--------|
| `Sources/Models/SessionStatusCounts.swift` | Pure helper: `[Session] → (running, waiting, idle, error)` tuple | **Create** |
| `Tests/ModelsTests/SessionStatusCountsTests.swift` | Unit tests for the helper | **Create** |
| `Sources/App/RunwayApp.swift` | `toolbarSessionCounts` view, lines 584-603 | **Modify** |

No changes to `Theme`, `RunwayStore`, `Views`, or any other module. `SessionStatusIndicator` is already `public` in the `Views` module which `App` imports.

---

## Task 1: Add `sessionStatusCounts` helper in Models with tests

**Files:**
- Create: `Sources/Models/SessionStatusCounts.swift`
- Create: `Tests/ModelsTests/SessionStatusCountsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ModelsTests/SessionStatusCountsTests.swift` with this exact content:

```swift
import Foundation
import Testing

@testable import Models

@Test func statusCountsEmpty() {
    let counts = [Session]().statusCounts
    #expect(counts.running == 0)
    #expect(counts.waiting == 0)
    #expect(counts.idle == 0)
    #expect(counts.error == 0)
}

@Test func statusCountsOneOfEach() {
    let sessions = [
        Session(title: "a", path: "/tmp", status: .running),
        Session(title: "b", path: "/tmp", status: .waiting),
        Session(title: "c", path: "/tmp", status: .idle),
        Session(title: "d", path: "/tmp", status: .error),
    ]
    let counts = sessions.statusCounts
    #expect(counts.running == 1)
    #expect(counts.waiting == 1)
    #expect(counts.idle == 1)
    #expect(counts.error == 1)
}

@Test func statusCountsIgnoresStartingAndStopped() {
    let sessions = [
        Session(title: "a", path: "/tmp", status: .starting),
        Session(title: "b", path: "/tmp", status: .stopped),
        Session(title: "c", path: "/tmp", status: .running),
    ]
    let counts = sessions.statusCounts
    #expect(counts.running == 1)
    #expect(counts.waiting == 0)
    #expect(counts.idle == 0)
    #expect(counts.error == 0)
}

@Test func statusCountsAggregates() {
    let sessions = [
        Session(title: "a", path: "/tmp", status: .running),
        Session(title: "b", path: "/tmp", status: .running),
        Session(title: "c", path: "/tmp", status: .running),
        Session(title: "d", path: "/tmp", status: .idle),
        Session(title: "e", path: "/tmp", status: .idle),
        Session(title: "f", path: "/tmp", status: .error),
    ]
    let counts = sessions.statusCounts
    #expect(counts.running == 3)
    #expect(counts.waiting == 0)
    #expect(counts.idle == 2)
    #expect(counts.error == 1)
}

@Test func statusCountsHasAnyActive() {
    let none = [Session]().statusCounts
    #expect(none.hasAny == false)

    let some = [Session(title: "a", path: "/tmp", status: .idle)].statusCounts
    #expect(some.hasAny == true)

    let onlyStopped = [Session(title: "a", path: "/tmp", status: .stopped)].statusCounts
    #expect(onlyStopped.hasAny == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionStatusCountsTests 2>&1 | tail -20`

Expected: build error — `value of type '[Session]' has no member 'statusCounts'` (or similar). The key is that `statusCounts` and `SessionStatusCounts` do not yet exist.

- [ ] **Step 3: Write the helper**

Create `Sources/Models/SessionStatusCounts.swift` with this exact content:

```swift
import Foundation

/// Aggregated session status counts for the four statuses surfaced in the toolbar.
/// `starting` and `stopped` are intentionally excluded — see design spec
/// `docs/superpowers/specs/2026-04-16-menu-bar-status-counts-design.md`.
public struct SessionStatusCounts: Sendable, Equatable {
    public let running: Int
    public let waiting: Int
    public let idle: Int
    public let error: Int

    public init(running: Int = 0, waiting: Int = 0, idle: Int = 0, error: Int = 0) {
        self.running = running
        self.waiting = waiting
        self.idle = idle
        self.error = error
    }

    /// True if any of the four tracked statuses has a non-zero count.
    public var hasAny: Bool {
        running > 0 || waiting > 0 || idle > 0 || error > 0
    }
}

extension Array where Element == Session {
    /// Single-pass aggregation of session statuses into toolbar-relevant buckets.
    public var statusCounts: SessionStatusCounts {
        var running = 0
        var waiting = 0
        var idle = 0
        var error = 0
        for session in self {
            switch session.status {
            case .running: running += 1
            case .waiting: waiting += 1
            case .idle: idle += 1
            case .error: error += 1
            case .starting, .stopped: break
            }
        }
        return SessionStatusCounts(
            running: running,
            waiting: waiting,
            idle: idle,
            error: error
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionStatusCountsTests 2>&1 | tail -20`

Expected: all 5 tests pass. Output should include a "Test run with N tests passed" line with no failures.

- [ ] **Step 5: Run the full Models test suite to confirm no regressions**

Run: `swift test --filter ModelsTests 2>&1 | tail -10`

Expected: all Models tests pass (existing + the 5 new ones).

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/SessionStatusCounts.swift Tests/ModelsTests/SessionStatusCountsTests.swift
git commit -m "feat(models): add SessionStatusCounts helper for toolbar badges"
```

---

## Task 2: Rewrite `toolbarSessionCounts` to use the helper and `SessionStatusIndicator`

**Files:**
- Modify: `Sources/App/RunwayApp.swift:584-603` (the `toolbarSessionCounts` computed view and its single usage at line 579-581).

- [ ] **Step 1: Replace the `toolbarSessionCounts` implementation**

Open `Sources/App/RunwayApp.swift`. Find the existing block (currently lines 584-603):

```swift
@ViewBuilder
private var toolbarSessionCounts: some View {
    let running = store.sessions.filter { $0.status == .running }.count
    let waiting = store.sessions.filter { $0.status == .waiting }.count
    if running > 0 || waiting > 0 {
        HStack(spacing: 6) {
            if running > 0 {
                Label("\(running)", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if waiting > 0 {
                Label("\(waiting)", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .help("\(running) running, \(waiting) waiting")
    }
}
```

Replace it with this exact code:

```swift
@ViewBuilder
private var toolbarSessionCounts: some View {
    let counts = store.sessions.statusCounts
    if counts.hasAny {
        HStack(spacing: 8) {
            if counts.running > 0 {
                statusChip(status: .running, count: counts.running, label: "running")
            }
            if counts.waiting > 0 {
                statusChip(status: .waiting, count: counts.waiting, label: "waiting")
            }
            if counts.idle > 0 {
                statusChip(status: .idle, count: counts.idle, label: "idle")
            }
            if counts.error > 0 {
                statusChip(status: .error, count: counts.error, label: "error")
            }
        }
        .help(toolbarCountsHelpText(counts))
    }
}

private func statusChip(status: SessionStatus, count: Int, label: String) -> some View {
    HStack(spacing: 3) {
        SessionStatusIndicator(status: status, size: 7)
        Text("\(count)")
            .font(.caption)
            .foregroundStyle(theme.chrome.text)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(count) \(label) \(count == 1 ? "session" : "sessions")")
}

private func toolbarCountsHelpText(_ counts: SessionStatusCounts) -> String {
    var parts: [String] = []
    if counts.running > 0 { parts.append("\(counts.running) running") }
    if counts.waiting > 0 { parts.append("\(counts.waiting) waiting") }
    if counts.idle > 0 { parts.append("\(counts.idle) idle") }
    if counts.error > 0 { parts.append("\(counts.error) error") }
    return parts.joined(separator: ", ")
}
```

Note: `statusChip` and `toolbarCountsHelpText` go inside the same `ContentView` struct as `toolbarSessionCounts`. Place them directly below `toolbarSessionCounts` (after line 603 in the original numbering).

- [ ] **Step 2: Verify the project builds**

Run: `swift build 2>&1 | tail -20`

Expected: `Build complete!` with no errors and no new warnings related to the edited lines.

If you get `cannot find 'SessionStatusCounts' in scope` — `Models` is already imported at `Sources/App/RunwayApp.swift:2`, so the helper (and `SessionStatusCounts`) should be visible without further work. If not, confirm the new file was saved under `Sources/Models/`.

If you get `cannot find 'SessionStatusIndicator' in scope` — `Views` is already imported at `Sources/App/RunwayApp.swift:9`, so this should compile. Confirm.

- [ ] **Step 3: Run the full test suite to confirm no regressions**

Run: `swift test 2>&1 | tail -10`

Expected: all 336 tests (331 existing + 5 new) pass.

- [ ] **Step 4: Run the format and lint check**

Run: `make check 2>&1 | tail -20`

Expected: build + test + lint + format all pass. If `swift-format` rewrites anything in the edited block, accept its output — the project's CI enforces this style.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RunwayApp.swift
git commit -m "feat(app): show running/waiting/idle/error counts in toolbar"
```

---

## Task 3: Manual verification

**Files:** none (runtime verification only).

- [ ] **Step 1: Launch the app**

Run: `swift run Runway`

Expected: app window opens. If there are sessions in the DB from prior runs, their statuses will drive the toolbar chips immediately.

- [ ] **Step 2: Verify chips appear for each status**

For each of the four statuses, confirm a chip appears with the correct count and a dot colored via `theme.chrome.*`:

| Status | How to trigger | Expected chip |
|--------|----------------|---------------|
| `running` | Start a new session via ⌘N; while the agent is producing output | Filled green dot + count |
| `waiting` | Let an agent reach a permission prompt (or use an agent that emits `UserPromptSubmit` → `Notification`) | Filled yellow dot + count |
| `idle` | Let a running session finish producing output (agent prints and awaits input) | Open gray circle + count |
| `error` | Start a session with an invalid command in settings, OR manually mark a session errored via the DB if easier | Filled red dot + count |

Left-to-right order must be: running, waiting, idle, error.

- [ ] **Step 3: Verify zero-count chips are hidden**

Stop all sessions (Command menu → "Stop All Sessions"). With no sessions in any of the four tracked statuses, the entire `HStack` group should disappear from the toolbar.

Delete stopped sessions (Command menu → "Delete Stopped Sessions") and confirm the toolbar group stays hidden when only no-op states (`starting`, `stopped`) or zero sessions exist.

- [ ] **Step 4: Verify theme integration**

Open Settings → switch between several themes (at minimum: one light, one dark, Noctis, Tokyo Night variants). Confirm the chip dot colors change with the theme (green/yellow/red intensity shifts). The count `Text` should remain legible in all themes.

- [ ] **Step 5: Verify accessibility label**

With VoiceOver enabled (⌘F5), focus each chip. Expected spoken label format: `"3 idle sessions"` (or `"1 running session"` — singular when count is 1).

Hover the entire chip group: the `.help` tooltip should read e.g. `"2 running, 1 idle"` — only non-zero statuses, comma-separated.

- [ ] **Step 6: Quit the app**

Close the window or ⌘Q.

- [ ] **Step 7: No commit required for this task**

Task 3 is verification only. If you find a defect, fix it and commit under a new `fix:` message before proceeding. Otherwise move on.

---

## Final: Ready for PR

After all three tasks are complete, the branch should contain two commits:

1. `feat(models): add SessionStatusCounts helper for toolbar badges`
2. `feat(app): show running/waiting/idle/error counts in toolbar`

Then run the project's standard pre-ship flow:

```bash
# Simplify pass (catches reuse/quality/efficiency issues)
# Run /simplify

# Then the pre-ship or ship-it pipeline
# Run /pre-ship  (or /ship-it for smaller changes)
```
