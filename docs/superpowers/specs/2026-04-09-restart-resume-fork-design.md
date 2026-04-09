# Restart Resume, Fork Session, and Happy Indicator

**Date**: 2026-04-09
**Status**: Approved
**Branch**: `feature-restart-resume`

## Overview

Three related enhancements to Runway's session management:

1. **Restart as Resume**: The restart button resumes the previous agent conversation (via `--continue`/`--resume` flags) instead of starting a fresh session.
2. **Fork Session**: Create a new worktree from an existing session's branch, launching a fresh agent conversation with all code changes carried over.
3. **Happy Indicator**: Visual indicator in sidebar and header when a session uses the Happy mobile wrapper, honored when forking and resuming.

## Data Model Changes

### AgentProfile — New Field

Add `resumeArguments: [String]` to `AgentProfile`:

| Profile | `resumeArguments` |
|---------|-------------------|
| Claude  | `["--continue"]`  |
| Gemini  | `["--resume"]`    |
| Codex   | `["--continue"]`  |
| Shell   | `[]`              |

This field is decoded from custom profile JSON files in `~/.runway/agents/`, so user-defined agents can specify their own resume flags. Defaults to `[]` if omitted.

### NewSessionRequest — New Field

Add `baseBranch: String?` to `NewSessionRequest`. When non-nil, the worktree is created from this branch instead of the project's default base branch. Used by the fork flow to branch from the source session's worktree branch.

### Session Model — No Changes

`parentID` already exists for fork relationships. `useHappy` already exists for the Happy toggle. No database migration needed.

## Restart as Resume

### Current Behavior

`restartSession(id:)` in `RunwayStore`:
1. Kills tmux session + shell tabs
2. Clears terminal cache
3. Recreates tmux session with `profile.command + profile.arguments + permissionFlags`
4. Bug: ignores `session.useHappy` — restart drops the Happy wrapper

### New Behavior

1. Kill tmux session + shell tabs (unchanged)
2. Clear terminal cache (unchanged)
3. Recreate tmux session with resume arguments included

Command construction:

```
[happy?] + profile.command + profile.arguments + profile.resumeArguments + permissionFlags
```

Examples:
- Claude + Happy: `happy claude --continue --accept-edits`
- Gemini: `gemini --resume`
- Codex: `codex --no-alt-screen --continue`
- Shell: `(default shell, no resume)`

### Shared Command Builder

Extract a `buildAgentCommand(session:profile:resume:)` helper used by both `startTmuxSession` and `restartSession`. This prevents the two paths from drifting apart (the `useHappy` bug is an example of such drift).

```swift
private func buildAgentCommand(
    session: Session,
    profile: AgentProfile,
    resume: Bool = false
) -> String? {
    guard profile.id != "shell" else { return nil }
    var parts: [String] = []
    if session.useHappy {
        parts.append("happy")
        parts.append(session.tool.command)
    } else {
        parts.append(profile.command)
    }
    parts.append(contentsOf: profile.arguments)
    if resume {
        parts.append(contentsOf: profile.resumeArguments)
    }
    if session.tool.supportsPermissionModes {
        parts.append(contentsOf: session.permissionMode.cliFlags(for: session.tool))
    }
    return parts.joined(separator: " ")
}
```

`startTmuxSession` calls with `resume: false`, `restartSession` calls with `resume: true`.

### Edge Cases

- **Shell sessions**: `resumeArguments` is `[]`, no behavioral change.
- **Custom agents with no resume support**: `resumeArguments` defaults to `[]`, behaves as fresh start.
- **First launch with resume flag**: Claude's `--continue` starts a new session if nothing exists in that directory. Gemini and Codex behave similarly. Safe.

## Fork Session

### Trigger

Context menu on any session with a worktree: "Fork Session" (`arrow.triangle.branch` icon). Disabled when `session.worktreeBranch == nil` — can't fork a non-worktree session.

### Flow

1. User right-clicks session -> "Fork Session"
2. `forkSession(id:)` opens `NewSessionDialog` pre-populated with:
   - **Title**: `"Fork of {original title}"`
   - **Project**: same as source
   - **Tool**: same as source
   - **Permission mode**: same as source
   - **Happy toggle**: same as source (`useHappy` inherited)
   - **Worktree**: enabled, branch name auto-generated as `{source-branch}-fork` (editable). If that branch already exists, append a numeric suffix (`-fork-2`, `-fork-3`, etc.)
   - **`parentID`**: set to source session's ID
   - **`baseBranch`**: set to source session's `worktreeBranch`
3. User can adjust any field, then clicks Create
4. Normal `handleNewSessionRequest` runs — creates worktree branching from source session's branch (not the default base branch)
5. Fresh agent conversation starts in the new worktree directory

### Key Difference from Normal New Session

The worktree's `baseBranch` is the source session's worktree branch, not `main`/`master`. The forked worktree starts with all code changes from the source session.

### Changes

- **`NewSessionRequest`**: Add `baseBranch: String?` field
- **`handleNewSessionRequest`**: Pass `baseBranch` to `worktreeManager.createWorktree()` when non-nil
- **`SidebarActions`**: Add `forkSession(id: String)` method
- **`RunwayStore`**: Implement `forkSession` — opens dialog with pre-populated values
- **`ProjectTreeView`**: Add context menu item, gated on `worktreeBranch != nil`

### Non-Worktree Sessions

Fork is disabled for non-worktree sessions. There's no isolated branch to fork from. Users can create a new worktree session from the project instead.

## UI Indicators

### Sidebar Row

**Happy indicator**: When `session.useHappy == true`, show a small `iphone` SF Symbol icon next to the tool badge. Same area as existing tool badge (non-hover zone). `caption2` styling, secondary color.

**Fork indicator**: When `session.parentID != nil`, show `arrow.triangle.branch` SF Symbol icon next to the title. Secondary color, matching branch name styling.

Sidebar row layout for a forked Happy session:
```
[status] Session Title  [fork-icon]
         feature/my-fork
         Last activity text...
                                    [phone-icon] [Gemini CLI]
```

### Header

**Tool badge**: Extend the existing `"tool . mode"` badge to include Happy:
- Normal: `"claude . accept edits"`
- With Happy: `"claude . happy . accept edits"`
- The "happy" segment uses accent/teal color to stand out

**Fork label**: When `session.parentID != nil`, add a line below the title row:
```
[fork-icon] Forked from "Parent Session Name"
```
Caption font, secondary color. Parent name is clickable (calls `selectSession(parentID)`). If the parent has been deleted (cascade sets `parentID` to nil), this line does not appear.

Full header layout for a forked Happy session:
```
[status] My Forked Session   Running   [claude . happy . accept edits]
         [fork-icon] Forked from "Original Session"
         [branch] feature/my-fork  <-  main
```

## Files Changed

| File | Change |
|------|--------|
| `Sources/Models/AgentProfile.swift` | Add `resumeArguments` field, populate for built-ins |
| `Sources/Models/NewSessionRequest.swift` | Add `baseBranch: String?` field |
| `Sources/App/RunwayStore.swift` | Extract `buildAgentCommand`, update `restartSession` to use resume args + fix Happy bug, implement `forkSession`, update `handleNewSessionRequest` to pass `baseBranch` |
| `Sources/Views/Sidebar/ProjectTreeView.swift` | Add fork context menu item, fork icon on `parentID != nil` rows, Happy icon on `useHappy` rows, add `forkSession` to `SidebarActions` protocol |
| `Sources/Views/SessionDetail/SessionHeaderView.swift` | Add "Forked from" label, extend tool badge with Happy segment |
| `Sources/Views/Shared/NewSessionDialog.swift` | Accept pre-populated fork values, expose `baseBranch` |
| `Tests/` | Update AgentProfile tests for new field, add fork flow tests |

## Out of Scope

- Interactive session picker (Claude's `--resume` with picker) — Runway manages sessions itself
- Forking non-worktree sessions
- Forking conversation context into the new worktree (agent sessions are directory-scoped)
- Changes to the `Session` model or database schema
