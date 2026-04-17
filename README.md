<p align="center">
  <img src="images/Hero.png" alt="Runway — AI coding agent session manager for macOS" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/SwiftUI-blue?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
</p>

---

**Runway** is a native macOS command center for AI coding agents. One window replaces the terminal tabs, browser windows, and git commands you juggle when working with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and similar tools.

## Highlights

| | Feature | What you get |
|---|---------|-------------|
| **🖥** | **Embedded terminals** | Full terminal emulator with ANSI truecolor, search (`Cmd+F`), drag-and-drop, and font customization |
| **🌿** | **Git worktree isolation** | Every session gets its own branch and working copy — `main` stays clean |
| **🔍** | **Live status detection** | See at a glance whether each agent is running, waiting, idle, or errored |
| **📋** | **GitHub PR dashboard** | Review, approve, merge, request changes, toggle automerge, and view CI checks — all without leaving the app |
| **📌** | **GitHub Issues** | View, create, and manage issues per project |
| **🔔** | **Notifications** | Native macOS notifications for permission requests and session completion, with enable/disable toggle in Settings |
| **🎨** | **Theme system** | 23 built-in themes + user-installable custom themes from `~/.runway/themes/` |
| **📂** | **Project organization** | Group sessions by project with per-project settings for theme, permissions, and branch prefix |
| **⌨️** | **Keyboard-driven** | 15 shortcuts — `Cmd+K` search, `Cmd+N` new session, `Cmd+D` split pane, `Cmd+3` changes, and more |

## Install

### Download (recommended)

Grab the latest **Runway.dmg** from the [Releases](https://github.com/sjoeboo/runway/releases) page, open the DMG, and drag Runway to Applications.

> Runway includes Sparkle for automatic updates — you'll be notified when new versions are available.

### Build from source

**Prerequisites:** macOS 14+, Swift 6.0+ (Xcode 16+), Git, [GitHub CLI](https://cli.github.com/) (`gh`)

```bash
git clone https://github.com/sjoeboo/runway.git
cd runway
swift build
swift run Runway
```

To build a proper `.app` bundle:

```bash
make package        # → build/Runway.app (release universal binary)
make dmg            # → build/Runway.dmg (requires package first)
make dist           # → package + DMG in one step
```

### Development setup

```bash
make setup          # installs swiftlint, swift-format, and git pre-commit hook
make check          # build + test + lint + format-check (mirrors CI)
make fix            # auto-fix lint and format issues
make precommit      # fix, then verify everything passes
```

## Features

### Session Management

Create named sessions tied to projects. Each session launches a terminal running your chosen agent (Claude Code, Gemini CLI, Codex, shell, or custom command) in an isolated git worktree.

- **Auto-branch naming** — session name suggests a branch using the project's configured prefix (default: `feature/`)
- **Per-project branch prefixes** — configure `feature/`, `fix/`, `yourname/`, or any prefix in Project Settings
- **Worktree isolation** — each session works in `.worktrees/{branch}`, keeping `main` clean
- **Worktree cleanup** — delete confirmation offers "Delete Session Only" or "Delete Session & Worktree" (removes branch too)
- **Orphan worktree cleanup** — on startup, worktrees with no matching session are automatically pruned; merged branches are deleted, unmerged branches preserved
- **PR Review mode** — dedicated "PR Review" tab in the new session dialog (`Cmd+Shift+R`) creates a review session for any PR number
- **Changes sidebar** — toggle with `Cmd+3` to see all changed files in the session worktree, with tabbed diff viewer (diffs open as tabs alongside the terminal) and "vs Main" / "Uncommitted" modes
- **Default branch detection** — auto-detects `main` vs `master` via `git symbolic-ref`
- **Permission modes** — choose Default, Accept Edits, or Bypass All per session (with color-coded badges)
- **Multiple terminal tabs** — add shell tabs alongside your main agent session
- **Session persistence** — sessions survive app restarts via SQLite + tmux
- **Session templates** — save common configurations (tool, permissions, prompt) and reuse them from the "From Template" tab in the New Session dialog
- **Issue-linked sessions** — start sessions directly from GitHub Issues with auto-generated branch names
- **Activity log** — per-session event timeline with issue badge and activity subtitle in sidebar
- **Deep linking** — `runway://` URL scheme for opening sessions, PRs, and creating new sessions
- **Multi-agent support** — first-class support for Claude Code, Gemini CLI, and Codex with agent-specific permission modes, hook injection, and optional Happy wrapper for mobile/remote access
- **Session restart/resume** — restart stopped sessions from the sidebar context menu, resuming from where they left off
- **Fork session** — create a new session forked from an existing one, inheriting configuration and branch
- **Session search** — `Cmd+K` filters the sidebar by session name, branch, or project name
- **Saved prompts** — save and reuse frequently-sent prompts in the send bar, with global and per-project scope
- **Transcript viewer** — browse session conversation transcripts in a read-only JSONL viewer
- **Commit history** — view branch commit history from the session header with rollback capability

### Live Status Detection

Runway knows what your agent is doing. Two detection paths work together:

| Method | How it works |
|--------|-------------|
| **HTTP Hooks** | Claude Code sends lifecycle events (session start, permission request, stop) to Runway's hook server |
| **Buffer Polling** | Every 3 seconds, terminal buffer content is scanned for 90+ patterns — spinners, prompts, permission dialogs, idle indicators |
| **Agent Profiles** | Configurable detection profiles (Claude, Gemini CLI, Codex, Shell) with profile-based pattern matching |

Hook injection is automatic — Runway writes to `~/.claude/settings.json` on every launch with the current ephemeral port.

Status shows in the sidebar as colored indicators: green (running), yellow (waiting for permission), hollow (idle), spinner (starting), red (error), dim (stopped). The toolbar also surfaces live per-status counts across all sessions for at-a-glance monitoring.

### Terminal

- **Embedded SwiftTerm** with full ANSI 256-color and truecolor support
- **Cmd+F search** — find text in terminal history with next/previous navigation
- **Cmd+Shift+X send bar** — type and send prompts without switching focus
- **Shift+Enter** — insert newline (recognized by Claude Code)
- **Tmux pane splitting** — split panes via toolbar buttons or `Cmd+D` (right) / `Cmd+Shift+D` (down)
- **Drag and drop** — drop files and images into the terminal to insert their paths
- **Font customization** — choose font family (grouped: Nerd Fonts, Monospaced, All) and size with live preview

### GitHub PR Dashboard

Built-in PR management powered by `gh` CLI:

- **Three views**: All PRs, Mine, Review Requested
- **Sortable columns** — click column headers to sort by title, status, author, date, or review state
- **Filter bar** — quick text filtering across PR titles, branches, and authors
- **Native Table view** — macOS-native table layout with resizable columns
- **PR grouping** by status with merge-state badges
- **Detail drawer** with Overview, Diff, and Conversation tabs (`Ctrl+1/2/3`)
- **Actions**: approve, request changes, comment, merge (squash/merge/rebase), close, toggle draft, toggle automerge
- **CI checks tab** — view GitHub Actions / CI check results per PR
- **Visual status**: check results (passed/failed/pending), review decision badges, diff stats (+/-)
- **Sidebar comment indicators**: session rows show a badge when reviewers leave new comments since your last push
- **Session linking**: PRs are matched to sessions by worktree branch
- **Send to Session**: navigate to the linked session with the send bar open
- **Inline comment grouping**: comments grouped by file with count badges and send-to-session action
- **Conversation timeline**: reviews and comments interleaved chronologically with colored accents for review decisions
- **GFM markdown rendering**: PR and issue descriptions render full GitHub Flavored Markdown — syntax highlighting, tables, task lists, and more

### GitHub Issues

Per-project issue management:

- **Enable per project** in Project Settings (auto-detects repo via git remote)
- **Issue list** with labels and status
- **Issue detail view** — full-parity detail drawer matching the PR experience, with GFM markdown rendering
- **Create issues** with title, body, and label selection
- **Start Session** from an issue — creates a session linked to the issue with activity tracking
- **Open in browser** for full GitHub UI when needed

### Project Settings

Per-project configuration from the sidebar context menu:

- **Theme override** — use a different theme for specific projects
- **Permission mode default** — set the default for new sessions
- **Branch prefix** — customize auto-generated branch names
- **GitHub integration** — enable issues, auto-detect repository

### Theme System

23 hand-crafted themes with paired light/dark variants:

| Theme | Style |
|-------|-------|
| Tokyo Night Storm / Moon / Night / Day | Dark storm / Dark purple / Dark base / Light |
| Ayu Mirage | Dark, warm amber |
| Catppuccin Mocha / Latte | Dark pastel / Light pastel |
| Dracula / Alucard | Dark purple / Light purple |
| Everforest Dark / Light | Nature green |
| Gruvbox Dark / Light | Warm retro |
| Kanagawa | Dark, wave blue |
| Noctis Azureus / Lux | Dark ocean blue / Warm light |
| Nord | Dark, arctic blue |
| Oasis Lagoon Dark / Light | Ocean blue |
| Rosé Pine / Dawn | Dark muted / Light rosé |
| Solarized Dark / Light | Precision color |

Themes apply to both the app chrome (sidebar, toolbar, status bar) and the terminal (ANSI colors, cursor, selection). System appearance auto-switching is supported with 11 paired theme sets.

**Custom themes**: Drop a JSON theme file into `~/.runway/themes/` and it appears in the theme picker automatically.

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
| `Cmd+Shift+R` | New PR Review session |
| `Cmd+D` | Split terminal pane right |
| `Cmd+Shift+D` | Split terminal pane down |
| `Cmd+3` | Toggle changes sidebar |
| `Shift+Enter` | Newline in terminal |
| `Ctrl+1/2/3` | PR detail: Overview / Diff / Conversation |

## Architecture

Pure SwiftUI app built with Swift Package Manager. 11 focused targets:

```
Sources/
├── App/                # @main entry, RunwayStore, window setup
├── Models/             # Session, Project, PullRequest, HookEvent, GitHubIssue, AgentProfile, SessionEvent, SessionTemplate
├── Persistence/        # GRDB/SQLite (WAL mode, ~/.runway/state.db)
├── Terminal/           # TerminalProvider protocol, PTY + tmux management
├── TerminalView/       # NSViewRepresentable wrapping SwiftTerm, search bar, event monitors
├── GitOperations/      # Actor-based git worktree CLI wrapper
├── GitHubOperations/   # Actor-based gh CLI wrapper (PRs + issues)
├── StatusDetection/    # Hook server + buffer scanner + hook injector
├── Theme/              # AppTheme, ChromePalette, TerminalPalette
├── Views/              # All SwiftUI views
└── CGhosttyVT/         # libghostty wrapper (standby — awaiting SIMD support)
```

### Dependencies

| Package | Purpose |
|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite ORM with typed records and migrations |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator (AppKit NSView) with search API |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Auto-update framework for macOS |

### Key Patterns

| Pattern | Where | Why |
|---------|-------|-----|
| `@Observable` | RunwayStore | Single source of truth for all app state |
| Swift Actors | WorktreeManager, PRManager | Thread-safe CLI operations without locks |
| SidebarActions protocol | ProjectTreeView | Eliminates prop drilling — single protocol replaces 14 callbacks |
| TerminalProvider protocol | Terminal target | Abstracts backend (SwiftTerm now, libghostty later) |
| GRDB typed records | Persistence | Type-safe SQLite with migrations (currently v14) |
| Environment injection | Theme | `@Environment(\.theme)` for consistent theming |

## Configuration

Runway stores its state in `~/.runway/`:

```
~/.runway/
├── state.db        # SQLite database (sessions, projects, PR/issue cache)
├── themes/         # User-installable JSON theme files
└── logs/           # Application logs
```

### Claude Code Integration

Runway auto-injects hooks into `~/.claude/settings.json` on every launch, subscribing to lifecycle events: `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`. Hook injection uses atomic writes (temp file + rename) and skips re-injection when hooks already point to the correct port.

## CI & Testing

- **338 tests** across 8 test targets
- **GitHub Actions CI** on every PR: build, test, SwiftLint, swift-format
- **Branch protection** on `master` — CI must pass before merging
- **Pre-commit hooks** run lint + format checks locally

## Planned

- Multi-session split view / open session in new window
- Menu bar extra for monitoring agent status
- Global activity feed / cross-session dashboard
- Session-to-session tree (parent/child agent visualization)

## License

MIT
