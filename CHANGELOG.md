# Changelog

All notable changes to Runway are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.1] — 2026-04-07

### Added

- **Resizable divider** — Drag to resize the list and detail panels in the main window ([#139](https://github.com/sjoeboo/runway/pull/139))

### Fixed

- **Sidebar project navigation** — Reliably opens the project page when clicking a project in the sidebar ([#138](https://github.com/sjoeboo/runway/pull/138))
- **Monorepo PR cross-contamination** — Provisioning sessions are now skipped during PR linking, preventing incorrect PR associations in monorepo setups ([#140](https://github.com/sjoeboo/runway/pull/140))

### Maintenance

- Refreshed README and CLAUDE.md for v0.1.0 ([#137](https://github.com/sjoeboo/runway/pull/137))

[0.1.1]: https://github.com/sjoeboo/runway/compare/v0.1.0...v0.1.1

## [0.1.0] — 2026-04-07

### Added

- **PR grouping pipeline with merge status badges** — PRs are now grouped by status with visual merge-state badges in the dashboard ([#135](https://github.com/sjoeboo/runway/pull/135))
- **GitHub Issue detail view** — Full-parity detail drawer for GitHub Issues, matching the PR detail experience ([#134](https://github.com/sjoeboo/runway/pull/134))
- **Automerge toggle** — Enable or disable GitHub automerge directly from the PR detail drawer ([#133](https://github.com/sjoeboo/runway/pull/133))
- **Faster session PR detection** — PR status now polls independently per session, reducing latency for active worktrees ([#129](https://github.com/sjoeboo/runway/pull/129))
- **Improved menubar** — New icons, colored status badges, and refined window styling ([#128](https://github.com/sjoeboo/runway/pull/128))
- **CI checks tab** — Detailed GitHub Actions / CI check results shown in the PR detail drawer ([#127](https://github.com/sjoeboo/runway/pull/127))

### Fixed

- **Terminal attach race** — Resolved a race condition when attaching terminals to monorepo worktree sessions ([#132](https://github.com/sjoeboo/runway/pull/132))
- **Shift+Enter in tmux** — Enabled extended-keys in tmux configuration so Shift+Enter works correctly in Claude Code sessions ([#131](https://github.com/sjoeboo/runway/pull/131))
- **Image drag-and-drop** — Terminal sessions now accept dragged images and screenshots ([#130](https://github.com/sjoeboo/runway/pull/130))

### Maintenance

- Updated GitHub Actions workflows ([#126](https://github.com/sjoeboo/runway/pull/126))
- Updated SPM dependencies ([#125](https://github.com/sjoeboo/runway/pull/125))

[0.1.0]: https://github.com/sjoeboo/runway/compare/v0.0.15...v0.1.0
