# Changelog

All notable changes to Runway are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.9.0] — 2026-04-13

### Added

- **Saved prompts** — save and reuse frequently-sent prompts in the send bar, with global and per-project scope ([#300](https://github.com/sjoeboo/runway/pull/300))
- **Transcript viewer** — read-only JSONL transcript viewer for browsing session conversations ([#300](https://github.com/sjoeboo/runway/pull/300))
- **Commit history popover** — browse branch commit history from the session header with rollback capability ([#301](https://github.com/sjoeboo/runway/pull/301))
- **PR status badges** — visual merge-state badges in the PR dashboard and project PR tabs ([#300](https://github.com/sjoeboo/runway/pull/300))
- **VoiceOver accessibility** — comprehensive accessibility labels across sidebar, session detail, PR dashboard, and dialog views ([#301](https://github.com/sjoeboo/runway/pull/301))

### Fixed

- **Branch name sanitization** — fixed `sanitizeBranchName` replacing `/` with `-`, which broke PR-to-session linking and branch deletion for `feature/` and `fix/` branches ([#300](https://github.com/sjoeboo/runway/pull/300))
- **TerminalPalette crash** — replaced `precondition(ansi.count == 16)` with pad/truncate so malformed theme JSON no longer crashes the app ([#300](https://github.com/sjoeboo/runway/pull/300))
- **GraphQL injection** — PR node IDs are now validated before interpolation into mutation strings ([#300](https://github.com/sjoeboo/runway/pull/300))
- **Cache eviction process leak** — LRU eviction now terminates the PTY process before dropping the terminal view ([#301](https://github.com/sjoeboo/runway/pull/301))
- **ShellRunner timeout** — `ShellRunner.run()` now has a configurable timeout so a hung subprocess no longer blocks the calling actor forever ([#300](https://github.com/sjoeboo/runway/pull/300))
- **HookServer reliability** — added connection timeout and auto-restart on failed state ([#300](https://github.com/sjoeboo/runway/pull/300))
- **PTY process safety** — fixed write/resize race with FD close; deinit now calls `waitpid()` to prevent zombie processes ([#300](https://github.com/sjoeboo/runway/pull/300))
- **Theme color consistency** — activity log and settings views now use theme colors instead of hardcoded system colors ([#300](https://github.com/sjoeboo/runway/pull/300))

### Maintenance

- Extracted PRCoordinator (~400 LOC) from RunwayStore, reducing it from ~1,700 to ~900 lines for better `@Observable` invalidation scope ([#301](https://github.com/sjoeboo/runway/pull/301))
- Test suite expanded from 293 to 329 tests with new coverage for WorktreeManager, ShellRunner, HookServer, and TerminalSessionCache ([#300](https://github.com/sjoeboo/runway/pull/300), [#301](https://github.com/sjoeboo/runway/pull/301))
- Added ROADMAP-1.0.md tracking remaining work toward 1.0 release ([#300](https://github.com/sjoeboo/runway/pull/300))

[0.9.0]: https://github.com/sjoeboo/runway/compare/v0.8.0...v0.9.0

## [0.8.0] — 2026-04-13

### Added

- **Tabbed file diffs** — clicking a changed file in the sidebar now opens the diff in a new tab alongside the terminal, instead of replacing the session view; tabs can be closed independently and clicking the same file focuses the existing tab ([#299](https://github.com/sjoeboo/runway/pull/299))

[0.8.0]: https://github.com/sjoeboo/runway/compare/v0.7.2...v0.8.0

## [0.7.2] — 2026-04-13

### Fixed

- **Diff sidebar freeze with many changed files** — resolved a UI freeze when viewing PRs with a large number of changed files ([#298](https://github.com/sjoeboo/runway/pull/298))

[0.7.2]: https://github.com/sjoeboo/runway/compare/v0.7.1...v0.7.2

## [0.7.1] — 2026-04-10

### Added

- **Close PR button** — close pull requests directly from the PR dashboard without leaving the app ([#297](https://github.com/sjoeboo/runway/pull/297))

[0.7.1]: https://github.com/sjoeboo/runway/compare/v0.7.0...v0.7.1

## [0.7.0] — 2026-04-10

### Added

- **PR dashboard overhaul** — sortable columns, filter bar, and native macOS Table view replace the previous list-based layout ([#296](https://github.com/sjoeboo/runway/pull/296))

### Fixed

- **Crash when syntax highlighting code blocks** — fixed a crash in the packaged app caused by missing syntax highlighting resources ([#295](https://github.com/sjoeboo/runway/pull/295))
- **PR branch checkout for GHE monorepos** — robust 3-strategy fallback ensures checkout works reliably in GitHub Enterprise monorepo sparse checkouts ([#294](https://github.com/sjoeboo/runway/pull/294))

### Maintenance

- Test suite expanded from 273 to 293 tests

[0.7.0]: https://github.com/sjoeboo/runway/compare/v0.6.2...v0.7.0

## [0.6.0] — 2026-04-09

### Added

- **Session restart/resume** — restart stopped sessions from the sidebar context menu, resuming from where they left off ([#245](https://github.com/sjoeboo/runway/pull/245))
- **Fork session** — create a new session forked from an existing one, inheriting its configuration and branch as a starting point ([#245](https://github.com/sjoeboo/runway/pull/245))
- **Happy wrapper indicators** — visual indicators (cyan permission badge, "happy" subtitle) when a session is launched with Happy for mobile/remote access ([#245](https://github.com/sjoeboo/runway/pull/245))
- **12 new built-in themes** — Catppuccin Mocha/Latte, Dracula/Alucard, Gruvbox Dark/Light, Kanagawa, Nord, Rosé Pine/Dawn, Solarized Dark/Light, all with paired light/dark auto-switching ([#244](https://github.com/sjoeboo/runway/pull/244))

### Fixed

- **43 bugs from pre-1.0.0 bug hunt** — comprehensive quality pass across 27 files covering UI glitches, state management edge cases, and correctness issues ([#246](https://github.com/sjoeboo/runway/pull/246)–[#292](https://github.com/sjoeboo/runway/pull/292), [#293](https://github.com/sjoeboo/runway/pull/293))
- **Crash in notification cleanup** — fixed a crash during notification center cleanup and sidebar disclosure arrow regression ([#243](https://github.com/sjoeboo/runway/pull/243))

### Maintenance

- Test suite expanded from 266 to 273 tests
- Database migration v14 adds Happy wrapper support

[0.6.0]: https://github.com/sjoeboo/runway/compare/v0.5.2...v0.6.0

## [0.5.1] — 2026-04-08

### Fixed

- **Duplicate disclosure arrows in sidebar** — suppressed redundant disclosure arrow on project sections that already have a custom chevron ([#242](https://github.com/sjoeboo/runway/pull/242))

[0.5.1]: https://github.com/sjoeboo/runway/compare/v0.5.0...v0.5.1

## [0.5.0] — 2026-04-08

### Added

- **Multi-agent support** — first-class Gemini CLI and Codex support alongside Claude Code, with agent-specific permission modes, data-driven hook injection, and optional Happy wrapper for mobile/remote access ([#241](https://github.com/sjoeboo/runway/pull/241))

### Fixed

- **Terminal scrollback replay** — eliminated full scrollback buffer replay when switching sessions or tabs ([#239](https://github.com/sjoeboo/runway/pull/239))
- **Dock badge and notifications not clearing** — dock badge count and pending notifications now clear properly when a session leaves the waiting state ([#238](https://github.com/sjoeboo/runway/pull/238))
- **Split panes opening in wrong directory** — split panes now open in the project directory instead of `/`, and click-to-focus works between tmux panes ([#237](https://github.com/sjoeboo/runway/pull/237))

### Maintenance

- Resolved all compiler warnings across the codebase ([#240](https://github.com/sjoeboo/runway/pull/240))
- Test suite expanded from 230 to 266 tests

[0.5.0]: https://github.com/sjoeboo/runway/compare/v0.4.1...v0.5.0

## [0.4.1] — 2026-04-08

### Fixed

- **Notification crash on launch** — Replaced completion-handler-based `UNUserNotificationCenter.add()` with async overload to fix `@MainActor` isolation violation that caused `EXC_BREAKPOINT` on the UserNotifications callback queue

[0.4.1]: https://github.com/sjoeboo/runway/compare/v0.4.0...v0.4.1

## [0.4.0] — 2026-04-08

### Added

- **GFM markdown rendering** — PR and issue detail views now render full GitHub Flavored Markdown with syntax highlighting, tables, task lists, and more ([#236](https://github.com/sjoeboo/runway/pull/236))
- **Notification preferences** — Toggle notifications on or off from Settings ([#233](https://github.com/sjoeboo/runway/pull/233))

### Fixed

- **Notification crash** — Added proper `UNUserNotificationCenterDelegate` to prevent crash when interacting with notifications ([#234](https://github.com/sjoeboo/runway/pull/234))

### Maintenance

- Added Dependabot configuration for automated dependency updates ([#235](https://github.com/sjoeboo/runway/pull/235))

[0.4.0]: https://github.com/sjoeboo/runway/compare/v0.3.0...v0.4.0

## [0.3.0] — 2026-04-07

### Added

- **Native notifications** — macOS notifications for permission requests and session completion, with intelligent filtering to avoid noise ([#232](https://github.com/sjoeboo/runway/pull/232))
- **Issue-linked sessions** — Start sessions directly from GitHub Issues with auto-generated branch names and activity tracking ([#232](https://github.com/sjoeboo/runway/pull/232))
- **Activity log** — Per-session event timeline with issue badge and activity subtitle in sidebar ([#232](https://github.com/sjoeboo/runway/pull/232))
- **PR inline comments** — Grouped inline comments with count badge and send-to-session action in PR detail ([#232](https://github.com/sjoeboo/runway/pull/232))
- **User-installable themes** — Load custom themes from `~/.runway/themes/` JSON files ([#232](https://github.com/sjoeboo/runway/pull/232))
- **Session templates** — Save and reuse session configurations with template picker in the New Session dialog ([#232](https://github.com/sjoeboo/runway/pull/232))
- **Deep linking** — `runway://` URL scheme for opening sessions, PRs, and creating new sessions ([#232](https://github.com/sjoeboo/runway/pull/232))
- **Agent profiles** — Configurable status detection profiles (Claude, Shell built-ins) with profile-based pattern matching ([#232](https://github.com/sjoeboo/runway/pull/232))

### Fixed

- **Changes sidebar expansion** — Files always open expanded; removed unnecessary single-file collapse toggle ([#231](https://github.com/sjoeboo/runway/pull/231))
- **Picker overflow** — Segmented picker no longer clips "Uncommitted" tab in changes sidebar ([#230](https://github.com/sjoeboo/runway/pull/230))
- **Sidebar hover shift** — Section headers no longer shift the + button on hover ([#230](https://github.com/sjoeboo/runway/pull/230))
- **Font consistency** — Standardized section title fonts to `.callout.semibold` across all views ([#230](https://github.com/sjoeboo/runway/pull/230))

### Maintenance

- Added CONTRIBUTING.md with development setup and workflow guide ([#232](https://github.com/sjoeboo/runway/pull/232))
- Added GitHub issue and PR templates ([#232](https://github.com/sjoeboo/runway/pull/232))
- Added architecture guide documenting key design decisions ([#232](https://github.com/sjoeboo/runway/pull/232))
- Added `/release` command for automated release workflow
- Test suite expanded from 180 to 230 tests

[0.3.0]: https://github.com/sjoeboo/runway/compare/v0.2.0...v0.3.0

## [0.2.0] — 2026-04-07

### Added

- **Tmux pane splitting** — Split terminal panes via toolbar buttons or `Cmd+D` (right) / `Cmd+Shift+D` (down) ([#141](https://github.com/sjoeboo/runway/pull/141))
- **PR Review mode** — Dedicated "PR Review" tab in the new session dialog (`Cmd+Shift+R`) creates review sessions for any PR number ([#142](https://github.com/sjoeboo/runway/pull/142))
- **Changes sidebar** — Toggle with `Cmd+3` to see all changed files in a session's worktree, with diff viewer, line stats, and "vs Main" / "Uncommitted" modes ([#143](https://github.com/sjoeboo/runway/pull/143))
- **Orphaned worktree cleanup** — On startup, automatically prunes worktrees that have no matching session; merged branches are deleted, unmerged branches are preserved ([#144](https://github.com/sjoeboo/runway/pull/144))

### Fixed

- **Terminal search feedback** — Shows match count ("N matches") and disables navigation with red tint when no results found ([#219](https://github.com/sjoeboo/runway/pull/219))
- **PTY thread starvation** — Replaced blocking `waitpid()` with event-driven `DispatchSourceProcess`, fixing thread exhaustion with 10+ open sessions ([#219](https://github.com/sjoeboo/runway/pull/219))
- **Worktree failure safety** — Sessions now transition to error state if worktree creation fails, instead of silently falling back to the project root ([#219](https://github.com/sjoeboo/runway/pull/219))
- **Keyboard navigation** — Replaced `DisclosureGroup` with `Section(isExpanded:)` for proper arrow-key and VoiceOver navigation in the project list ([#219](https://github.com/sjoeboo/runway/pull/219))
- **Pipe deadlock in shell runner** — Increased buffer to 64 KB to prevent concurrent read/write hangs ([#218](https://github.com/sjoeboo/runway/pull/218))
- **PR diff pagination** — Large PRs with 31+ files now load correctly ([#218](https://github.com/sjoeboo/runway/pull/218))
- **Branch name sanitization** — Disallows invalid git characters (`~^:?*[]\@{}`, `.lock` suffix, leading/consecutive dots) ([#218](https://github.com/sjoeboo/runway/pull/218))

### Maintenance

- Deep codebase audit addressing 69 issues across security, correctness, accessibility, and UX ([#218](https://github.com/sjoeboo/runway/pull/218))
- Test suite expanded from 118 to 180 tests

[0.2.0]: https://github.com/sjoeboo/runway/compare/v0.1.1...v0.2.0

## [0.1.1] — 2026-04-07

### Added

- **Resizable divider** — Drag to resize the list and detail panels in the main window ([#139](https://github.com/sjoeboo/runway/pull/139))

### Fixed

- **Sidebar project navigation** — Reliably opens the project page when clicking a project in the sidebar ([#138](https://github.com/sjoeboo/runway/pull/138))
- **Monorepo PR cross-contamination** — Provisioning sessions are now skipped during PR linking, preventing incorrect PR associations in monorepo setups ([#140](https://github.com/sjoeboo/runway/pull/140))

### Maintenance

- Refreshed README and CLAUDE.md for v0.1.0 ([#137](https://github.com/sjoeboo/runway/pull/137))

[0.1.1]: https://github.com/sjoeboo/runway/compare/v0.1.0...v0.1.1

## [0.1.0] — 2026-04-07

### Added

- **PR grouping pipeline with merge status badges** — PRs are now grouped by status with visual merge-state badges in the dashboard ([#135](https://github.com/sjoeboo/runway/pull/135))
- **GitHub Issue detail view** — Full-parity detail drawer for GitHub Issues, matching the PR detail experience ([#134](https://github.com/sjoeboo/runway/pull/134))
- **Automerge toggle** — Enable or disable GitHub automerge directly from the PR detail drawer ([#133](https://github.com/sjoeboo/runway/pull/133))
- **Faster session PR detection** — PR status now polls independently per session, reducing latency for active worktrees ([#129](https://github.com/sjoeboo/runway/pull/129))
- **Improved menubar** — New icons, colored status badges, and refined window styling ([#128](https://github.com/sjoeboo/runway/pull/128))
- **CI checks tab** — Detailed GitHub Actions / CI check results shown in the PR detail drawer ([#127](https://github.com/sjoeboo/runway/pull/127))

### Fixed

- **Terminal attach race** — Resolved a race condition when attaching terminals to monorepo worktree sessions ([#132](https://github.com/sjoeboo/runway/pull/132))
- **Shift+Enter in tmux** — Enabled extended-keys in tmux configuration so Shift+Enter works correctly in Claude Code sessions ([#131](https://github.com/sjoeboo/runway/pull/131))
- **Image drag-and-drop** — Terminal sessions now accept dragged images and screenshots ([#130](https://github.com/sjoeboo/runway/pull/130))

### Maintenance

- Updated GitHub Actions workflows ([#126](https://github.com/sjoeboo/runway/pull/126))
- Updated SPM dependencies ([#125](https://github.com/sjoeboo/runway/pull/125))

[0.1.0]: https://github.com/sjoeboo/runway/compare/v0.0.15...v0.1.0
