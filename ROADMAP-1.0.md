# Runway 1.0 Roadmap

> 10-agent audit of v0.8.0 (April 2026) identified 130+ findings.
> Phases 1-3 completed in a single session. This document tracks remaining work.

## Completed Work (v0.8.0 → v0.9.0)

**4 commits, 36 files changed, +2013/-308 lines, 293 → 312 tests**

### Phase 1: Ship-Stoppers — DONE
- [x] C1: Branch name sanitization (preserves `/` in git branches, sanitizes directory only)
- [x] C2: GraphQL injection prevention (nodeID validation)
- [x] C3: TerminalPalette precondition → defensive pad/truncate
- [x] M3: fetchAllPRs partial results (one filter failure doesn't discard the other)
- [x] M4: Task.isCancelled guard in enrichPRs
- [x] M8: Hook handler registered before server start

### Phase 2: Reliability — DONE
- [x] C4: Cache eviction terminates PTY attach processes
- [x] M1: ShellRunner 30s subprocess timeout
- [x] M2: databaseFailed persistent flag
- [x] M5: PTY write/resize FD race fix (atomic lock)
- [x] M6: Zombie process reap in PTYProcess.deinit
- [x] M9: HookServer 30s connection timeout
- [x] M10: HookServer auto-restart on failure
- [x] M11: Port file cleanup on app quit
- [x] M12: NSColor deviceRGB crash fix
- [x] M13: Mouse restore re-resolves from firstResponder
- [x] P3: Buffer polling with [weak self] + jitter
- [x] P5: Terminal search row-by-row (no 6MB allocation)
- [x] P6: PR dashboard tab counts computed once
- [x] P7: All polling timers have jitter
- [x] P8: Targeted per-session file tree rebuild
- [x] P9: Stale cache cleanup on session delete + explicit @MainActor on poll tasks

### Phase 3: UX + Features — DONE
- [x] U2: Restart button + error detail on stopped/error terminal view
- [x] U3: Theme colors in ActivityLogView + Settings
- [x] U4: Deep link to unknown PR shows toast
- [x] U5: Deep link to deleted session shows toast
- [x] U6: SendTextBar shows tool name with prompt library dropdown
- [x] U7: Enhanced first-run empty state
- [x] U8: Shared PRStateDot component
- [x] F1: Cost/token tracking (model + migration + header badge + hook capture)
- [x] F2: Transcript viewer (TranscriptView.swift + tab button)
- [x] F3: Session housekeeping (cleanup methods + Settings Maintenance tab + VACUUM)
- [x] F4: Prerequisite checking (tmux/gh detection at startup)
- [x] F5: Error recovery (lastError field + error display + restart button)
- [x] F6: Git rollback backend (commitLog + resetToCommit on WorktreeManager)
- [x] F7: Prompt library (SavedPrompt model + DB + tool-specific slash commands)
- [x] F8: Batch actions (stop all, delete stopped + sidebar menu + menu bar)
- [x] Dead code: TerminalKeyEventMonitor removed
- [x] Session Equatable conformance
- [x] Event cap: single SQL DELETE
- [x] Legacy tables dropped (todos, groups, metadata)

---

## Remaining Work for v1.0.0

### High Priority

#### P1: Extract PRCoordinator from RunwayStore
**Impact:** Biggest remaining performance win — reduces @Observable view invalidation scope.
**Scope:** ~400 LOC moved to new file, ~200 LOC of glue changes in RunwayStore + RunwayApp.
**Risk:** Large refactor — do on clean baseline.
**What to extract:**
- `pullRequests`, `selectedPRID`, `prDetail`, `prTab`, `prLastFetched`, `isLoadingPRs`
- `enrichPRsTask`, `lastPRFingerprint`, `prPollTask`, `sessionPRPollTask`
- `detailCache`, `detailTTL`, `sessionPRs`, `sessionPRFetchedAt`
- Methods: `fetchPRs`, `enrichPRs`, `linkSessionPRs`, `freshenSessionPRs`, `selectPR`, `startPRPoll`, `startSessionPRPoll`
- `loadCachedPRs`, `refreshPRsIfStale`, `reEnrichPR`, `applyEnrichment`

#### U1: VoiceOver Accessibility Pass
**Impact:** Required for 1.0 — app is essentially unusable with VoiceOver.
**Scope:** ~25 view files need `.accessibilityLabel()` added.
**Already done:** SendTextBar, sidebar search/clear/action buttons, PRDetailDrawer close, IssueDetailDrawer close, PRBadges (already had labels), ResizableDivider (already had labels).
**Still needs labels:**
- DiffView (file headers, line numbers)
- ChangesSidebarView (file entries)
- FileTreeView (file status)
- PRDashboardView (table cells, action buttons)
- PRFilterBar (filter toggles)
- NewSessionDialog (form fields)
- NewProjectDialog (form fields)
- NewIssueSheet, EditIssueSheet, ManageLabelsSheet, ManageAssigneesSheet
- ProjectPageView (tab bar)
- SessionHeaderView (cost badge, tool badge, PR number)

#### Remaining Tests (5 from QA2's top 10) — DONE
Tests already added: migration safety, cost tracking, housekeeping, saved prompts, branch sanitization, worktree with slashes, HookEvent cost fields, Session Equatable.
**Added (17 tests across 4 files):**
1. [x] `deleteSession(deleteWorktree: true)` — removeWorktree protects unmerged branches via `-d`, deletes merged
2. [x] `TerminalSessionCache` LRU eviction — eviction order, refresh on access, removal, get-or-create identity
3. [x] `ShellRunner.run()` timeout — SIGTERM on timeout, success within timeout, non-zero exit handling
4. [x] `cleanOrphanedWorktrees()` — full list→identify→merge-check→remove flow, owned preserved, unmerged preserved
5. [x] HookServer → handler e2e — full JSON decode with header override + cost fields, without header
**Bug fixed:** `isBranchMerged` didn't strip `+ ` prefix from `git branch --merged` output (worktree checkout marker)

### Medium Priority

#### F6 UI: Git Rollback View
Backend exists (`commitLog`, `resetToCommit` on WorktreeManager). Needs:
- `CommitHistoryView.swift` showing commit list for the session's worktree branch
- Rollback button with confirmation dialog
- Integration into session detail (button or tab)

#### U9: Unified Tab Bar Component
4 different tab bar patterns exist (dashboard, project page, PR detail, issue detail). Extract shared `TabBarView`.

#### U10: Adaptive Sheet Widths
~10 sheets use hardcoded `frame(width:)`. Switch to `minWidth`/`idealWidth`/`maxWidth`.

#### U11: Consolidate Sheet Booleans
4 independent sheet booleans (`showNewSessionDialog`, `showNewProjectDialog`, `showReviewPRSheet`, `showReviewPRDialog`) → single `ActiveSheet` enum.

### Low Priority

| Item | File | Notes |
|------|------|-------|
| DatabaseQueue → DatabasePool | Database.swift | Concurrent reads during writes |
| Consolidate 3 Color(hex:) initializers | Theme module | Dedup |
| startSessionFromIssue hardcoded .claude | RunwayStore.swift | Use project default tool when available |
| P4: async let actor serialization | PRManager.swift | Needs nonisolated helper methods |
| P2: Reduce enrichPath timeout to 1s | ShellRunner.swift | Minor launch time improvement |
| [weak self] on bufferDetectionTask | RunwayStore.swift | Consistency (already has jitter) |
| PullRequest + CheckSummary Equatable | Models | Optimize SwiftUI diffing |
| Remove precondition(inMemory) from Database test init | Database.swift | Replace with throwing |
| HookServer stop() cancel in-flight connections | HookServer.swift | Track + cancel active connections |
| Orphaned Task tracking | RunwayStore.swift | Store provisioning Tasks, cancel on delete |

---

## Metrics

| Metric | v0.8.0 | Current (v0.9.0) | Target v1.0.0 |
|--------|--------|-------------------|---------------|
| Critical bugs | 4 | **0** | 0 |
| Major bugs | ~20 | **~2** | 0 |
| Test count | 292 | **329** | 340+ |
| DB migrations | 14 | **17** | 17+ |
| Features added | — | **8 new** | — |
| RunwayStore LOC | 1708 | ~1850 | ~1200 (after P1) |
| Accessibility labels | ~10 | **~25** | 200+ |
| Force unwrap/precondition crash risks | 3 | **0** | 0 |
