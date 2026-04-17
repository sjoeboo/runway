# PR Assignment — Design

**Date:** 2026-04-17
**Branch:** `feature-pr-assign`
**Status:** Draft

## Problem

Runway's PR view today lets you approve, comment, request changes, merge, toggle draft, and close a pull request. It does not let you manage **assignees** — neither assigning yourself to take ownership of a PR nor assigning a repo collaborator. GitHub treats assignment as an independent dimension from authorship and review requests: a PR you authored is not automatically assigned to you, and you may be assigned to a PR you are neither reviewing nor authoring. Users who rely on the "assigned to me" lens to triage work currently have to leave Runway and open the PR page in a browser.

## Goal

Add first-class assignee support to the PR surface:

- See who is currently assigned to a PR at a glance (drawer row + dashboard card).
- Assign or unassign yourself with one click.
- Assign or unassign any repo collaborator via a searchable picker.
- Surface PRs assigned to you as a dedicated tab in the dashboard.

## Non-Goals

- Dashboard right-click "Assign to me" quick action (deferred — can be added if frequently needed).
- Fetching and rendering GitHub avatar images. Initials in a colored circle are used instead. Deferred until real avatars become worth the network cost and image-caching complexity.
- Suggesting assignees from outside the repo collaborator list (code owners, recent contributors, Copilot suggestions).
- Persisting assignees in SQLite across launches. Assignees populate on the first enrichment after launch, matching how `checks` already behaves.
- Bulk assign across multiple PRs.

## Design

### Architecture

The feature uses the existing three-layer PR architecture. No new layers are introduced.

```
PRDetailDrawer (View)           → new AssigneesRow + popover-hosted AssigneePickerView
PRDashboardView (View)          → new "Assigned" tab + avatar stack on card footer
PRCoordinator (@Observable)     → orchestrates assign/unassign, caches collaborators
PRManager (actor)               → shells out to `gh` for assignee + collaborator ops
```

Four new `gh` operations wrap into `PRManager`:

| Operation | Command | Cache |
|-----------|---------|-------|
| `assign(repo, number, logins)` | `gh pr edit <n> --add-assignee <login,...>` | — |
| `unassign(repo, number, logins)` | `gh pr edit <n> --remove-assignee <login,...>` | — |
| `collaborators(repo)` | `gh api repos/<repo>/collaborators --paginate` | per-repo, 10-min TTL |
| `whoami(host)` | `gh api user -q .login` | per-host, indefinite |

Existing `enrichChecks` and `fetchDetail` calls learn a new `assignees` JSON field — no extra subprocesses for list display. `fetchAllPRs` fires three parallel searches (Mine, ReviewRequested, Assigned) instead of two, merging `origin: Set<PROrigin>` with the existing dedup logic.

### Data Model

**`PullRequest` (`Sources/Models/PullRequest.swift`)** — one new field:

```swift
public var assignees: [String] = []   // GitHub logins
```

Represented as `[String]` rather than a struct: we only need the login for API calls and to derive initials for display. Avoids a data-type ripple and keeps `Codable` round-trips simple.

**`PROrigin`** — one new case:

```swift
public enum PROrigin: String, Codable, Sendable, Hashable {
    case mine, reviewRequested, assigned
}
```

**`PRFilter` (`Sources/GitHubOperations/PRManager.swift`)** — one new case:

```swift
public enum PRFilter: Sendable {
    case mine, reviewRequested, assigned, all
}
```

`buildSearchArgs` and `buildListArgs` gain a `.assigned` branch that adds `--assignee @me`.

**`PRTab` (`Sources/Views/PRDashboard/PRDashboardView.swift`)** — one new case:

```swift
public enum PRTab: String, CaseIterable, Sendable {
    case all = "All"
    case mine = "Mine"
    case reviewRequested = "Review Requests"
    case assigned = "Assigned"
}
```

**`PREnrichResult`** — one new field:

```swift
public var assignees: [String] = []
```

Populated by the existing `gh pr view --json ...` call — the JSON field list adds `assignees`, and `GHEnrichResponse` decodes the array of `{login}` objects.

**`Collaborator` (new type, in `PRManager.swift`)** — for the picker:

```swift
public struct Collaborator: Identifiable, Sendable, Hashable {
    public let login: String
    public let name: String?        // optional, for search matching
    public var id: String { login }
}
```

**No database migration.** Assignees are enrichment-derived. A cold start shows blank avatars for ~2s until enrichment completes, matching how `checks` already behaves. Skipping the migration keeps the feature tight.

**`PRManager` state additions (actor-isolated):**

```swift
private var cachedWhoami: [String: String] = [:]               // host → login
private var cachedCollaborators: [String: (data: [Collaborator], fetchedAt: Date)] = [:]  // repo → ...
private let collaboratorsTTL: TimeInterval = 600
```

### PRManager — New Methods

```swift
public func assign(
    repo: String, number: Int, logins: [String], host: String? = nil
) async throws

public func unassign(
    repo: String, number: Int, logins: [String], host: String? = nil
) async throws

public func whoami(host: String? = nil) async throws -> String

public func collaborators(repo: String, host: String? = nil) async throws -> [Collaborator]
```

Both write ops join `logins` with commas and pass as a single `--add-assignee` / `--remove-assignee` argument (gh accepts comma-separated lists).

`whoami` caches per host indefinitely — the user's login rarely changes in a session, and invalidation is a cold-start concern.

`collaborators` paginates and caches per repo with a 10-minute TTL. The popover triggers a fetch on appear; a stale cache is served instantly and refreshed in the background.

### PRManager — Extended Methods

- **`enrichChecks`** — add `"assignees"` to the `--json` field list; `GHEnrichResponse` decodes `assignees: [GHAuthor]` and maps to `[String]` via `login`.
- **`fetchDetail`** — same one-line addition.
- **`fetchAllPRs`** — adds a third parallel fetch for `.assigned`, merges `.assigned` into `pr.origin` before inserting into the dedup dictionary.
- **`buildSearchArgs` / `buildListArgs`** — new `.assigned` branch: `args += ["--assignee", "@me"]`.

### PRCoordinator — New Methods

```swift
@MainActor
func assignPRToMe(_ pr: PullRequest) async

@MainActor
func unassignMeFromPR(_ pr: PullRequest) async

@MainActor
func updateAssignees(_ pr: PullRequest, adding: [String], removing: [String]) async

@MainActor
func loadCollaborators(for repo: String) async -> [Collaborator]

@MainActor
func myLogin(forHost host: String?) -> String?      // synchronous — reads the PRManager whoami cache
```

The sync `myLogin(forHost:)` reads an @Observable mirror of `PRManager.cachedWhoami` that `PRCoordinator` keeps in step. On first access for a host, a background task warms the cache; the mirror triggers a view refresh when it populates. This avoids requiring every card to spawn an async task just to check "is this me".

Each write path follows the existing error-handling pattern: `store?.statusMessage = .success/.error(...)` + `refreshPRAfterAction(pr)` on success.

**Optimistic UI.** Before the `gh` subprocess returns, `pr.assignees` is mutated locally so the avatar row updates instantly. On failure, the re-enrichment round overwrites the optimistic state. Assignment is a visually immediate action where a 1s delay feels sluggish; approve/merge don't do this today but aren't as visually tight.

### UI Components

**1. `AssigneeAvatar` (new shared view, `Sources/Views/Shared/AssigneeAvatar.swift`)**

Reusable initials-in-circle. Deterministic color hashed from the login so `alice-bailey` always renders the same hue. Two-letter initials split on `-` first (`alice-bailey` → "AB"), else first two chars of the login (`mnicholson` → "MN"). Single-character logins pad with a space.

```swift
public struct AssigneeAvatar: View {
    let login: String
    let isMe: Bool          // triggers the green theme gradient
    let size: CGFloat       // 18 default (drawer), 14 for card footer
}
```

The "me" variant uses `theme.chrome.green` gradient for instant recognition. Other avatars draw from a fixed palette indexed by a **stable hash of the login** — e.g., summing UTF-8 code units modulo palette size — so colors stay consistent across app launches. **Do not use Swift's built-in `.hashValue`**: it's randomized per-launch and colors would change every time the app opens.

**2. `AssigneesRow` (new private view inside `PRDetailDrawer`)**

Placed below the metadata row in the drawer header, rendered only when `pr.state == .open` or `.draft`. Matches the visual weight of the existing check/review/merge status rows.

```swift
@ViewBuilder
private var assigneesRow: some View {
    HStack(spacing: 8) {
        Text("Assignees").font(.callout).foregroundColor(theme.chrome.textDim)
        ForEach(pr.assignees, id: \.self) { login in
            AssigneeAvatar(login: login, isMe: login == myLogin, size: 18)
                .help(login)
        }
        Button {
            showAssigneePicker = true
        } label: {
            Image(systemName: "plus.circle")
                .foregroundColor(theme.chrome.textDim)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAssigneePicker) {
            AssigneePickerView(pr: pr, myLogin: myLogin)
        }
        Spacer()
    }
}
```

`myLogin` is resolved per-PR from `PRManager.whoami(host:)` using the PR's host (extracted via `prManager.hostFromURL(pr.url)`). Held in the drawer as `@State private var myLogin: String?` and populated in `.task`. This is host-aware because the same user may have different logins on different GHE instances (e.g., `mnicholson` on github.com vs `m-nicholson` on ghe.spotify.net); comparing a github.com login against a GHE PR's assignees would mis-identify "me".

**3. `AssigneePickerView` (new file, `Sources/Views/PRDashboard/AssigneePicker.swift`)**

Fixed-frame popover content (`360 × 420`). Structure:

```
┌──────────────────────────────────────┐
│    [⚡ Assign to me / Unassign me]   │  ← full-width green pill
├──────────────────────────────────────┤
│ 🔍 [Filter collaborators…          ] │
├──────────────────────────────────────┤
│ ● alice-bailey               Alice B.│  ← ✓ if assigned
│   bob-chen                   Bob C.  │
│   carlos-dev                 Carlos  │
│ ...                                  │
└──────────────────────────────────────┘
```

- **Top pill** — full-width rounded button. Label and action flip based on `pr.assignees.contains(myLogin)`:
  - `"Assign to me"` → calls `prCoordinator.assignPRToMe(pr)`
  - `"Unassign me"` → calls `prCoordinator.unassignMeFromPR(pr)`
- **Search field** — `TextField` that filters both `login` and `name` case-insensitively.
- **Collaborator list** — scrollable `LazyVStack`. Each row shows avatar, login, optional name. Tapping toggles the login via `prCoordinator.updateAssignees(pr, adding:[login])` or `removing:[login]`.
- **Loading state** — `ProgressView("Loading collaborators…")` while `loadCollaborators` is in flight.
- **Error state** — `Text("Couldn't load collaborators").foregroundStyle(theme.chrome.red)` with a retry button.
- **Empty search state** — `Text("No matches").foregroundStyle(.secondary)` centered.

Collaborator fetch triggers in `.task { await prCoordinator.loadCollaborators(for: pr.repo) }`. The cache ensures reopening the picker is instant within the 10-minute window.

**4. "Assignees" column in `PRDashboardView` Table**

The dashboard uses SwiftUI `Table` with columns (not cards). Add a new `TableColumn("Assignees")` between the existing "Author" and "Age" columns, sortable by assignee count.

```swift
TableColumn("Assignees", value: \.assigneeSortKey) { pr in
    if !pr.assignees.isEmpty {
        let myLogin = prCoordinator.myLogin(forHost: prManager.hostFromURL(pr.url))
        HStack(spacing: -4) {
            ForEach(pr.assignees.prefix(3), id: \.self) { login in
                AssigneeAvatar(login: login, isMe: login == myLogin, size: 14)
            }
            if pr.assignees.count > 3 {
                Text("+\(pr.assignees.count - 3)")
                    .font(.caption2)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(theme.chrome.surface))
                    .foregroundColor(theme.chrome.textDim)
            }
        }
    }
}
.width(min: 40, ideal: 80, max: 140)
```

`assigneeSortKey` is a new computed property on `PullRequest` (via the existing `PullRequest+ViewHelpers.swift` extension pattern that already hosts `reviewSortRank` / `mergeSortRank` / `checksPassRatio`):

```swift
public extension PullRequest {
    /// Sort key for the "Assignees" column — count ascending (PRs without assignees first).
    var assigneeSortKey: Int { assignees.count }
}
```

`PRCoordinator` exposes `myLogin(forHost:)` returning the cached whoami for that host (or `nil` if not yet resolved, in which case the "me" highlight is skipped gracefully). The slight negative spacing (`-4`) creates an overlapping-avatar stack familiar from GitHub/Linear.

The cell renders nothing (empty view) when `pr.assignees.isEmpty`, keeping the Table visually tidy for PRs with no assignees.

**5. "Assigned" dashboard tab**

`PRTab.assigned = "Assigned"` adds the fourth tab. The grouping/filtering logic filters `pullRequests` where `origin.contains(.assigned)`. `PRCoordinator.fetchAllPRs` already populates origins from all three searches, so the new tab is pure filtering — no additional fetch when the tab is switched.

Tab counts (if displayed by the existing `PRColumnHeader`) use the same filter logic.

## Testing

Extensions to the existing 338-test suite:

**`PRManagerTests` (GitHubOperationsTests)**

- `assign` builds `["pr", "edit", "42", "--repo", "owner/repo", "--add-assignee", "alice,bob"]`.
- `unassign` symmetric.
- `whoami` returns cached value without re-running `gh api user` on second call.
- `collaborators` parses paginated `--slurp` output and dedups across pages.
- `collaborators` serves stale cache within TTL window.
- `buildSearchArgs(.assigned)` includes `--assignee @me`.
- `fetchAllPRs` merges three origins correctly when the same PR appears in multiple searches.
- `enrichChecks` decodes the `assignees` field from a fixture JSON payload.

**`PullRequestTests` (ModelsTests)**

- `assignees` field encodes/decodes round-trip.
- `PROrigin.assigned` encode/decode.
- `origin: Set<PROrigin>` merge behavior with `.assigned`.

**`ViewsTests` (new `AssigneeAvatarTests`)**

- Initials: `alice-bailey` → "AB", `mnicholson` → "MN", `mn` → "MN", `a` → "A ", `` `` → "".
- Color hash determinism: same login yields same color across calls **and across simulated app restarts** (regression guard against accidentally reverting to `login.hashValue`).
- `isMe=true` uses theme green regardless of hash.

**`ViewsTests` (update `PRGroupingTests`, `PRSortFilterTests`)**

- New `assigned` tab filter includes PRs where `origin.contains(.assigned)` and excludes others.
- `all` tab continues to include assigned-only PRs.

**`ViewsTests` (new `AssigneePickerTests`)**

- Loading state renders ProgressView.
- Empty list renders "No collaborators".
- Search filters on both login and name.
- Pill label flips between "Assign to me" and "Unassign me" based on `pr.assignees`.

## Rollout

Single PR. No feature flag. No migration. Behind-the-scenes changes (extra JSON field in `enrichChecks`, third parallel search in `fetchAllPRs`) are additive — if the `gh` command doesn't return assignees for some reason, the field defaults to `[]` and the UI hides the row.

## Open Questions

None at design time.

## References

- `Sources/GitHubOperations/PRManager.swift` — PR operations actor
- `Sources/App/PRCoordinator.swift` — PR state orchestrator
- `Sources/Views/PRDashboard/PRDetailDrawer.swift` — drawer UI
- `Sources/Views/PRDashboard/PRDashboardView.swift` — dashboard UI and `PRTab` enum
- `Sources/Models/PullRequest.swift` — model layer
- GitHub CLI docs for `gh pr edit --add-assignee` and `gh api repos/:owner/:repo/collaborators`
