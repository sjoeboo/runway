# Contributing to Runway

Thank you for your interest in contributing to Runway! This guide will help you get started.

## Development Setup

**Requirements:**
- macOS 14.0+
- Xcode 16.0+ (with Swift 6.0+)
- Git

**Quick start:**

```bash
# Clone the repo
git clone https://github.com/sjoeboo/runway.git
cd runway

# Install development tools (swiftlint, swift-format, git pre-commit hook)
make setup

# Build
swift build

# Run tests
swift test

# Run the app
swift run Runway
```

## Development Workflow

### Building and Testing

| Command | Purpose |
|---------|---------|
| `swift build` | Build all targets |
| `swift test` | Run all tests (~180 tests across 8 targets) |
| `swift test --filter <TargetName>` | Run a specific test target |
| `make check` | Build + test + lint + format-check (mirrors CI) |
| `make fix` | Auto-fix lint and format issues |
| `make precommit` | Fix, then verify everything passes |

### Test Targets

| Target | What it tests |
|--------|--------------|
| `ModelsTests` | Session, Project, PullRequest, HookEvent value types |
| `PersistenceTests` | SQLite database operations (uses in-memory DB) |
| `StatusDetectionTests` | Hook server, hook injector, status detection patterns |
| `GitOperationsTests` | Worktree management (creates real temp git repos) |
| `GitHubOperationsTests` | PR and issue manager smoke tests |
| `TerminalTests` | Terminal config, tmux session management |
| `ThemeTests` | Theme manager, built-in theme validation |
| `ViewsTests` | PR grouping logic |

### Testing Framework

Runway uses **Swift Testing** (not XCTest). Tests are written as free functions with the `@Test` attribute:

```swift
import Testing
@testable import Models

@Test func sessionIDGeneration() {
    let session = Session(title: "Test", path: "/tmp")
    #expect(session.id.hasPrefix("id-"))
}
```

Key patterns:
- `#expect(condition)` for assertions
- `try #require(optional)` for unwrapping (fails test if nil)
- `async throws` for actor/async tests
- No mocks — tests use real instances with temp directories or in-memory databases

## Making Changes

1. **Fork and branch** — Create a feature branch from `master`
2. **Make your changes** — Follow existing code patterns
3. **Test** — Run `make check` to mirror CI
4. **Commit** — Write clear commit messages explaining *why*
5. **Open a PR** — Fill out the PR template; link any related issues

### Code Style

- **Linting**: SwiftLint with strict mode
- **Formatting**: swift-format (auto-enforced by CI)
- Run `make fix` to auto-fix both before committing

### Branching

- `master` is the main branch
- Feature branches: `feature/description` or `fix/description`
- CI must pass before merge

## Architecture Overview

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation, including non-obvious design decisions and their rationale.

## Packaging

```bash
make package    # Build release universal .app bundle
make dmg        # Create DMG installer
make dist       # Full distribution build (package + DMG)
```

## Getting Help

- Open an issue for bugs or feature requests
- Use the issue templates for structured reports
