# Session Persistence via tmux

**Date:** 2026-04-03
**Status:** Approved
**Scope:** Make terminal sessions survive navigation and app restarts using tmux as the process lifecycle manager

---

## Problem

1. **Navigation bug:** TerminalSessionCache exists but sessions die when navigating away and back, losing all work
2. **App restart:** PTY processes die when the app exits — no way to resume a running Claude session

## Approach

Use tmux as an invisible process lifecycle manager. Runway creates detached tmux sessions for each terminal, and SwiftTerm attaches to them via `tmux attach-session`. tmux keeps processes alive independently of the app.

This fixes both problems: reattaching to a tmux session restores full terminal state whether the view was destroyed by SwiftUI navigation or by an app restart.

## Architecture

### TmuxSessionManager (new)

**File:** `Sources/Terminal/TmuxSessionManager.swift`

Stateless actor wrapping tmux CLI operations.

**API:**
- `isAvailable() -> Bool` — checks tmux is installed
- `createSession(name:, workDir:, command:, env:)` — `tmux new-session -d -s {name} -c {workdir}`, then sends initial command and sets environment variables
- `sessionExists(name:) -> Bool` — `tmux has-session -t {name}`
- `listSessions() -> [TmuxSession]` — `tmux list-sessions` filtered to `runway-*` prefix
- `killSession(name:)` — `tmux kill-session -t {name}`
- `attachCommand(name:) -> (executable: String, args: [String])` — returns `("/usr/bin/tmux", ["attach-session", "-t", name])`

**Naming convention:** `runway-{sessionID}` for main terminals, `runway-{sessionID}-shell{N}` for additional shell tabs.

**Environment:** Uses `tmux set-environment` to pass `RUNWAY_SESSION_ID`, `RUNWAY_TITLE`, and hook-related env vars into the tmux session.

### TerminalPane Changes

**File:** `Sources/TerminalView/TerminalPane.swift`

`createTerminal()` changes from spawning a raw shell to spawning `tmux attach-session`:

- When `config.tmuxSessionName` is set: `startProcess(executable: "/usr/bin/tmux", args: ["attach-session", "-t", name])`
- When nil (fallback): current direct-spawn behavior preserved

No more `cd /path && command\r` text injection — tmux session is pre-configured with the correct working directory and command.

### TerminalConfig Changes

**File:** `Sources/TerminalView/TerminalPane.swift` (TerminalConfig struct)

Add optional field:
- `tmuxSessionName: String?` — when present, TerminalPane attaches to tmux instead of spawning directly

### Session Creation Flow

**File:** `Sources/App/RunwayStore.swift`

`handleNewSessionRequest()` changes:
1. Create Session model, save to DB (unchanged)
2. **New:** Call `tmuxManager.createSession()` with the session's command, workdir, and env
3. Set the tmux session name on the terminal config
4. UI renders TerminalPane which attaches to the tmux session

### Startup Reconciliation

**File:** `Sources/App/RunwayStore.swift`

`loadState()` gains a reconciliation step after loading from DB:
1. Call `tmuxManager.listSessions()` to get live `runway-*` sessions
2. For each DB session with status not `.stopped`:
   - Matching tmux session alive → set status to `.idle`
   - No matching tmux session → set status to `.stopped`
3. Orphaned tmux sessions (no DB record) → `tmuxManager.killSession()` to clean up

### Session Deletion

`deleteSession()` now also calls `tmuxManager.killSession()` to clean up the tmux process.

### Shell Tabs

`TerminalTabView.addShellTab()` creates a new tmux session (`runway-{id}-shell{N}`) and the TerminalPane attaches to it. `closeTab()` kills the corresponding tmux session.

### tmux Availability

On launch, check `tmuxManager.isAvailable()`. If missing:
- Show a one-time alert: "Runway works best with tmux installed. Without it, sessions won't persist across app restarts. Install with: brew install tmux"
- Fall back to direct-spawn (current behavior) — app remains functional, just without persistence
- The `tmuxSessionName` field being nil triggers the fallback path

## Edge Cases

- **tmux not installed:** Graceful fallback to direct-spawn, with user notification
- **tmux session creation fails:** Fall back to direct-spawn for that session, log error
- **Orphaned tmux sessions:** Cleaned up on startup reconciliation
- **Multiple Runway instances:** Each has unique session IDs, tmux sessions don't conflict
- **User's own tmux sessions:** `runway-` prefix ensures we never touch them

## Out of Scope

- tmux configuration customization (we use sensible defaults)
- Terminal scrollback persistence to disk (tmux handles in-memory scrollback)
- Session forking/cloning
- Custom tmux key bindings (we attach in raw mode, SwiftTerm handles input)
