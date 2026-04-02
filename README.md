# Runway

A native macOS app for managing AI coding agent sessions. Terminal management, git worktrees, GitHub PRs, and project organization — all in one window.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

---

## What is Runway?

Runway is a single-window command center for developers who work with AI coding agents like Claude Code. Instead of juggling terminal tabs, browser windows, and git commands, Runway gives you:

- **Embedded terminals** with real-time status detection (running, waiting, idle, error)
- **Git worktree isolation** — every session gets its own branch and working copy
- **GitHub PR dashboard** — review, approve, and comment without leaving the app
- **Project organization** — group sessions by project, track what's active
- **Theme system** — 6 built-in themes (Tokyo Night, Ayu Mirage, Everforest, Oasis Lagoon) applied to both UI and terminal

## Quick Start

### Prerequisites

- macOS 14 (Sonoma) or later
- [Swift 6.0+](https://www.swift.org/install/) (bundled with Xcode 16+)
- [GitHub CLI](https://cli.github.com/) (`gh`) for PR features
- Git (bundled with Xcode Command Line Tools)

### Build & Run

```bash
git clone https://github.com/sjoeboo/runway.git
cd runway
swift build
swift run Runway
```

### Development Setup

Install the linting and formatting tools:

```bash
make setup   # installs swiftlint and swift-format via Homebrew
```

### Common Commands

```bash
make check      # build + test + lint + format-check (mirrors CI)
make test       # run all tests
make fix        # auto-fix lint and format issues
make precommit  # fix, then verify everything passes
make lint       # SwiftLint only
make help       # show all available targets
```

All PRs must pass the CI pipeline (build, test, SwiftLint, swift-format) before merging.

## Features

### Session Management

Create named sessions tied to projects. Each session launches a terminal running your chosen tool (Claude Code, shell, or custom command) in an isolated git worktree.

- **Auto-branch naming** — session name automatically suggests a branch (e.g., "fix auth flow" → `fix-auth-flow`)
- **Worktree isolation** — each session works in `.worktrees/{branch}`, keeping `main` clean
- **Default branch detection** — auto-detects `main` vs `master` via `git symbolic-ref`
- **Permission modes** — choose Default, Accept Edits, or Bypass All per session
- **Multiple terminal tabs** — add shell tabs alongside your main agent session
- **Session persistence** — sessions survive app restarts via SQLite

### Live Status Detection

Runway knows what your agent is doing. Two detection paths work together:

| Method | How it works |
|--------|-------------|
| **HTTP Hooks** | Claude Code sends lifecycle events (session start, permission request, stop) to Runway's hook server on port `47437` |
| **Buffer Scanning** | Terminal output is scanned for patterns — spinners, prompts, permission dialogs, idle indicators |

Status shows in the sidebar as colored indicators:
- Green circle = running
- Yellow half-circle = waiting for permission
- Hollow circle = idle
- Red X = error

### GitHub PR Dashboard

Built-in PR management powered by `gh` CLI:

- **Three views**: All PRs, Mine, Review Requested
- **Detail drawer** with overview, diff, and conversation tabs
- **Actions**: approve, comment, open in browser
- **Visual status**: check results, review state, diff stats

### Theme System

Six hand-crafted themes with paired light/dark variants:

| Theme | Style |
|-------|-------|
| Tokyo Night Storm | Dark, purple/blue |
| Ayu Mirage | Dark, warm amber |
| Everforest Dark | Dark, nature green |
| Everforest Light | Light, nature green |
| Oasis Lagoon Dark | Dark, deep navy |
| Oasis Lagoon Light | Light, ocean blue |

Themes apply to both the app chrome (sidebar, toolbar, status bar) and the terminal (ANSI colors, cursor, selection). System appearance auto-switching is supported.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+N` | New session |
| `Cmd+Shift+P` | New project |
| `Cmd+1` | Sessions view |
| `Cmd+2` | PRs view |
| `Shift+Enter` | Newline in terminal (instead of submit) |

## Architecture

Runway is a pure SwiftUI app built with Swift Package Manager. The codebase is split into 11 focused targets:

```
Sources/
├── App/                # @main entry, RunwayStore, window setup
├── Models/             # Session, Project, Group, PullRequest, HookEvent
├── Persistence/        # GRDB/SQLite database (WAL mode, ~/.runway/state.db)
├── Terminal/           # TerminalProvider protocol, PTY process management
├── TerminalView/       # NSViewRepresentable wrapping SwiftTerm
├── GitOperations/      # Actor-based git worktree CLI wrapper
├── GitHubOperations/   # Actor-based gh CLI wrapper for PR management
├── StatusDetection/    # Hook server (port 47437) + terminal buffer scanner
├── Theme/              # AppTheme, ChromePalette, TerminalPalette
├── Views/              # All SwiftUI views (sidebar, session detail, PRs)
└── CGhosttyVT/         # libghostty wrapper (standby — awaiting SIMD support)
```

### Key Patterns

| Pattern | Where | Why |
|---------|-------|-----|
| `@Observable` | RunwayStore | Single source of truth for all app state |
| Swift Actors | WorktreeManager, PRManager | Thread-safe CLI operations without locks |
| TerminalProvider protocol | Terminal target | Abstracts backend (SwiftTerm now, libghostty later) |
| GRDB typed records | Persistence | Type-safe SQLite with migrations |
| Environment injection | Theme | `@Environment(\.theme)` for consistent theming |

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.4.0+ | SQLite ORM with typed records and migrations |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.2.0+ | Terminal emulator (AppKit NSView) |
| [libghostty-spm](https://github.com/nicholsonm/libghostty-spm) | 1.0.0+ | GPU-accelerated terminal (on standby) |

## Configuration

Runway stores its state in `~/.runway/`:

```
~/.runway/
├── state.db        # SQLite database (sessions, projects)
├── themes/         # Custom theme files (planned)
└── logs/           # Application logs (planned)
```

### Claude Code Integration

Runway auto-injects hooks into `~/.claude/settings.json` on launch, subscribing to:

- `SessionStart` — marks session as running
- `UserPromptSubmit` — marks session as running
- `PermissionRequest` — marks session as waiting
- `Notification` — permission prompts and elicitation dialogs
- `Stop` / `SessionEnd` — marks session as idle

Hook events are sent to `http://127.0.0.1:47437/hooks` with the session ID in a header.

## Development Status

Runway is in **active early development**. Core session and terminal management works. See [TODO.md](TODO.md) for the full roadmap.

### CI & Testing

- **118 tests** across 7 test targets (Models, Persistence, StatusDetection, Theme, Terminal, GitOperations, GitHubOperations)
- **GitHub Actions CI** runs on every PR: build, test, SwiftLint, swift-format
- **Branch protection** on `master` — CI must pass before merging
- **SwiftLint** enforces safety (no force casts/unwraps/try) and style
- **swift-format** enforces consistent formatting

### What Works

- Session creation with git worktree isolation
- Embedded terminal with SwiftTerm
- Multi-tab terminals per session
- Session persistence across app restarts
- Live status detection (hook server + buffer scanning)
- GitHub PR dashboard (fetch, filter, detail view, approve, comment)
- Permission mode picker (Default / Accept Edits / Bypass All)
- Default branch auto-detection (`main` vs `master`)
- Theme system with 6 built-in themes
- Font customization (family + size, Nerd Font default)
- Claude Code hook injection
- Project registration and organization

### What's In Progress

- Session context menus (restart, delete, rename)
- Split-pane terminal layouts
- Proper `.app` bundle with icon and entitlements
- GitHub Issues integration (replacing removed Todo feature)

## License

MIT
