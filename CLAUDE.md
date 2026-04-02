# CLAUDE.md

## Project Overview

**Runway** is a native macOS app for managing AI coding agent sessions. Built with SwiftUI and Swift Package Manager, it provides terminal management (via SwiftTerm), git worktree operations, and GitHub PR management — all in a single-window native interface.

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
| `Models` | Session, Project, Group, PullRequest, HookEvent |
| `Persistence` | GRDB/SQLite with migrations |
| `Terminal` | TerminalProvider protocol, PTY management |
| `CGhosttyVT` | libghostty C wrapper (excluded from build, awaiting SIMD support) |
| `TerminalView` | NSViewRepresentable wrapping SwiftTerm |
| `GitOperations` | git CLI worktree operations |
| `GitHubOperations` | gh CLI PR operations |
| `StatusDetection` | Hook server + buffer-based status detector |
| `Theme` | AppTheme, ChromePalette, TerminalPalette |
| `Views` | All SwiftUI views (sidebar, session detail, PR dashboard) |

## Key Patterns

- **@Observable** store (`RunwayStore`) as single source of truth
- **Actor-based** managers for thread safety (WorktreeManager, PRManager, NativePTYProvider)
- **TerminalProvider protocol** abstracts terminal backend (currently SwiftTerm, libghostty on standby)
- **GRDB** for SQLite persistence with typed records
- **Theme environment** — `@Environment(\.theme)` provides current AppTheme to all views

## Config Directory

`~/.runway/` — state.db, themes/, logs/

## Status Detection

Dual-path: HTTP hooks (port 47437) + terminal buffer scanning. Same patterns as Hangar's detector.go.
