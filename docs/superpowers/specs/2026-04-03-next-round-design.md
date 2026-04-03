# Next Round: PR Actions, Polish & Terminal UX

**Date:** 2026-04-03
**Branch:** `feature-next-round`
**Scope:** 7 features across settings, PR management, sidebar UX, layout persistence, and terminal interaction

---

## 1. Global Default Permission Mode

**Goal:** Let users set their preferred permission mode once, so every new session pre-selects it.

**Changes:**

- **SettingsPlaceholder.swift** — Add segmented picker to the General tab with the three modes (Default, Accept Edits, Bypass). Stored as `@AppStorage("defaultPermissionMode")` using `Session.PermissionMode` raw string values.
- **NewSessionDialog.swift** — Read `@AppStorage("defaultPermissionMode")` as the initial value for the permission mode picker. User can still override per-session.

**No model changes needed** — `Session.PermissionMode` already has string raw values.

---

## 2. ANSI Color Palette Sync

**Goal:** Ensure terminal ANSI colors match the active theme, and update live on theme change.

**Changes:**

- **TerminalPane.swift** — Verify that `theme.terminal.ansi[0..15]` is applied to SwiftTerm. The exploration confirmed foreground/background/selection are wired, but the 16 ANSI palette colors may not be. Map them via SwiftTerm's color installation API (`installColors` or equivalent).
- **Live update** — When `@Environment(\.theme)` changes, reapply the full palette (foreground, background, selection, and all 16 ANSI colors) to the running terminal without restarting the PTY.

---

## 3. PR Actions

**Goal:** Full PR action support — approve, request changes, comment, merge, and draft toggle.

### PRManager Additions

| Method | CLI Command |
|--------|-------------|
| `requestChanges(repo:number:body:host:)` | `gh pr review {number} --repo {repo} --request-changes --body {body}` |
| `merge(repo:number:strategy:host:)` | `gh pr merge {number} --repo {repo} --squash` (default). `--merge` or `--rebase` as overrides. |
| `toggleDraft(repo:number:isDraft:host:)` | `gh pr ready {number}` to mark ready. `gh api graphql` with `convertPullRequestToDraft` mutation to convert to draft (no CLI flag for this direction). |

Existing: `approve`, `comment`, `openInBrowser` — no changes needed.

### Action Bar UI

Horizontal button bar at the top of the PR detail panel:

- **Contextual visibility based on PR state:**
  - Draft PR → "Mark Ready" button visible
  - Ready PR → "Convert to Draft" visible
  - Approved/mergeable → "Merge" button enabled with small chevron dropdown for strategy override (squash default, merge, rebase)
  - Always visible: "Approve", "Request Changes", "Comment"
- **Approve / Request Changes** — tapping opens an optional text field for comment body, then submits
- **Comment** — opens a text input popover/sheet
- **Merge** — shows a confirmation alert (destructive action, includes strategy selection)

### State Refresh

After any action completes, re-fetch PR detail so the UI reflects the updated state (review decision, draft status, merge status).

---

## 4. Auto-Detect PR for Sessions

**Goal:** Automatically link sessions to their PRs and make the link visible and actionable.

### Trigger Points

1. On session creation (after worktree is set up)
2. During periodic `enrichPRs()` refresh (already exists in RunwayStore)
3. On manual refresh

### Session Row Enhancement

When `sessionPRs[session.id]` exists, show a small PR badge in `SessionRowView` — PR number + status icon (draft, open, merged, checks status). Clicking the badge navigates to the PR in the PR dashboard or opens a detail drawer.

### Context Menu Integration

Add "View PR" and "Open PR in Browser" items to the session context menu (enabled when a linked PR exists). See Section 5.

---

## 5. Sidebar Context Menus + Drag Reorder

**Goal:** Full right-click menus on sessions and projects, plus drag-to-reorder for both.

### Session Context Menu

```
Rename Session
Copy Worktree Path
Copy Branch Name
Open in Finder
Open in Terminal
─────────────────
View PR              (if linked)
Open PR in Browser   (if linked)
─────────────────
Restart Session
Delete Session       (destructive)
```

### Project Context Menu

```
Rename Project
Copy Path
Open in Finder
─────────────────
Remove Project       (destructive — removes from Runway, not disk)
```

### Drag Reorder

- **GRDB migration** — add `sortOrder: Int` column to both `Session` and `Project` tables. Default: `max(existing) + 1` on creation.
- **ForEach + .onMove** — sessions reorder within their project group, projects reorder globally.
- On move: update `sortOrder` for affected rows, persist to GRDB immediately.
- Sessions use `ForEach` inside each `DisclosureGroup` for per-project reorder. Projects use a top-level `ForEach`.

### Implementation Notes

- Copy actions use `NSPasteboard.general`
- Open in Finder uses `NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:)`
- Open in Terminal uses `open -a Terminal <path>` (or user's default terminal)
- Rename uses inline `.textFieldStyle` edit on the row

---

## 6. Responsive Layout with Persisted Widths

**Goal:** Remember sidebar and split view widths across app restarts.

### @AppStorage Keys

| Key | Default | Purpose |
|-----|---------|---------|
| `"sidebarWidth"` | 280 | Sidebar column width |
| `"prListWidth"` | 380 | PR list panel width in PR dashboard |

### Implementation

- **Sidebar** — use `.navigationSplitViewColumnWidth(min: 200, ideal: sidebarWidth, max: 500)` on the sidebar column. The `ideal` tracks the stored value.
- **Width observation** — `NavigationSplitView` doesn't provide a divider-drag callback. Use a `GeometryReader` inside the sidebar to observe actual width and write back to `@AppStorage` with debounce (avoid writing on every frame).
- **PR list/detail split** — same pattern. If this is a custom split (not `NavigationSplitView`), bind the divider position directly to `@AppStorage("prListWidth")`.

### Fallback

If `NavigationSplitView` doesn't reliably honor `ideal` width or the `GeometryReader` approach proves unreliable, replace with a custom `HSplitView` that directly binds divider position to `@AppStorage`. This gives full control at the cost of losing the built-in sidebar toggle animation.

---

## 7. Terminal Selection, Copy/Paste, and Drag-Drop

**Goal:** Make the terminal behave like a real terminal — select text, copy/paste, drag-drop files.

### Selection & Copy/Paste

SwiftTerm's `TerminalView` supports mouse-based text selection natively. The likely issue is that the `NSViewRepresentable` wrapper (`TerminalPane`) or the global `TerminalKeyEventMonitor` is intercepting mouse events.

**Investigation steps:**
1. Check if `TerminalPane`'s `NSViewRepresentable` is eating mouse events (missing `hitTest`, overlay views blocking clicks)
2. Check if `TerminalKeyEventMonitor`'s global event monitor is interfering with click-drag
3. Check if any SwiftUI overlay or gesture modifier is capturing mouse input before it reaches the NSView

**Expected behavior once fixed:**
- Click-drag selects text
- Double-click selects word
- Triple-click selects line
- Cmd+C copies selection (when selection exists; otherwise sends SIGINT as usual)
- Cmd+V pastes from clipboard
- Right-click shows context menu with Copy/Paste

### Drag & Drop

- Register the `TerminalPane` NSView for drag types: `.fileURL`, `.png`, `.tiff`
- **File drop** — insert the escaped file path at cursor position (standard terminal behavior: space-escaped, e.g., `/path/to/my\ file.txt`)
- **Image drop** — insert the file path (same as file drop — terminals don't inline images)
- Implementation via `registerForDraggedTypes` on the SwiftTerm view and `performDragOperation` to extract paths and write to the PTY

### Priority Note

This is the highest-impact UX fix in this round. A terminal that doesn't support text selection feels fundamentally broken.

---

## Non-Goals

- libghostty integration (still blocked on SIMD)
- .app bundle / CI / GoReleaser (architecture debt, separate effort)
- SendTextBar (dropped)
- Window title (already implemented)

## Dependencies

- Features 1, 2, 6, 7 are fully independent
- Feature 3 (PR actions) is independent but enhances Feature 4
- Feature 4 (auto-detect PR) depends on Feature 3 for the action bar to be useful in the session context
- Feature 5 (context menus) includes items from Feature 4 (View PR, Open PR in Browser)
