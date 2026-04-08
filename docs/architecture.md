# Runway Architecture Guide

This document explains non-obvious design decisions in Runway. It's intended for contributors who want to understand *why* things work the way they do, not just *what* the code does.

## Module Structure

Runway is built as a collection of Swift Package Manager targets with strict dependency boundaries:

```
App (entry point, RunwayStore)
├── Views (all SwiftUI views)
├── TerminalView (NSViewRepresentable wrapping SwiftTerm)
├── Terminal (PTY + tmux session management)
├── StatusDetection (hook server + buffer polling)
├── GitOperations (worktree management)
├── GitHubOperations (PR + issue management via gh CLI)
├── Persistence (GRDB/SQLite)
├── Models (shared value types)
└── Theme (appearance system)
```

Each target can only depend on targets below it. `Views` does not depend on `App` — it communicates upward through the `SidebarActions` protocol.

## Key Design Decisions

### SidebarActions Protocol

**What:** `Views.SidebarActions` is a protocol that `App.RunwayStore` conforms to. Sidebar views call protocol methods instead of receiving closures.

**Why:** The sidebar view hierarchy is deep: `ProjectTreeView` → section headers → `SessionRowView` → action buttons. Without the protocol, every action would need to be threaded as a closure through 4+ levels of view parameters. Early versions of Runway had 14 separate callback closures threaded through `ProjectTreeView` — each new action added another parameter to every intermediate view.

**How it works:** `ProjectTreeView` declares `let actions: any SidebarActions`. `RunwayStore` conforms to `SidebarActions`. The `App` layer passes `store` as the `actions` parameter. Views in the `Views` module only see the protocol, never the concrete `RunwayStore` type.

### Dual-Path Status Detection

**What:** Session status is detected via two independent channels: HTTP hooks and terminal buffer polling.

**Why:** HTTP hooks are precise and real-time — they fire on exact Claude Code lifecycle events (SessionStart, PermissionRequest, Stop, etc.). But they require Claude Code's cooperation: Runway injects hook configuration into `~/.claude/settings.json`. If the injection fails, Claude Code updates settings and overwrites hooks, or the user runs a non-Claude agent, hooks won't fire. Buffer polling (reading the last 10 lines of terminal output every 3 seconds) is the universal fallback that works with any terminal content.

**Priority:** When a hook event arrives, `lastHookEventTime` records the timestamp. The buffer polling loop (`pollTerminalBuffers`) skips any session with a hook event in the last 10 seconds (`hookPriorityCooldown`). This prevents the two paths from fighting: hooks are authoritative when available, polling fills gaps.

### HookInjector Advisory Locking

**What:** `HookInjector` acquires an `flock()` advisory lock on `settings.json.lock` before reading or writing `~/.claude/settings.json`.

**Why:** Both Runway and Claude Code read and write `settings.json`. Without locking, a race condition exists: Runway reads the file, Claude Code writes an update, Runway writes back its version — Claude Code's changes are lost. The advisory lock serializes access. Claude Code's own hook system also respects file locks.

### TerminalSessionCache (LRU)

**What:** `TerminalSessionCache` keeps terminal `NSView` instances alive in memory, evicting least-recently-used entries when the cache exceeds its capacity.

**Why:** SwiftTerm terminal views hold their scrollback buffer as *view state*, not model state. When SwiftUI re-creates a view during navigation (e.g., switching between sessions in the sidebar), a new SwiftTerm view starts empty — all scrollback is lost. The cache preserves terminal views across navigation so users don't lose their history. The LRU policy bounds memory usage for users with many sessions.

### Tool.custom Extensibility

**What:** The `Tool` enum has a `.custom(String)` case alongside `.claude` and `.shell`.

**Why:** This is the extension point for non-Claude agents. While the UI currently only exposes Claude and Shell, the data model and persistence layer support arbitrary tool strings. The `StatusDetector` has a `detectGeneric` fallback for custom tools. See issue #226 for the full Agent Profile System proposal.

## Persistence

Runway uses GRDB (SQLite ORM) with numbered migrations (`v1` through current). The database lives at `~/.runway/state.db`. Migrations are additive — each adds tables or columns but never drops existing ones.

**In-memory mode:** `Database(inMemory: true)` is used in tests. All persistence tests run against in-memory databases for speed and isolation.

## Status Detection Event Types

| Event | Source | Session Status |
|-------|--------|---------------|
| `SessionStart` | Hook | `.running` |
| `UserPromptSubmit` | Hook | `.running` |
| `PermissionRequest` | Hook | `.waiting` |
| `Stop` | Hook | `.idle` |
| `SessionEnd` | Hook | `.stopped` |
| `Notification` | Hook | (no change) |
| Spinner patterns | Buffer poll | `.running` |
| Permission dialog | Buffer poll | `.waiting` |
| Shell prompt | Buffer poll | `.idle` |
