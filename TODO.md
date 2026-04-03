# Runway — TODO

## Critical / Core Functionality

- [x] **PR tab working** — PRManager wired into RunwayStore with fetch on load, filter support, detail loading, approve/comment actions
- ~~**Todo tab**~~ — Removed; future plan is GitHub Issues integration via PR tab
- [x] **Session status indicators** — Hook server extracts `X-Runway-Session-Id` header to map events to correct Runway session; status updates flow through RunwayStore
- [x] **Bypass permissions option** — PermissionMode picker (Default / Accept Edits / Bypass All) in NewSessionDialog, persisted to DB, passed as CLI flags to claude
- [x] **Worktree default branch detection** — `git symbolic-ref refs/remotes/origin/HEAD` with fallback to local branch check; auto-detects on project load and creation
- [x] **Session persistence** — Sessions should continue running when navigating away (to another session, PR tab, etc.) or closing the app. Similar to Hangar's tmux-based approach — the underlying process must survive view changes and app lifecycle events
- [x] **Auto-detect master/main branch** — When adding a new project, auto-detect whether the repo uses `master` or `main` as its default branch

## Terminal / Session UX

- [x] **Add terminal tabs** — the "+" button for adding shell tabs to a session doesn't appear (tab bar only shows when >1 tab exists, but you can't create the second tab)
- [ ] **Right sidebar/footer for extra terminals** — option to show additional shell tabs as a split pane (bottom or right) instead of tabs
- [ ] **PR/diff info panel for session** — header/footer/sidebar showing worktree branch, diff summary (+/-), PR status, checks — visible while working in the terminal
- [x] **Session restart** — ability to restart a stopped/exited session without creating a new one
- [x] **Session delete** — right-click or keyboard shortcut to delete sessions and clean up worktrees
- [ ] **Send text to session** — the SendTextBar component exists but isn't wired into the UI

## Sidebar UX

- [x] **Project names larger** — increase font size/weight for project names in the sidebar for better visual hierarchy
- [ ] **Collapsible/expandable projects** — projects should be collapsible disclosure groups; remember expanded state
- [ ] **Inline "+" button per project** — each project header gets a "+" button to add a new session directly
- [ ] **Add project from sidebar** — ability to add a new project from the sidebar (e.g., "+" at the top or bottom of the project list)
- [ ] **Remove top-right new session/project buttons** — once sidebar has inline add controls, remove the redundant buttons from the upper-right toolbar

## PR Integration

- [ ] **Fetch PRs on app launch** — RunwayStore should fetch PRs for all registered projects
- [ ] **PR detail loading** — clicking a PR should fetch full detail (body, reviews, comments, files) via `gh pr view --json`
- [ ] **PR actions** — approve, comment, request changes from the PR detail drawer
- [ ] **Open PR in browser** — wire the "Open in Browser" button
- [ ] **Session ↔ PR linking** — auto-detect PR for a session's worktree branch

## UI Polish

- [ ] **Sidebar styling** — project/session list needs better visual hierarchy, hover states, context menus
- [x] **Session context menu** — right-click for rename, delete, move, restart, open in editor
- [ ] **Responsive layout** — sidebar width persistence, detail area minimum sizes
- [ ] **Status toast improvements** — currently only shows errors; add success/info toasts
- [ ] **Empty states** — better empty states for PR and Todo tabs (with action buttons)
- [x] **Window title** — show current session name in window title bar
- [ ] **Drag and drop** — reorder sessions within projects, move between projects

## Theme / Appearance

- [ ] **Theme persistence** — selected theme should persist across app restarts (currently resets to Tokyo Night)
- [ ] **Terminal color sync** — theme terminal palette should be applied to SwiftTerm (currently only fg/bg/selection, not ANSI 0-15)
- [ ] **Custom theme import** — load JSON themes from ~/.runway/themes/
- [ ] **Ghostty theme import** — parse .conf theme files into AppTheme

## Architecture / Backend

- [ ] **libghostty terminal** — revisit when libghostty-spm supports embedding in NavigationSplitView (SwiftTerm is current workaround)
- [ ] **Hook server testing** — verify Claude Code hooks actually fire and update session status
- [x] **Hook server dynamic port** — hook server gets "address in use" errors on startup; switch to dynamic port selection (bind to port 0 or scan for available port) to avoid conflicts. This may be why sidebar session statuses aren't updating
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
