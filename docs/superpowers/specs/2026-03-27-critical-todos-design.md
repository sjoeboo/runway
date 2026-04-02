# Critical TODOs — Design Spec

## Scope

Five changes in dependency order:

1. Remove Todo feature (cleanup)
2. Worktree default branch detection
3. PR tab wiring
4. Session status indicators
5. Bypass permissions option

---

## 1. Remove Todo Feature

**What:** Strip all Todo-related code. The kanban board is unused; future task tracking will come via GitHub Issues integration.

**Files to modify:**
- `Sources/App/RunwayStore.swift` — remove `todos` array, any todo methods
- `Sources/Views/TodoBoard/` — delete entire directory
- `Sources/Views/Shared/` — remove todo references from shared views if any
- `Sources/App/RunwayApp.swift` — remove `.todos` from AppView enum and tab picker
- `Sources/Models/Todo.swift` — keep file (DB migration references it), but mark as deprecated or leave for migration compatibility
- `Sources/Persistence/Database.swift` — keep table in migration (don't break existing DBs), but remove active query methods
- `Sources/Persistence/Records.swift` — keep TodoRecord for migration, remove from active use

**Decision:** Keep the DB table/migration intact so existing databases don't break. Just remove all UI, store, and active persistence code.

---

## 2. Worktree Default Branch Detection

**What:** Auto-detect the default branch (main vs master) from git remote instead of hardcoding "main".

**Approach:**
- Add `detectDefaultBranch(repoPath:)` to `WorktreeManager`
- Run `git symbolic-ref refs/remotes/origin/HEAD` → parse `refs/remotes/origin/main` → "main"
- Fallback chain: symbolic-ref fails → try `git remote show origin` and parse "HEAD branch:" → fall back to "main"
- Call on project creation/load, store result in `Project.defaultBranch`
- RunwayStore calls this when adding a project and updates the stored value

**Files to modify:**
- `Sources/GitOperations/WorktreeManager.swift` — add `detectDefaultBranch(repoPath:)`
- `Sources/App/RunwayStore.swift` — call detection on project add/load

---

## 3. PR Tab Wiring

**What:** PRDashboardView is fully built but RunwayStore never populates `pullRequests`. Wire PRManager into the store.

**Approach:**
- On app launch (RunwayStore.init), fetch PRs for all projects
- On tab switch to `.prs`, refresh if stale (>60s since last fetch)
- Store PRs in RunwayStore.pullRequests, keyed/filtered by project
- Wire filter changes (mine/reviewRequested/all) to re-fetch
- Wire PR detail loading when a PR is selected
- Wire "Open in Browser" button

**Files to modify:**
- `Sources/App/RunwayStore.swift` — add PR fetching, refresh logic, detail loading
- `Sources/Views/PRDashboard/PRDashboardView.swift` — connect to store's PR data and actions
- `Sources/Views/PRDashboard/PRDetailDrawer.swift` — wire approve/comment/browser actions if not already

**Data flow:**
```
RunwayStore.init → PRManager.fetchPRs(repo:) for each project
                 → store in pullRequests array
                 → PRDashboardView observes @Observable store
                 → user selects PR → fetchDetail → PRDetailDrawer
```

---

## 4. Session Status Indicators

**What:** Status dots in sidebar are static. Hook server receives events but doesn't update session status.

**Current state:**
- HookServer listens on port 47437, receives HookEvents
- StatusDetector can analyze terminal buffer text
- SessionDetailView already renders colored dots based on session.status
- But nothing connects hook events → session.status updates

**Approach:**
- In RunwayStore, register a hook event handler with HookServer
- On hook event received, map event type to session status:
  - `SessionStart` → `.running`
  - `UserPromptSubmit` → `.running`
  - `PermissionRequest` → `.waiting`
  - `Notification` → keep current status (just log)
  - `Stop` → `.idle`
  - `SessionEnd` → `.stopped`
- Update both in-memory session and persist to DB
- StatusDetector serves as secondary detection (buffer scanning) for sessions where hooks aren't firing

**Files to modify:**
- `Sources/App/RunwayStore.swift` — register hook handler, map events to status
- `Sources/StatusDetection/HookServer.swift` — verify handler registration API exists

---

## 5. Bypass Permissions Option

**What:** NewSessionDialog needs a permission mode picker that passes the appropriate flag to the claude process.

**Approach:**
- Add `PermissionMode` enum: `.default`, `.acceptEdits`, `.bypassAll`
- Add picker to NewSessionDialog UI
- Include selected mode in `NewSessionRequest`
- When launching claude session, map mode to CLI flags:
  - `.default` → no extra flags
  - `.acceptEdits` → `--accept-edits`
  - `.bypassAll` → `--dangerously-skip-permissions`
- Session model gets optional `permissionMode` field for display/persistence

**Files to modify:**
- `Sources/Models/Session.swift` — add `PermissionMode` enum and optional field
- `Sources/Views/Shared/NewSessionDialog.swift` — add picker UI
- `Sources/App/RunwayStore.swift` — pass permission mode through session creation to terminal launch
- `Sources/Terminal/` — ensure permission flags reach the PTY command

---

## Testing Strategy

- Build verification after each change (`swift build`)
- Existing tests must continue to pass (`swift test`)
- Manual verification of each feature in running app
