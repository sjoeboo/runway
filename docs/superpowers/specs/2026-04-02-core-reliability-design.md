# Core Reliability: Dynamic Hook Port & Auto-Detect Default Branch

**Date:** 2026-04-02
**Status:** Approved
**Scope:** Two targeted fixes to core reliability before tackling session persistence

---

## Item 1: Hook Server Dynamic Port

### Problem

HookServer binds to hardcoded port 47437. If the port is in use (another Runway instance, leftover listener, or any other process), the server fails silently and session status indicators stop updating. The TODO notes this as a likely cause of broken sidebar status.

### Approach

Bind to port 0 (OS-assigned ephemeral port). Read the actual port from `NWListener.port` once the listener enters `.ready` state. Pass the resolved port to `HookInjector` so Claude Code's settings.json gets the correct URL.

### Changes

**`Sources/StatusDetection/HookServer.swift`:**
- Change default `port` from `47437` to `0`
- Add `public var actualPort: UInt16?` property
- Make `start()` async — use `CheckedContinuation` to bridge NWListener's `stateUpdateHandler` callback, resolving when `.ready` (setting `actualPort`) or throwing on `.failed`
- Keep the explicit port parameter so tests or overrides can still pin a port

**`Sources/App/RunwayStore.swift`:**
- In `startHookServer()`: start server, then inject hooks with `hookServer.actualPort`
- Remove the standalone `Task { try? hookInjector.inject() }` from `init()` — hook injection moves into `startHookServer()` after the port is known
- If server fails to start, log error and skip injection (app still works, just no status indicators)

**No changes to `HookInjector`** — already accepts `port:` parameter.

### Error handling

Port 0 binding should never fail unless the system is out of ephemeral ports. If it does fail, the error is logged and hook injection is skipped. The app remains functional without status indicators.

---

## Item 2: Auto-Detect Default Branch in NewProjectDialog

### Problem

NewProjectDialog has a manual "Default Branch" text field defaulting to "main". The detection logic exists in `WorktreeManager.detectDefaultBranch()` but isn't used during project creation in the dialog. Users must manually type "master" for repos that use it.

### Approach

Auto-detect the default branch when the user selects or types a project path. Keep the field editable as an override.

### Changes

**`Sources/Views/Shared/NewProjectDialog.swift`:**
- Add `@State private var isDetectingBranch: Bool = false`
- Add `.onChange(of: path)` modifier that triggers detection with a short debounce
- Create a local `WorktreeManager()` instance (stateless actor, no need to couple to store)
- On path change: validate path is a git repo directory, then call `detectDefaultBranch(repoPath:)` in a background Task
- Set `defaultBranch` to the detected value; show a ProgressView spinner while detecting
- Field remains editable — detection is a convenience, not a lock

### Detection flow

1. User selects path via Browse (or types manually)
2. `.onChange(of: path)` fires
3. Validate: directory exists and contains `.git`
4. Set `isDetectingBranch = true`
5. Call `WorktreeManager().detectDefaultBranch(repoPath:)` (runs `git symbolic-ref` with fallback)
6. Set `defaultBranch` to result, `isDetectingBranch = false`

### Edge cases

- Path typed manually: debounce prevents spamming git on every keystroke
- Path not a git repo: skip detection, leave field as-is
- Detection fails: leave field at current value (default "main")
- User edits field after detection: their edit wins (no re-detection unless path changes again)

---

## Out of Scope

- **Session persistence** — separate design, to be tackled after these two items
- **Hook server authentication** — not needed for localhost-only communication
- **Multiple Runway instances** — each gets its own port and injects its own hooks; last-writer-wins on settings.json is acceptable for now
