# Runway 1.0.0 Pre-Release Bug Hunt Report

**Date**: 2026-04-09
**Audited by**: 8 parallel subagents (2 Swift experts, 2 macOS design experts, 2 terminal/tmux experts, 2 general bug hunters)
**Scope**: Full codebase — all 11 SPM targets

## Executive Summary

| Severity | Count | Confidence |
|----------|-------|------------|
| Critical | 6 | Multi-agent corroboration on top findings |
| High | 10 | Strong evidence, clear impact |
| Medium | 16 | Real bugs with limited blast radius |
| Low | 15 | Edge cases, polish, minor UX |
| **Total** | **47** | Deduplicated from ~95 raw findings |

The most impactful cluster is in **StatusDetection** — the ANSI stripping state machine has 3 distinct bugs that compound to make buffer-based status detection unreliable, and the cache key mismatch means it was never actually working. The second cluster is in **process lifecycle** — ShellRunner and PTYProcess both have race conditions around process termination that can hang or crash the app.

---

## Critical (6)

### C1. TerminalSessionCache key mismatch — buffer detection and SendTextBar silently broken
**Found by**: 4/8 agents | **Confidence**: Very High

- **Files**: `Sources/TerminalView/TerminalSessionCache.swift:76`, `Sources/Views/SessionDetail/TerminalTabView.swift:245`
- **Description**: `mainTerminal(forSessionID:)` looks up key `"{id}_{id}_main"` but the actual cache key is `"{id}_{id}_main_{restartTrigger}"`. Even with trigger=0, the stored key is `"X_X_main_0"` while lookup expects `"X_X_main"`. These **never match**.
- **Impact**: Two features are completely non-functional:
  1. **SendTextBar** (Cmd+Shift+X) silently drops all user input
  2. **Buffer-based status polling** always returns nil — the entire fallback detection path is dead code
- **Fix**: Remove `_\(terminalRestartTrigger)` from the main tab ID, or change `mainTerminal` to use prefix matching

### C2. ShellRunner continuation race — process can hang indefinitely
**Found by**: 3/8 agents | **Confidence**: Very High

- **File**: `Sources/Models/ShellRunner.swift:101-119`
- **Description**: `terminationHandler` is set *after* `process.run()`. If the process terminates before the handler is assigned (common for instant failures like bad path, missing tool), the continuation is never resumed. The calling Task hangs forever.
- **Impact**: Any `gh`, `git`, or `tmux` command that exits instantly can permanently deadlock the calling actor (`PRManager`, `WorktreeManager`, or `TmuxSessionManager`), freezing all operations in that subsystem.
- **Fix**: Set `terminationHandler` before calling `process.run()`

### C3. HookServer continuation never resumed on `.cancelled` — app hangs on startup
**Found by**: 2/8 agents | **Confidence**: High

- **File**: `Sources/StatusDetection/HookServer.swift:62-76`
- **Description**: The NWListener `stateUpdateHandler` only handles `.ready` and `.failed`. If the listener transitions to `.cancelled` (e.g., concurrent `stop()` call), the `CheckedContinuation` is never resumed. Debug builds crash with "leaked continuation"; release builds hang indefinitely.
- **Impact**: Hook server initialization permanently hangs, blocking hook injection and all hook-based status detection
- **Fix**: Handle `.cancelled` state by resuming the continuation with an error

### C4. No hook cleanup on app termination — 5-second agent delays after quit
**Found by**: 1/8 agents | **Confidence**: High

- **Files**: `Sources/App/RunwayStore.swift` (no termination handler), `Sources/App/RunwayApp.swift` (no lifecycle handling)
- **Description**: When Runway quits, injected hooks remain in `~/.claude/settings.json` (and gemini/codex configs) pointing at the dead port. There is no `NSApplication.willTerminate` handler to remove them.
- **Impact**: Every Claude Code hook event (SessionStart, UserPromptSubmit, PermissionRequest, etc.) blocks for up to 5 seconds hitting the dead port. This persists until Runway is relaunched. Affects **every user** between app restarts.
- **Fix**: Add an `NSApplication.willTerminate` observer that calls `hookInjector.remove(config:)` for each config

### C5. PTYProcess missing `deinit` — dispatch source deallocation crash
**Found by**: 1/8 agents | **Confidence**: High

- **File**: `Sources/Terminal/PTYProcess.swift` (entire class, no deinit)
- **Description**: `readSource` and `processSource` (DispatchSources) are resumed but never cancelled if the PTYProcess is simply deallocated without calling `terminate()`. Deallocating a resumed, non-cancelled DispatchSource is undefined behavior and crashes the process.
- **Impact**: App crash if any code path releases a PTYProcess reference without first calling terminate(). Currently PTYProcess is not used in production (NativePTY uses tmux), but it's compiled public API.
- **Fix**: Add `deinit { handleExit() }` to cancel dispatch sources before deallocation

### C6. PTYProcess treats EAGAIN as EOF — spurious session termination
**Found by**: 1/8 agents | **Confidence**: High

- **File**: `Sources/Terminal/PTYProcess.swift:126-132`
- **Description**: The read handler treats all `bytesRead <= 0` identically. When `read()` returns -1 with `errno == EAGAIN` (spurious dispatch source wakeup), the code calls `handleExit()`, tearing down the entire PTY session.
- **Impact**: Under memory pressure or kernel scheduling, a spurious wakeup kills the user's terminal session for no apparent reason
- **Fix**: Check `errno` and only call `handleExit()` for true EOF (bytesRead == 0) or real errors (not EAGAIN/EINTR)

---

## High (10)

### H1. ANSI stripper: OSC String Terminator (ESC \) not handled — text consumed after OSC sequences
**Found by**: 1/8 agents

- **File**: `Sources/StatusDetection/StatusDetector.swift:116-124`
- **Description**: After an OSC sequence, the ST terminator (ESC + `\`) causes the state machine to enter `.escSeen` then fall through to `.inCSI` mode, consuming all subsequent real text until a letter is found
- **Impact**: Terminal title-setting sequences (`ESC]0;title ESC\`) corrupt the stripped output, causing missed status transitions
- **Fix**: Handle `\` in `.escSeen` state as ST terminator, transition back to `.normal`

### H2. ANSI stripper: CSI terminator misses valid final bytes (@, `, etc.)
**Found by**: 4/8 agents

- **File**: `Sources/StatusDetection/StatusDetector.swift:113`
- **Description**: CSI final bytes per ECMA-48 are 0x40-0x7E, but only letters and `~` are checked. Characters like `@` (Insert Character), `` ` `` (HPA) cause the parser to stay in CSI mode, eating real text
- **Impact**: CSI sequences with non-letter terminators leave the parser stuck, corrupting status detection input
- **Fix**: Replace ad-hoc checks with `scalar.value >= 0x40 && scalar.value <= 0x7E`

### H3. PR detail drawer cannot be closed in ProjectPRsTab
**Found by**: 2/8 agents

- **File**: `Sources/Views/ProjectPage/ProjectPRsTab.swift:115`
- **Description**: The `onClose` handler is `{ onSelectPR(pr) }` — this re-selects the current PR instead of deselecting. Compare with `PRDashboardView` which correctly passes `nil`
- **Impact**: Users cannot close the PR detail drawer on the project page. The X button does nothing.
- **Fix**: Change to pass a deselection callback (requires making the callback accept `PullRequest?`)

### H4. deleteSession force-deletes unmerged branches without warning
**Found by**: 3/8 agents

- **Files**: `Sources/App/RunwayStore.swift:606`, `Sources/GitOperations/WorktreeManager.swift:124-130`
- **Description**: `removeWorktree` unconditionally uses `git branch -D` (force delete). The orphan cleanup logic correctly checks `isBranchMerged` first, but explicit session deletion does not.
- **Impact**: Users permanently lose unmerged commits when deleting a session with worktree cleanup. No confirmation, no recovery.
- **Fix**: Check `isBranchMerged` before deleting, or use `git branch -d` (safe delete), or add a confirmation dialog

### H5. handleReviewPR continues after worktree failure — review runs on wrong branch
**Found by**: 2/8 agents

- **File**: `Sources/App/RunwayStore.swift:1503-1524`
- **Description**: If worktree checkout fails, the error is caught and shown, but execution continues. The session starts with `sessionPath = project.path` (the main repo, not a worktree). Compare with `handleNewSessionRequest` which correctly sets `.error` and returns.
- **Impact**: The agent reviews code on whatever branch the main repo is on, not the PR branch. The user gets misleading review feedback.
- **Fix**: Set session to `.error` status and return early, matching `handleNewSessionRequest` behavior

### H6. Database nil silently swallows all writes — complete data loss scenario
**Found by**: 2/8 agents

- **File**: `Sources/App/RunwayStore.swift:132-142, 109`
- **Description**: If the database fails to open, `database` is nil. All 30+ call sites use `try? database?.` which silently becomes a no-op. The user sees the app working but nothing persists.
- **Impact**: All sessions, project changes, and templates are lost on next app launch. The one-time error toast is easily missed.
- **Fix**: Show a persistent error banner, disable session creation, or retry database opening

### H7. PR conversation tab shows inline comments twice
**Found by**: 2/8 agents

- **File**: `Sources/Views/PRDashboard/PRDetailDrawer.swift:631-678`
- **Description**: Inline comments (with `path != nil`) are rendered in a dedicated "Inline Comments" section, then included again in the timeline (line 667 doesn't filter them out)
- **Impact**: Every inline review comment is duplicated, cluttering the conversation view
- **Fix**: Filter timeline: `comments.filter { $0.path == nil }.map { .comment($0) }`

### H8. PR detail drawer tab shortcuts displayed but not functional
**Found by**: 2/8 agents

- **File**: `Sources/Views/PRDashboard/PRDetailDrawer.swift:369-397`
- **Description**: Tab bar shows `^1`, `^2`, `^3`, `^4` hints but no `.keyboardShortcut()` modifier is attached. `IssueDetailDrawer` has them correctly.
- **Impact**: Broken affordance — users see shortcuts that don't work
- **Fix**: Add `.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)`

### H9. HookServer connection leak on teardown
**Found by**: 1/8 agents

- **File**: `Sources/StatusDetection/HookServer.swift:101-141`
- **Description**: `accumulateRequest` uses `[weak self]`. If the HookServer actor is deallocated while a connection is mid-accumulation, `self` becomes nil but the NWConnection is never cancelled, leaking resources.
- **Impact**: During rapid hook server restarts (port fallback), in-flight connections leak file descriptors
- **Fix**: Add `guard let self else { connection.cancel(); return }` at the start

### H10. Status detection pattern overlap — idle sessions shown as waiting
**Found by**: 1/8 agents

- **File**: `Sources/Models/AgentProfile.swift:110, 116`
- **Description**: `waitingPatterns` includes `"What would you like"` which is a substring of `idlePatterns` entry `"What would you like to do"`. Waiting patterns are checked first, so idle sessions get misclassified.
- **Impact**: Spurious notifications, inflated dock badge count, sessions shown as needing attention when idle
- **Fix**: Use more specific waiting pattern like `"What would you like to change"`, or check idle patterns first

---

## Medium (16)

### M1. HookServer blocks actor for handler dispatch before HTTP response
- **File**: `Sources/StatusDetection/HookServer.swift:143-166`
- Could cause Claude Code hook timeouts (5s) during heavy UI work
- **Fix**: Send 200 OK before dispatching to handlers

### M2. deleteProject fires concurrent worktree removals that race on git locks
- **File**: `Sources/App/RunwayStore.swift:668-677`
- Fire-and-forget Tasks for each session cause concurrent `git worktree remove` calls that fail
- **Fix**: Remove worktrees serially, or batch cleanup after DB operations

### M3. loadCachedPRs called twice during init — overwrites fresh data with stale cache
- **File**: `Sources/App/RunwayStore.swift:166, 248`
- Second call after `fetchPRs()` overwrites fresh data with older cache
- **Fix**: Remove the second `loadCachedPRs()` call at line 248

### M4. Concurrent enrichPRs and fetchPRs can overwrite each other's data
- **File**: `Sources/App/RunwayStore.swift:985, 1032-1037`
- Enrichment from previous cycle can overwrite newer fetch results
- **Fix**: Cancel in-flight enrichment when starting new fetch, or use generation counter

### M5. DiffView multi-file: all files start collapsed with no visible content
- **File**: `Sources/Views/Shared/DiffView.swift:13, 55`
- User sees only file headers, must manually expand each file
- **Fix**: Initialize `expandedFiles` with all paths, or auto-expand for small diffs

### M6. CheckRun uses `name` as Identifiable `id` — duplicates in CI matrix builds
- **File**: `Sources/Models/PullRequest.swift:168-180`
- Matrix builds produce multiple runs with the same name, causing SwiftUI rendering issues
- **Fix**: Use a unique ID (combination of name + status, or UUID suffix)

### M7. Diff parser drops empty lines from patches
- **File**: `Sources/Views/PRDashboard/PRDetailDrawer.swift:567-606`, `Sources/Views/Shared/DiffView.swift:186-233`
- Empty context lines without leading space fall through all conditions
- **Fix**: Add else clause treating unrecognized lines as context

### M8. sanitizeBranchName can produce collisions for similar session titles
- **File**: `Sources/GitOperations/WorktreeManager.swift:229-245`
- `"Feature/My Branch"` and `"feature-my-branch"` sanitize to the same name
- **Fix**: Append short unique suffix from session ID

### M9. flock() return value not checked — lock may not be acquired
- **File**: `Sources/StatusDetection/HookInjector.swift:296-305`
- Found by 3/8 agents. Lock failure falls through to unprotected execution
- **Fix**: Check return value, log warning or retry

### M10. Collapsed directory node uses incorrect fullPath in buildFileTree
- **File**: `Sources/Models/FileChange.swift:114`
- Collapsed chain's `fullPath` only has first level, causing potential SwiftUI identity conflicts
- **Fix**: Set `fullPath` to the child's full collapsed path

### M11. Hex color parser wrong for 3-digit CSS-style hex notation
- **File**: `Sources/Theme/ThemeFile.swift:75-80`
- `"F00"` (red shorthand) parses as `r=0, g=15, b=0` — completely wrong
- **Fix**: Detect 3/4-digit hex and expand before parsing

### M12. CheckForUpdatesViewModel recreated on every view rebuild
- **File**: `Sources/App/UpdaterController.swift:44-51`
- `@ObservedObject` in init doesn't own lifecycle; creates/destroys Combine subscription per menu open
- **Fix**: Change to `@StateObject` or `@State` + `@Observable`

### M13. Search buttons disabled after editing text following "not found"
- **File**: `Sources/TerminalView/TerminalSearchBar.swift:57-61`
- `searchState` stays `.notFound` when text changes, disabling buttons
- **Fix**: Reset `searchState` to `.idle` on any text change

### M14. Search highlights persist when search bar hidden via Cmd+F toggle
- **File**: `Sources/TerminalView/TerminalSearchBar.swift:120-125`
- Cmd+F toggle bypasses `dismiss()` which calls `clearSearch()`
- **Fix**: Add `onDisappear` that clears search, or route Cmd+F through dismiss

### M15. Settings window missing `.theme()` environment modifier
- **File**: `Sources/App/RunwayApp.swift:92-95`
- Settings may show light/dark mode mismatch with main window
- **Fix**: Add `.theme(store.themeManager.currentTheme)` and `.preferredColorScheme()`

### M16. enrichPath() blocks main thread with synchronous waitUntilExit()
- **File**: `Sources/Models/ShellRunner.swift:49`
- Called from `RunwayApp.init()`, blocks app launch if shell config is slow
- **Fix**: Add timeout (3s) and fallback to hardcoded paths, or run async

---

## Low (15)

### L1. ResizableDivider cursor push/pop imbalance on rapid hover
- `Sources/Views/Shared/ResizableDivider.swift:20-26` — Resize cursor can "stick"

### L2. ProjectPageView editableProject can become stale while settings sheet is open
- `Sources/Views/ProjectPage/ProjectPageView.swift:57, 246-261` — External changes overwrite unsaved edits

### L3. ProjectSettingsSheet fixed height may clip with many templates
- `Sources/Views/Settings/ProjectSettingsSheet.swift:169` — Use `minHeight` instead of fixed height

### L4. SettingsView font picker recomputes grouped fonts on every render
- `Sources/Views/Settings/SettingsPlaceholder.swift:122` — Cache in `@State` or compute in `onAppear`

### L5. NewIssueSheet allows whitespace-only titles
- `Sources/Views/ProjectPage/NewIssueSheet.swift:185-190` — Trim title before `onCreate`

### L6. PRDashboardView onAppear calls onRefresh unconditionally
- `Sources/Views/PRDashboard/PRDashboardView.swift:305` — Unnecessary fetch on every tab switch

### L7. requestChangesText/sheetCommentText not cleared on sheet cancel
- `Sources/Views/PRDashboard/PRDetailDrawer.swift:217, 239` — Old text reappears on reopen

### L8. PRReview with nil submittedAt sorts to beginning of timeline
- `Sources/Views/PRDashboard/PRDetailDrawer.swift:621-622` — Use `Date()` instead of `.distantPast`

### L9. Issue comment submission shows no success feedback
- `Sources/App/RunwayStore.swift:1406-1413` — Other actions show toasts, this one doesn't

### L10. IssueDetailDrawer Ctrl+N shortcuts are global, not scoped to drawer
- `Sources/Views/ProjectPage/IssueDetailDrawer.swift:247` — Fire from anywhere in the app

### L11. Shared `hideDrafts` AppStorage key creates cross-context coupling
- `Sources/Views/PRDashboard/PRDashboardView.swift:27` — Global and per-project toggle linked

### L12. Status toast auto-dismiss can clear a newer identical message
- `Sources/App/RunwayApp.swift:226-233` — Duplicate success messages silently dropped

### L13. ThemeManager selectedThemeID not updated during system auto-switch
- `Sources/Theme/ThemeManager.swift:50-76` — Checkmark on wrong theme in settings

### L14. Accessibility: sidebar action buttons hidden from VoiceOver when not hovered
- `Sources/Views/Sidebar/ProjectTreeView.swift:474-475` — `allowsHitTesting(false)` removes from a11y tree

### L15. Accessibility: ProjectSection chevron uses onTapGesture instead of Button
- `Sources/Views/Sidebar/ProjectTreeView.swift:219-229` — Not keyboard/VoiceOver accessible

---

## Additional Notes (not bugs, but worth tracking)

These were flagged by agents but are either currently unreachable code, informational, or extremely unlikely:

| Item | Notes |
|------|-------|
| **GhosttyVTTerminal leaks renderState** | Excluded from build, only matters when ghostty is enabled |
| **TerminalKeyEventMonitor is dead code** | Never started — may indicate missing keyboard event forwarding |
| **PTYProcess EOF/processSource race** | Zombie processes if read source fires before process exits |
| **PTYProcess PID reuse on SIGKILL** | Extremely unlikely but theoretically possible |
| **GraphQL variable interpolation in toggleDraft** | GitHub node IDs don't contain quotes in practice |
| **gh auth status parsing on old CLI** | Only affects pre-2.40 gh versions |
| **HookInjector TOML prefix matching** | Could match `codex_hooks_v2` when looking for `codex_hooks` |
| **Multiple windows share mutable singleton state** | App is single-window by intent but doesn't enforce it |
| **baseBranch unnecessarily sanitized** | Works due to fallback but adds latency |
| **Database v3 migration drop/rename window** | GRDB wraps in transaction, safe in practice |
| **Temp file accumulation from image drag-and-drop** | macOS cleans temp dir periodically |

---

## Recommended Priority for GitHub Issues

### Must-fix for 1.0.0
1. **C1** — TerminalSessionCache key mismatch (SendTextBar + buffer detection broken)
2. **C2** — ShellRunner continuation race (can deadlock any actor)
3. **C4** — No hook cleanup on quit (affects every user between restarts)
4. **H1+H2** — ANSI stripping bugs (3 issues, fix together — status detection unreliable)
5. **H3** — PR detail drawer can't close in project page
6. **H5** — PR review on wrong branch after worktree failure
7. **H10** — Status pattern overlap (idle shown as waiting)

### Should-fix for 1.0.0
8. **C3** — HookServer continuation on .cancelled
9. **H4** — Force-delete unmerged branches
10. **H6** — Database nil data loss scenario
11. **H7** — Duplicate PR comments
12. **H8** — PR drawer tab shortcuts broken
13. **M1** — HookServer response before dispatch
14. **M5** — DiffView files start collapsed
15. **M13** — Search buttons disabled after failed search
16. **M16** — enrichPath blocks main thread

### Nice-to-have for 1.0.0
17. **M3** — loadCachedPRs double-call
18. **M6** — CheckRun duplicate IDs
19. **M9** — flock return value
20. **M11** — Hex color parser
21. **L14+L15** — Accessibility issues
