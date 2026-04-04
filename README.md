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
- **GitHub PR dashboard** — review, approve, merge, request changes, and comment without leaving the app
- **Project organization** — group sessions by project, configure per-project settings
- **GitHub Issues** — view, create, and manage issues per project
- **Theme system** — 6 built-in themes (Tokyo Night, Ayu Mirage, Everforest, Oasis Lagoon) applied to both UI and terminal
- **Terminal search** — `Cmd+F` find-in-terminal powered by SwiftTerm
- **Session search** — `Cmd+K` to filter sessions and projects by name or branch
- **Send text bar** — `Cmd+Shift+X` to send prompts to a session without switching focus

## Quick Start

### Prerequisites

- macOS 14 (Sonoma) or later
- [Swift 6.0+](https://www.swift.org/install/) (bundled with Xcode 16+)
- [GitHub CLI](https://cli.github.com/) (`gh`) for PR and issue features
- Git (bundled with Xcode Command Line Tools)
- tmux (recommended — enables session persistence across app restarts)

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

- **Auto-branch naming** — session name automatically suggests a branch using the project's configured prefix (default: `feature/`)
- **Per-project branch prefixes** — configure `feature/`, `fix/`, `yourname/`, or any prefix in Project Settings
- **Worktree isolation** — each session works in `.worktrees/{branch}`, keeping `main` clean
- **Worktree cleanup** — delete confirmation offers "Delete Session Only" or "Delete Session & Worktree" (removes branch too)
- **Default branch detection** — auto-detects `main` vs `master` via `git symbolic-ref`
- **Permission modes** — choose Default, Accept Edits, or Bypass All per session (with color-coded badges)
- **Multiple terminal tabs** — add shell tabs alongside your main agent session
- **Session persistence** — sessions survive app restarts via SQLite + tmux
- **Session search** — `Cmd+K` filters the sidebar by session name, branch, or project name

### Live Status Detection

Runway knows what your agent is doing. Two detection paths work together:

| Method | How it works |
|--------|-------------|
| **HTTP Hooks** | Claude Code sends lifecycle events (session start, permission request, stop) to Runway's hook server |
| **Buffer Polling** | Every 3 seconds, terminal buffer content is scanned for 90+ patterns — spinners, prompts, permission dialogs, idle indicators |

Hook injection is automatic — Runway writes to `~/.claude/settings.json` on every launch with the current port (force-updated to handle ephemeral ports).

Status shows in the sidebar as colored indicators:
- Green circle = running
- Yellow half-circle = waiting for permission
- Hollow circle = idle
- Spinner = starting
- Red X = error
- Dim dot = stopped

### Terminal Features

- **Embedded SwiftTerm** terminal with full ANSI 256-color and truecolor support
- **Cmd+F search** — find text in terminal history with next/previous navigation
- **Cmd+Shift+X send bar** — type and send prompts to the terminal without switching focus (useful while viewing diffs or PRs)
- **Shift+Enter** — sends CSI u escape sequence recognized by Claude Code as "insert newline"
- **Native text selection** — mouse events are intercepted to ensure copy/paste always works
- **Drag and drop** — drop files into the terminal to insert their paths
- **Font customization** — choose font family (grouped: Nerd Fonts, Monospaced, All) and size with live preview

### GitHub PR Dashboard

Built-in PR management powered by `gh` CLI:

- **Three views**: All PRs, Mine, Review Requested
- **Detail drawer** with Overview, Diff, and Conversation tabs (`Ctrl+1/2/3` to switch)
- **Actions**: approve, request changes, comment, merge (squash/merge/rebase), toggle draft
- **Visual status**: check results (passed/failed/pending), review decision badges, diff stats (+/-)
- **PR enrichment**: background-fetches detail data with bounded concurrency; unenriched PRs show loading spinners
- **Session linking**: PRs are matched to sessions by worktree branch
- **Send to Session**: button in PR detail navigates to the linked session with the send bar open
- **Conversation timeline**: reviews and comments interleaved by date with colored left-border accents indicating review decisions

### GitHub Issues

Per-project issue management:

- **Enable per project** in Project Settings (auto-detects repo via git remote)
- **Issue list** with labels and status
- **Create issues** with title, body, and label selection
- **Open in browser** for full GitHub UI when needed

### Project Settings

Per-project configuration accessible from the sidebar context menu:

- **Theme override** — use a different theme for specific projects
- **Permission mode default** — set the default permission mode for new sessions
- **Branch prefix** — customize auto-generated branch names (e.g., `fix/`, `release/`, `yourname/`)
- **GitHub integration** — enable issues, auto-detect repository

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
| `Cmd+1` | Switch to Sessions view |
| `Cmd+2` | Switch to Pull Requests view |
| `Cmd+N` | New session |
| `Cmd+Shift+P` | New project |
| `Cmd+K` | Focus sidebar search |
| `Cmd+F` | Find in terminal |
| `Cmd+Shift+X` | Toggle send-to-session bar |
| `Shift+Enter` | Newline in terminal (instead of submit) |
| `Ctrl+1` | PR detail: Overview tab |
| `Ctrl+2` | PR detail: Diff tab |
| `Ctrl+3` | PR detail: Conversation tab |

### Toast Notifications

- **Success/info** toasts auto-dismiss after 3 seconds
- **Error** toasts persist until dismissed (click X) — text is selectable for copying

## Architecture

Runway is a pure SwiftUI app built with Swift Package Manager. The codebase is split into 11 focused targets:

```
Sources/
├── App/                # @main entry, RunwayStore, window setup
├── Models/             # Session, Project, PullRequest, HookEvent
├── Persistence/        # GRDB/SQLite database (WAL mode, ~/.runway/state.db)
├── Terminal/           # TerminalProvider protocol, PTY process management
├── TerminalView/       # NSViewRepresentable wrapping SwiftTerm, search bar, event monitors
├── GitOperations/      # Actor-based git worktree CLI wrapper
├── GitHubOperations/   # Actor-based gh CLI wrapper for PR and issue management
├── StatusDetection/    # Hook server + terminal buffer scanner + hook injector
├── Theme/              # AppTheme, ChromePalette, TerminalPalette
├── Views/              # All SwiftUI views (sidebar, session detail, PRs, settings)
└── CGhosttyVT/         # libghostty wrapper (standby — awaiting SIMD support)
```

### Key Patterns

| Pattern | Where | Why |
|---------|-------|-----|
| `@Observable` | RunwayStore | Single source of truth for all app state |
| Swift Actors | WorktreeManager, PRManager | Thread-safe CLI operations without locks |
| SidebarActions protocol | ProjectTreeView | Eliminates prop drilling — single protocol replaces 14 callbacks |
| TerminalProvider protocol | Terminal target | Abstracts backend (SwiftTerm now, libghostty later) |
| GRDB typed records | Persistence | Type-safe SQLite with migrations (currently v8) |
| Environment injection | Theme | `@Environment(\.theme)` for consistent theming |

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.4.0+ | SQLite ORM with typed records and migrations |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.2.0+ | Terminal emulator (AppKit NSView) with search API |
| [libghostty-spm](https://github.com/nicholsonm/libghostty-spm) | 1.0.0+ | GPU-accelerated terminal (on standby) |

## Configuration

Runway stores its state in `~/.runway/`:

```
~/.runway/
├── state.db        # SQLite database (sessions, projects, PR/issue cache)
├── themes/         # Custom theme files (planned)
└── logs/           # Application logs (planned)
```

### Claude Code Integration

Runway auto-injects hooks into `~/.claude/settings.json` on every launch (force-updated to handle ephemeral ports), subscribing to:

- `SessionStart` — marks session as running
- `UserPromptSubmit` — marks session as running
- `PermissionRequest` — marks session as waiting
- `Notification` — permission prompts and elicitation dialogs
- `Stop` — marks session as idle
- `SessionEnd` — marks session as stopped

Hook injection uses atomic writes (temp file + rename) and skips re-injection only when the existing hooks already point to the correct port.

## Development Status

Runway is in **active development**. Core features are complete and stable.

### CI & Testing

- **118 tests** across 7 test targets (Models, Persistence, StatusDetection, Theme, Terminal, GitOperations, GitHubOperations)
- **GitHub Actions CI** runs on every PR: build, test, SwiftLint, swift-format
- **Branch protection** on `master` — CI must pass before merging
- **SwiftLint** enforces safety (no force casts/unwraps/try) and style
- **swift-format** enforces consistent formatting
- **Pre-commit hooks** run lint + format checks locally

### What Works

- Session creation with git worktree isolation and cleanup
- Embedded terminal with SwiftTerm (multi-tab, search, send bar)
- Session persistence across app restarts via tmux + SQLite
- Live status detection (hook server + buffer polling)
- GitHub PR dashboard (fetch, filter, detail view, approve, comment, merge, request changes, toggle draft)
- PR-to-session linking with "Send to Session" workflow
- GitHub Issues per project (list, create, labels)
- Permission mode picker with color-coded security badges
- Default branch auto-detection (`main` vs `master`)
- Theme system with 6 built-in themes + system appearance auto-switching
- Font customization (family + size, grouped picker, Nerd Font default)
- Claude Code hook injection (auto-updated on every launch)
- Project organization with per-project settings (theme, permissions, branch prefix)
- Sidebar search/filter (`Cmd+K`)
- Comprehensive keyboard shortcuts (11 shortcuts across all workflows)
- Persistent error toasts with dismiss control

### Planned

- Multi-session split view / open session in new window
- Menu bar extra for monitoring agent status
- Session templates (save common configurations)
- Global activity feed / cross-session dashboard
- Session-to-session tree (parent/child agent visualization)
- Proper `.app` bundle with icon and entitlements

## License

MIT
