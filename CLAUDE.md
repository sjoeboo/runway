# CLAUDE.md

## Project Overview

**Runway** is a native macOS app for managing AI coding agent sessions. Built with SwiftUI and Swift Package Manager, it provides terminal management (via SwiftTerm), git worktree operations, GitHub PR management, and GitHub Issues — all in a single-window native interface.

## Build & Test

```bash
cd ~/code/github/runway
swift build                    # Build all targets
swift test                     # Run all tests
swift run Runway               # Run the app
```

## Architecture

Pure SwiftUI app with modular SPM targets:

| Target | Purpose |
|--------|---------|
| `App` | SwiftUI entry point, window management, RunwayStore |
| `Models` | Session, Project, PullRequest, HookEvent, GitHubIssue |
| `Persistence` | GRDB/SQLite with migrations (v1–v8) |
| `Terminal` | TerminalProvider protocol, PTY management |
| `CGhosttyVT` | libghostty C wrapper (excluded from build, awaiting SIMD support) |
| `TerminalView` | NSViewRepresentable wrapping SwiftTerm, TerminalSearchBar, event monitors, session cache |
| `GitOperations` | git CLI worktree operations |
| `GitHubOperations` | gh CLI PR and issue operations |
| `StatusDetection` | Hook server + buffer-based status detector + hook injector |
| `Theme` | AppTheme, ChromePalette, TerminalPalette |
| `Views` | All SwiftUI views (sidebar, session detail, PR dashboard, settings, project pages) |

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

Dual-path: HTTP hooks (ephemeral port, force-injected on every launch) + terminal buffer polling (3-second interval). Detection patterns ported from Hangar's detector.go.

## Keyboard Shortcuts

`Cmd+1/2` (views), `Cmd+N` (session), `Cmd+Shift+P` (project), `Cmd+K` (search), `Cmd+F` (terminal find), `Cmd+Shift+X` (send bar), `Ctrl+1/2/3` (PR tabs), `Shift+Enter` (newline in terminal).
