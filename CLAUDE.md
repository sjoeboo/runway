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
| `Models` | Session, Project, PullRequest, HookEvent, GitHubIssue |
| `Persistence` | GRDB/SQLite with migrations (v1–v8) |
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
- **GRDB** for SQLite persistence with typed records and 8 migrations
- **Theme environment** — `@Environment(\.theme)` provides current AppTheme to all views
- **TerminalSessionCache** — LRU cache keeps terminal views alive across SwiftUI navigation

## Config Directory

`~/.runway/` — state.db, themes/, logs/

## Status Detection

Dual-path: HTTP hooks (ephemeral port, force-injected on every launch into `~/.claude/settings.json`) + terminal buffer polling (3-second interval). Subscribes to: SessionStart, UserPromptSubmit, PermissionRequest, Notification, Stop, SessionEnd.

## Testing

118 tests across 8 targets: ModelsTests, PersistenceTests, StatusDetectionTests, GitOperationsTests, ThemeTests, GitHubOperationsTests, TerminalTests, ViewsTests.

## Keyboard Shortcuts

`Cmd+1/2` (views), `Cmd+N` (session), `Cmd+Shift+P` (project), `Cmd+K` (search), `Cmd+F` (terminal find), `Cmd+Shift+X` (send bar), `Ctrl+1/2/3` (PR tabs), `Shift+Enter` (newline in terminal).
