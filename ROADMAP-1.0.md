# Runway 1.0 Roadmap

> Generated from comprehensive 10-agent audit of v0.8.0 (April 2026)
> 130+ findings across bugs, performance, UX, test coverage, and feature gaps

## Overview

```
v0.8.0 (current) ──► v0.8.x (ship-stoppers) ──► v0.9.0 (reliability) ──► v0.9.x (polish+features) ──► v1.0.0
     │                    │                           │                         │                          │
     │                 4 criticals               core infra               accessibility              feature-complete
     │                 + quick wins               + safety                + UX polish                 + test coverage
     │                                           + perf                  + features                  + final tuning
     │                                                                                               
     19K LOC            ~200 LOC changed          ~800 LOC changed       ~2500 LOC changed           ~1000 LOC changed
     78 files           ~8 files touched          ~15 files touched      ~35 files touched            ~20 files touched
```

## Work Streams

Seven parallel work streams, each with internal dependency ordering:

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  WS1: Critical  │  │  WS2: Terminal  │  │  WS3: HookServer│  │  WS4: Store     │
│  Bug Fixes      │  │  & PTY Safety   │  │  Reliability    │  │  Architecture   │
│                 │  │                 │  │                 │  │                 │
│  C1 branch name │  │  C4 cache evict │  │  M8 handler reg │  │  P1 split store │
│  C2 graphql inj │  │  M5 FD race     │  │  M9 conn timeout│  │  M4 stale enrich│
│  C3 precondition│  │  M6 zombie proc │  │  M10 auto-restart│  │  M7 orphan tasks│
│  M12 NSColor    │  │  M13 mouse rest │  │  M11 quit cleanup│  │  P3 poll off-main│
│                 │  │  P5 search alloc│  │                 │  │  P6 filter cache│
│                 │  │  dead code clean│  │                 │  │  P7 timer jitter│
│                 │  │                 │  │                 │  │  P8 rebuild tree│
│                 │  │                 │  │                 │  │  P9 cache bounds│
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │                    │
         ▼                    ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  WS5: UX/UI     │  │  WS6: Features  │  │  WS7: Testing   │
│  Polish         │  │                 │  │                 │
│                 │  │  F1 cost track  │  │  Top 10 tests   │
│  U1 accessibility│  │  F2 transcripts │  │  Migration tests│
│  U2 error recov │  │  F3 housekeeping│  │  E2E hook→status│
│  U3 theme colors│  │  F4 onboarding  │  │  ShellRunner    │
│  U6 send bar lbl│  │  F5 error retry │  │  RunwayStore    │
│  U7 first-run   │  │  F6 git rollback│  │  coverage       │
│  U8-12 polish   │  │  F7 prompt lib  │  │                 │
│                 │  │  F8 batch action│  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

---

## Phase 1: v0.8.x — Ship-Stoppers (4 criticals + quick wins)

**Goal:** Fix bugs that cause crashes, data corruption, or security issues.
**Scope:** ~200 LOC changed, ~8 files touched.
**Timeline target:** 1-2 sessions.

### 1.1 Branch Name Sanitization [C1] — HIGHEST PRIORITY
**Files:** `WorktreeManager.swift`, `RunwayStore.swift`
**Problem:** `sanitizeBranchName` replaces `/` with `-`, breaking:
- PR-to-session linking (PR `headBranch` = `feature/my-work` ≠ session `worktreeBranch` = `feature-my-work`)
- Branch deletion on session delete (targets wrong branch name)
- Affects ALL users with `feature/`, `fix/`, `user/` branch patterns

**Fix:**
1. In `WorktreeManager.createWorktree`: use original branch name for `git worktree add -b <original>`, only sanitize the *directory path*
2. Store the real branch name in `Session.worktreeBranch` (not the sanitized one)
3. In `removeWorktree`: use `git -C <worktreePath> rev-parse --abbrev-ref HEAD` to get actual branch name
4. Add collision detection: check `git rev-parse --verify <branch>` before creating, append `-2`, `-3` if exists

**Test:** Create session with title "Feature: Auth Login", verify branch is `feature/auth-login` (or whatever the prefix produces), verify PR linking works, verify branch deletion targets the right name.

### 1.2 TerminalPalette Precondition Crash [C3]
**Files:** `AppTheme.swift`
**Problem:** `precondition(ansi.count == 16)` crashes app on malformed theme JSON. Can create unrecoverable crash loop if it's the active theme.

**Fix:** Replace `precondition` with:
```swift
public init(ansi: [Color], ...) {
    // Pad or truncate to exactly 16 entries
    var palette = ansi
    while palette.count < 16 { palette.append(.gray) }
    if palette.count > 16 { palette = Array(palette.prefix(16)) }
    self.ansi = palette
    ...
}
```

### 1.3 GraphQL Injection [C2]
**Files:** `PRManager.swift`
**Problem:** `nodeID` interpolated into GraphQL mutation string without validation.

**Fix:** Validate before use:
```swift
let sanitized = nodeID.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "=" }
guard sanitized == nodeID, !nodeID.isEmpty else {
    throw PRError.invalidNodeID(nodeID)
}
```

### 1.4 Quick Wins (1-line fixes)
- **M8:** Move `hookServer.onEvent` registration BEFORE `hookServer.start()` in `startHookServer()` — `RunwayStore.swift:826`
- **M4:** Add `guard !Task.isCancelled else { return }` before the merge in `enrichPRs()` — `RunwayStore.swift:1062`
- **M3:** Use `try?` for each independent fetch in `fetchAllPRs` so one failure doesn't discard the other — `PRManager.swift:73-96`

---

## Phase 2: v0.9.0 — Reliability & Core Infrastructure

**Goal:** Eliminate data loss risks, fix resource leaks, and address critical performance issues.
**Scope:** ~800 LOC changed, ~15 files touched.
**Timeline target:** 3-5 sessions.

### 2.1 Terminal & PTY Safety [WS2]

#### 2.1.1 Cache Eviction Process Cleanup [C4]
**File:** `TerminalSessionCache.swift`
```swift
private func evictIfNeeded() {
    while views.count > maxSize {
        guard let lruKey = lastAccess.min(by: { $0.value < $1.value })?.key else { break }
        // Kill the attach process before eviction
        if let (view, _) = views[lruKey] {
            view.process?.terminate()
        }
        views.removeValue(forKey: lruKey)
        lastAccess.removeValue(forKey: lruKey)
    }
}
```

#### 2.1.2 PTY FD Race Fix [M5]
**File:** `PTYProcess.swift`
Hold the lock through entire write/ioctl:
```swift
public func write(_ data: Data) {
    let fd = lock.withLock { _isAlive ? masterFD : -1 }
    guard fd >= 0 else { return }
    data.withUnsafeBytes { ... Darwin.write(fd, ...) }
}
```
Also move `close(fd)` from readSource cancel handler to `deinit`, after both sources confirmed cancelled.

#### 2.1.3 Zombie Process Fix [M6]
**File:** `PTYProcess.swift`
In `deinit`, after `handleExit()`:
```swift
deinit {
    handleExit()
    // Reap zombie if child already exited
    var status: Int32 = 0
    waitpid(pid, &status, WNOHANG)
}
```

#### 2.1.4 Mouse Restore Fix [M13]
**File:** `TerminalPane.swift`
In the deferred restore block, re-resolve the terminal from firstResponder instead of using captured reference.

#### 2.1.5 Search Memory Fix [P5]
**File:** `TerminalTabView.swift`
Replace `getBufferAsData()` with row-by-row iteration using `getLine(row:)`.

#### 2.1.6 Dead Code Removal
**File:** `TerminalKeyEventMonitor.swift`
Remove the entire file — it's never called and would cause double key delivery if activated.

### 2.2 HookServer Reliability [WS3]

#### 2.2.1 Connection Timeout [M9]
**File:** `HookServer.swift`
Add 30-second timeout after `connection.start()`:
```swift
let timeout = DispatchWorkItem { connection.cancel() }
connectionQueue.asyncAfter(deadline: .now() + 30, execute: timeout)
// Cancel timeout when full request received
```

#### 2.2.2 Auto-restart on Failure [M10]
**File:** `RunwayStore.swift`
Add `stateUpdateHandler` to the running listener that restarts on `.failed`:
```swift
listener.stateUpdateHandler = { [weak self] state in
    if case .failed = state {
        Task { await self?.restartHookServer() }
    }
}
```

#### 2.2.3 Clean Quit [M11]
**File:** `RunwayStore.swift`
In the `willTerminate` handler: delete the port file, call `hookServer.stop()`.

### 2.3 ShellRunner Timeout [M1]
**File:** `ShellRunner.swift`
Add timeout parameter with `withThrowingTaskGroup` pattern:
```swift
public static func run(
    executable: String,
    args: [String],
    cwd: String? = nil,
    env: [String: String]? = nil,
    timeout: Duration = .seconds(30)
) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask { /* existing execution logic */ }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw ShellError.timeout(executable: executable, args: args)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

### 2.4 Database Nil Visibility [M2]
**File:** `RunwayStore.swift`
Replace dismissable toast with persistent banner:
```swift
// Add a persistent flag
var databaseFailed: Bool = false

// In init, after catch:
self.databaseFailed = true
// Show blocking alert on first interaction, not just a toast
```

### 2.5 NSColor Crash Fix [M12]
**File:** `TerminalPane.swift`
```swift
let nsColor = NSColor(swiftUIColor).usingColorSpace(.deviceRGB) ?? NSColor.black
```

### 2.6 Core Performance Fixes

#### 2.6.1 Move Buffer Polling Off MainActor [P3]
**File:** `RunwayStore.swift`
```swift
bufferDetectionTask = Task {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        // Capture what we need on MainActor
        let sessionsSnapshot = await MainActor.run { 
            sessions.filter { $0.status != .stopped }
        }
        // Do heavy work off-main
        let results = await detectStatuses(for: sessionsSnapshot)
        // Apply results on MainActor
        await MainActor.run { applyStatusUpdates(results) }
    }
}
```

#### 2.6.2 Add Timer Jitter [P7]
Add `Double.random(in: 0...2)` to each polling interval to prevent alignment.

#### 2.6.3 Fix rebuildFileTree [P8]
Replace `didSet` on `sessionChanges` with a targeted update method:
```swift
func updateChanges(for sessionID: String, changes: [FileChange]) {
    sessionChanges[sessionID] = changes
    sessionFileTree[sessionID] = buildFileTree(changes)
}
```

---

## Phase 3: v0.9.x — Polish, UX, and Features

**Goal:** Accessibility, UX consistency, and must-have features.
**Scope:** ~2500 LOC changed, ~35 files touched.
**Timeline target:** 8-12 sessions.

### 3.1 Accessibility Pass [U1] — HIGHEST UX PRIORITY
**Files:** All Views/*.swift
Systematic pass adding:
- `.accessibilityLabel()` to all interactive elements
- `.accessibilityElement(children: .combine)` to composite rows
- Priority targets: sidebar session rows, PR table rows, diff headers, all action buttons, sheet close buttons

### 3.2 UX Fixes

| ID | Fix | File | LOC |
|----|-----|------|-----|
| U2 | Add "Restart Session" button to error/stopped terminal view | `TerminalTabView.swift` | ~20 |
| U3 | Replace hardcoded system colors with `theme.chrome.*` | `ActivityLogView.swift`, `SettingsPlaceholder.swift` | ~15 |
| U6 | Pass session tool name to SendTextBar instead of "Claude" | `SendTextBar.swift`, `SessionDetailView.swift` | ~5 |
| U7 | Enhanced first-run empty state with two clear actions | `ContentView` in RunwayApp | ~30 |
| U8 | Extract shared `PRStateDot` into PRBadges.swift | `PRBadges.swift`, 3 consuming views | ~40 |
| U9 | Extract shared `TabBarView` component | New shared component + 4 consuming views | ~80 |
| U10 | Use `minWidth`/`idealWidth` on sheets instead of fixed `width` | All sheet views | ~20 |
| U11 | Consolidate sheet state into single enum | `RunwayApp.swift` or `ContentView` | ~40 |
| U12 | Make project header expand/collapse, move settings to context menu only | `ProjectTreeView.swift` | ~20 |
| U4 | Deep link to unknown PR: attempt fetch or show toast | `RunwayStore.swift` | ~15 |
| U5 | Disable send button or show toast when terminal unavailable | `SessionDetailView.swift` | ~10 |

### 3.3 Features

#### 3.3.1 Cost/Token Tracking [F1]
**Files:** `HookEvent.swift`, `Session.swift`, `Records.swift`, `Database.swift` (migration v15), `SessionHeaderView.swift`, `ProjectTreeView.swift`
1. Parse `total_cost_usd`, `input_tokens`, `output_tokens` from `Stop` hook event payload
2. Add `totalCost: Double?`, `inputTokens: Int?`, `outputTokens: Int?` to Session
3. Display per-session cost in sidebar row and session header
4. Add project-level cost rollup on project page

#### 3.3.2 Session Transcript Access [F2]
**Files:** `HookEvent.swift`, `Session.swift`, `SessionDetailView.swift`, new `TranscriptView.swift`
1. Persist `transcriptPath` from hook events on Session model
2. Add "Transcript" tab in session detail
3. Parse and render JSONL transcript (messages, tool calls)

#### 3.3.3 Session Housekeeping [F3]
**Files:** `Database.swift`, `RunwayStore.swift`, `SettingsPlaceholder.swift`
1. Add `cleanSessionEvents(maxAge:)`, `cleanStoppedSessions(maxAge:)` methods
2. Drop unused `todos` and `groups` tables in migration v16
3. Add "Clean Up" section in Settings with retention controls
4. Run `VACUUM` option

#### 3.3.4 First-Run Onboarding [F4]
**Files:** New `OnboardingView.swift`, `RunwayStore.swift`
1. `PrerequisiteChecker` validates tmux, git, gh availability
2. Welcome sheet on first launch with: prereq results, add project, quick session
3. Yellow banner for missing tools instead of toast

#### 3.3.5 Error Recovery [F5]
**Files:** `Session.swift`, `RunwayStore.swift`, `TerminalTabView.swift`
1. Add `lastError: String?` to Session model
2. "Retry" action on sessions with `.error` status
3. "Start Without Worktree" fallback button
4. Display error detail in session detail view

#### 3.3.6 Git Rollback [F6]
**Files:** New `CommitHistoryView.swift`, `WorktreeManager.swift`, `SessionDetailView.swift`
1. Add `commitLog(repoPath:branch:)` to WorktreeManager
2. "Commits" tab or section showing `git log --oneline` since branch divergence
3. "Rollback to this commit" with confirmation dialog
4. "Create checkpoint" action (tag or stash)

#### 3.3.7 Prompt Library [F7]
**Files:** New `PromptLibrary.swift`, `SendTextBar.swift`, `Database.swift`
1. Prompt model (name, text, projectID?)
2. DB table + CRUD in migration v17
3. Dropdown/palette on SendTextBar (Cmd+Shift+P or similar)
4. Built-in entries for `/commit`, `/pr`, common commands

#### 3.3.8 Batch Session Actions [F8]
**Files:** `ProjectTreeView.swift`, `RunwayStore.swift`
1. Multi-select in sidebar (Shift+click, Cmd+click)
2. Batch toolbar: "Restart All", "Stop All", "Delete All"
3. Simple iteration over existing methods

---

## Phase 4: v1.0.0 — Feature-Complete Release

**Goal:** Remaining test coverage, performance tuning, and final polish.
**Scope:** ~1000 LOC changed, ~20 files touched.
**Timeline target:** 3-5 sessions.

### 4.1 Test Coverage [WS7]

| Priority | Test | Target |
|----------|------|--------|
| 1 | `RunwayStore.deleteSession(deleteWorktree: true)` | Verify worktree + branch cleanup |
| 2 | Database migration upgrade path (v1 → v17) | Prevent data loss on updates |
| 3 | `TerminalSessionCache` LRU eviction | Validate process cleanup |
| 4 | `ShellRunner.run()` timeout + deadlock prevention | Continuation ordering |
| 5 | `RunwayStore.cleanOrphanedWorktrees()` | Protect unmerged branches |
| 6 | `PRManager.fetchPRs()` JSON parsing | Real `gh` output |
| 7 | HookServer → StatusDetector end-to-end | Event wiring |
| 8 | `RunwayStore.handleNewSessionRequest()` | Session lifecycle |
| 9 | `SyntaxHighlighter` | JSContext fragility |
| 10 | `RunwayStore.loadState()` session/tmux reconciliation | Stale state |

### 4.2 Performance Tuning

| ID | Fix | File |
|----|-----|------|
| P1 | Extract `PRCoordinator` from RunwayStore (~400 LOC) | New file + RunwayStore |
| P4 | Fix `async let` actor serialization in `fetchAllPRs` | `PRManager.swift` |
| P6 | Cache filtered PR arrays in PRDashboardView body | `PRDashboardView.swift` |
| P9 | Add cleanup to `deleteSession` for stale caches | `RunwayStore.swift` |
| P2 | Reduce `enrichPath` timeout to 1s, add loading splash | `ShellRunner.swift`, `RunwayApp.swift` |

### 4.3 Final Polish

| ID | Fix | File |
|----|-----|------|
| | Consolidate 3 `Color(hex:)` initializers | Theme module |
| | Fix `startSessionFromIssue` hardcoded `.claude` tool | `RunwayStore.swift` |
| | Remove stale `precondition(inMemory)` from Database | `Database.swift` |
| | Session event cap: single SQL DELETE instead of loop | `Database.swift` |
| | Add Equatable to Session, PullRequest, CheckSummary | Models |
| | DatabaseQueue → DatabasePool for concurrent reads | `Database.swift` |
| | Explicit `@MainActor` on poll Tasks | `RunwayStore.swift` |
| | `[weak self]` on bufferDetectionTask | `RunwayStore.swift` |

---

## Dependency Graph

```
Phase 1 (ship-stoppers)
  ├── C1 branch name ─────────────────────────────────────────────┐
  ├── C3 precondition ──── standalone                             │
  ├── C2 graphql ────────── standalone                            │
  ├── M8 hook handler ───── standalone                            │
  ├── M4 stale enrich ───── standalone                            │
  └── M3 partial results ── standalone                            │
                                                                  │
Phase 2 (reliability) ◄── depends on Phase 1 completing          │
  ├── WS2: Terminal ──────── C4, M5, M6, M13 (internal order)    │
  ├── WS3: HookServer ───── M8→M9→M10→M11 (sequential)          │
  ├── M1 ShellRunner timeout ── standalone                        │
  ├── M2 DB nil visibility ── standalone                          │
  ├── M12 NSColor ────────── standalone                           │
  └── P3, P7, P8 ────────── can parallel                         │
                                                                  │
Phase 3 (polish + features) ◄── depends on Phase 2               │
  ├── U1 accessibility ──── standalone (can start early)          │
  ├── U2 error recovery ─── depends on F5 (error model)          │
  ├── F1 cost tracking ──── depends on C1 (session model chg)  ◄─┘
  ├── F2 transcripts ────── standalone
  ├── F3 housekeeping ───── standalone
  ├── F4 onboarding ─────── standalone
  ├── F5 error retry ────── depends on Phase 2 terminal fixes
  ├── F6 git rollback ───── depends on C1 (branch name fix)
  ├── F7 prompt library ─── standalone
  └── F8 batch actions ──── standalone

Phase 4 (1.0) ◄── depends on Phase 3
  ├── WS7: Tests ─────────── depends on all code changes
  ├── P1 store split ─────── depends on all RunwayStore changes
  └── Final polish ────────── standalone items
```

## Execution Strategy

### Parallelizable Within Each Phase

**Phase 1:** All 6 items are independent — can be done in parallel or single session.

**Phase 2:** Three parallel tracks:
- Track A: Terminal/PTY fixes (2.1.x)
- Track B: HookServer fixes (2.2.x)  
- Track C: ShellRunner + DB + Performance (2.3-2.6)

**Phase 3:** Four parallel tracks:
- Track A: Accessibility pass (U1)
- Track B: UX fixes (U2-U12)
- Track C: Features F1-F4
- Track D: Features F5-F8

**Phase 4:** Two parallel tracks:
- Track A: Test coverage
- Track B: Performance tuning + polish

### Commit Strategy

Each numbered item gets its own atomic commit. Group into PRs by work stream:
- PR per phase (4 PRs total), or
- PR per work stream within phase (more granular review)

### Risk Mitigation

- **C1 (branch name)** touches the most code paths — test thoroughly with real worktrees
- **Phase 2 terminal fixes** are the riskiest — test with many concurrent sessions
- **P1 (store split)** is the largest refactor — defer to Phase 4 when all other changes are stable
- **Database migrations** — always test upgrade path from v0.8.0 database

---

## Metrics

| Metric | v0.8.0 | Target v1.0.0 |
|--------|--------|---------------|
| Critical bugs | 4 | 0 |
| Major bugs | ~20 | 0 |
| Test count | 292 | 350+ |
| RunwayStore LOC | 1708 | ~1200 (after coordinator extraction) |
| Accessibility labels | ~10 | ~200+ |
| VoiceOver usable | No | Yes |
| Force unwrap/precondition crash risks | 3 | 0 |
| Average PR fetch latency | ~800ms | ~400ms |
| View invalidation scope | Full tree | Scoped by coordinator |
