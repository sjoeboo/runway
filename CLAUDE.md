# CLAUDE.md

## Project Overview

**Runway** is a native macOS app for managing AI coding agent sessions. Built with SwiftUI and Swift Package Manager, it provides terminal management (via libghostty), git worktree operations, GitHub PR management, and todo tracking — all in a single-window native interface.

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
| `Models` | Session, Project, Group, Todo, PullRequest, HookEvent |
| `Persistence` | GRDB/SQLite with migrations |
| `Terminal` | TerminalProvider protocol, PTY management |
| `TerminalView` | NSViewRepresentable terminal wrapper |
| `GitOperations` | git CLI worktree operations |
| `GitHubOperations` | gh CLI PR operations |
| `StatusDetection` | Hook server + buffer-based status detector |
| `Theme` | AppTheme, ChromePalette, TerminalPalette |
| `Views` | All SwiftUI views (sidebar, session detail, PR dashboard, todos) |

## Key Patterns

- **@Observable** store (`RunwayStore`) as single source of truth
- **Actor-based** managers for thread safety (WorktreeManager, PRManager, NativePTYProvider)
- **TerminalProvider protocol** abstracts terminal backend (currently NativePTYProvider, will be libghostty)
- **GRDB** for SQLite persistence with typed records
- **Theme environment** — `@Environment(\.theme)` provides current AppTheme to all views

## Config Directory

`~/.runway/` — state.db, themes/, logs/

## Status Detection

Dual-path: HTTP hooks (port 47437) + terminal buffer scanning. Same patterns as Hangar's detector.go.
