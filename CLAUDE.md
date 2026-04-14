# CLAUDE.md

## Project Overview

**Runway** is a native macOS app for managing AI coding agent sessions. Built with SwiftUI and Swift Package Manager, it provides embedded terminals (via SwiftTerm), git worktree isolation, GitHub PR management, GitHub Issues, live status detection, and a theme system — all in a single-window native interface.

## Build & Test

```bash
swift build                    # Build all targets
swift test                     # Run all tests
swift run Runway               # Run the app
```

### Packaging

```bash
make package                   # Build release universal .app bundle → build/Runway.app
make dmg                       # Create DMG installer (run package first)
make dist                      # Full distribution build (package + DMG)
```

### Development

```bash
make setup                     # Install swiftlint, swift-format, git pre-commit hook
make check                     # Build + test + lint + format-check (mirrors CI)
make fix                       # Auto-fix lint and format issues
make precommit                 # Fix, then verify everything passes
```

## Architecture

Pure SwiftUI app with modular SPM targets:

| Target | Purpose |
|--------|---------|
| `App` | SwiftUI entry point, window management, RunwayStore |
| `Models` | Session, Project, PullRequest, HookEvent, GitHubIssue, AgentProfile, SessionEvent, SessionTemplate |
| `Persistence` | GRDB/SQLite with migrations (v1–v14) |
| `Terminal` | TerminalProvider protocol, PTY + tmux session management |
| `TerminalView` | NSViewRepresentable wrapping SwiftTerm, TerminalSearchBar, event monitors, session cache |
| `GitOperations` | Actor-based git CLI worktree operations |
| `GitHubOperations` | Actor-based gh CLI wrapper for PRs and issues |
| `StatusDetection` | Hook server + buffer-based status detector + hook injector |
| `Theme` | AppTheme, ChromePalette, TerminalPalette |
| `Views` | All SwiftUI views (sidebar, session detail, PR dashboard, issues, settings, project pages) |
| `CGhosttyVT` | libghostty C wrapper (excluded from build, awaiting SIMD support) |

## Dependencies

| Package | Purpose |
|---------|---------|
| GRDB.swift (7.10+) | SQLite ORM with typed records and migrations |
| SwiftTerm | Terminal emulator (AppKit NSView) with search API |
| Sparkle (2.9+) | Auto-update framework for macOS |

## Key Patterns

- **@Observable** store (`RunwayStore`) as single source of truth
- **SidebarActions protocol** — eliminates prop drilling; `RunwayStore` conforms, Views module references protocol only
- **Actor-based** managers for thread safety (WorktreeManager, PRManager, NativePTYProvider)
- **TerminalProvider protocol** abstracts terminal backend (currently SwiftTerm, libghostty on standby)
- **GRDB** for SQLite persistence with typed records and 17 migrations
- **Theme environment** — `@Environment(\.theme)` provides current AppTheme to all views
- **TerminalSessionCache** — LRU cache keeps terminal views alive across SwiftUI navigation

## Config Directory

`~/.runway/` — state.db, themes/, logs/

## Status Detection

Dual-path: HTTP hooks (ephemeral port, force-injected on every launch into `~/.claude/settings.json`) + terminal buffer polling (3-second interval). Subscribes to: SessionStart, UserPromptSubmit, PermissionRequest, Notification, Stop, SessionEnd.

## Testing

331 tests across 8 targets: ModelsTests, PersistenceTests, StatusDetectionTests, GitOperationsTests, ThemeTests, GitHubOperationsTests, TerminalTests, ViewsTests.

## Keyboard Shortcuts

`Cmd+1/2` (views), `Cmd+N` (session), `Cmd+Shift+P` (project), `Cmd+K` (search), `Cmd+F` (terminal find), `Cmd+Shift+X` (send bar), `Ctrl+1/2/3` (PR tabs), `Shift+Enter` (newline in terminal).

## Known Issues & Architecture Notes (v0.8.0 Audit)

See `ROADMAP-1.0.md` for the full prioritized plan. Key things to know when working on this codebase:

### Critical Bugs (fix first)
- **Branch name sanitization** (`WorktreeManager.swift:276`): `sanitizeBranchName` replaces `/` with `-`, breaking PR-to-session linking and branch deletion for `feature/`, `fix/` branches. Fix: use original name for git branch, only sanitize directory path.
- **TerminalPalette precondition** (`AppTheme.swift:78`): `precondition(ansi.count == 16)` crashes on malformed theme JSON. Replace with pad/truncate.
- **GraphQL injection** (`PRManager.swift:276`): `nodeID` interpolated into mutation string. Validate characters before use.
- **Cache eviction leaks processes** (`TerminalSessionCache.swift:87`): LRU eviction drops view without terminating PTY attach process.

### Architecture Concerns
- **RunwayStore is 1708 lines** with ~50 @Observable properties. Every property mutation invalidates the entire view tree. Plan: extract `PRCoordinator` (~400 LOC) and `SessionLifecycleCoordinator` to reduce to ~900 LOC.
- **Buffer detection polls on MainActor** every 3s for all sessions — should be moved off-main.
- **4 uncoordinated polling timers** (3s, 10s, 15s, 30s) align every 30s causing CPU spikes. Add jitter.
- **`ShellRunner.run()` has no timeout** — a hung subprocess blocks the entire calling actor forever.

### PTY/Terminal Safety
- `PTYProcess.write()`/`resize()` race with FD close — check `isAlive` and use FD under same lock.
- `PTYProcess.deinit` doesn't call `waitpid()` — zombie processes accumulate.
- `HookServer` has no connection timeout and no auto-restart on `.failed` state.
- Register hook event handler BEFORE `hookServer.start()`, not after.

### Test Coverage Gaps
- **RunwayStore** (1800 LOC orchestrator): ZERO tests. Highest-priority gap.
- **TerminalView** module: ZERO tests (cache, key monitors, search).
- No database migration upgrade path tests.
- No end-to-end HookServer → StatusDetector integration test.

### UX Gaps
- VoiceOver accessibility labels almost entirely missing.
- Session error/stopped state has no inline recovery action.
- Send bar hardcodes "Claude" label regardless of tool.
- Activity log and settings use hardcoded system colors instead of theme colors.
