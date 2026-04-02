# Runway — TODO

## Critical / Core Functionality

- [x] **PR tab working** — PRManager wired into RunwayStore with fetch on load, filter support, detail loading, approve/comment actions
- ~~**Todo tab**~~ — Removed; future plan is GitHub Issues integration via PR tab
- [x] **Session status indicators** — Hook server extracts `X-Runway-Session-Id` header to map events to correct Runway session; status updates flow through RunwayStore
- [x] **Bypass permissions option** — PermissionMode picker (Default / Accept Edits / Bypass All) in NewSessionDialog, persisted to DB, passed as CLI flags to claude
- [x] **Worktree default branch detection** — `git symbolic-ref refs/remotes/origin/HEAD` with fallback to local branch check; auto-detects on project load and creation

## Terminal / Session UX

- [ ] **Add terminal tabs** — the "+" button for adding shell tabs to a session doesn't appear (tab bar only shows when >1 tab exists, but you can't create the second tab)
- [ ] **Right sidebar/footer for extra terminals** — option to show additional shell tabs as a split pane (bottom or right) instead of tabs
- [ ] **PR/diff info panel for session** — header/footer/sidebar showing worktree branch, diff summary (+/-), PR status, checks — visible while working in the terminal
- [ ] **Session restart** — ability to restart a stopped/exited session without creating a new one
- [ ] **Session delete** — right-click or keyboard shortcut to delete sessions and clean up worktrees
- [ ] **Send text to session** — the SendTextBar component exists but isn't wired into the UI

## PR Integration

- [ ] **Fetch PRs on app launch** — RunwayStore should fetch PRs for all registered projects
- [ ] **PR detail loading** — clicking a PR should fetch full detail (body, reviews, comments, files) via `gh pr view --json`
- [ ] **PR actions** — approve, comment, request changes from the PR detail drawer
- [ ] **Open PR in browser** — wire the "Open in Browser" button
- [ ] **Session ↔ PR linking** — auto-detect PR for a session's worktree branch

## UI Polish

- [ ] **Sidebar styling** — project/session list needs better visual hierarchy, hover states, context menus
- [ ] **Session context menu** — right-click for rename, delete, move, restart, open in editor
- [ ] **Responsive layout** — sidebar width persistence, detail area minimum sizes
- [ ] **Status toast improvements** — currently only shows errors; add success/info toasts
- [ ] **Empty states** — better empty states for PR and Todo tabs (with action buttons)
- [ ] **Window title** — show current session name in window title bar
- [ ] **Drag and drop** — reorder sessions within projects, move between projects

## Theme / Appearance

- [ ] **Theme persistence** — selected theme should persist across app restarts (currently resets to Tokyo Night)
- [ ] **Terminal color sync** — theme terminal palette should be applied to SwiftTerm (currently only fg/bg/selection, not ANSI 0-15)
- [ ] **Custom theme import** — load JSON themes from ~/.runway/themes/
- [ ] **Ghostty theme import** — parse .conf theme files into AppTheme

## Architecture / Backend

- [ ] **libghostty terminal** — revisit when libghostty-spm supports embedding in NavigationSplitView (SwiftTerm is current workaround)
- [ ] **Hook server testing** — verify Claude Code hooks actually fire and update session status
- [ ] **Claude Code hook injection** — verify/test the settings.json injection works
- [ ] **Database cleanup** — session cleanup for exited/orphaned sessions
- [ ] **Proper .app bundle** — build as a real .app with Info.plist, icon, entitlements (currently SPM executable)
- [ ] **Error handling** — surface errors from git/gh operations to the user properly

## Nice to Have (Future)

- [ ] **Global search** — search across sessions, PRs, projects (⌘/)
- [ ] **macOS notifications** — notify when session status changes (waiting → needs attention)
- [ ] **Fork session** — create child session from parent
- [ ] **Editor integration** — "Open in editor" button (VS Code, Cursor, etc.)
- [ ] **Homebrew formula** — `brew install runway`
- [ ] **GoReleaser / CI** — automated builds and releases
- [ ] **Import from Hangar** — read ~/.hangar/state.db to migrate existing sessions
