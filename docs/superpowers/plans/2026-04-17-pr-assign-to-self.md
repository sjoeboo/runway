# PR Assignee Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add assignee management to Runway's PR surface — a dedicated drawer row with a searchable popover picker, an "Assignees" column on the dashboard Table, and a new "Assigned" tab — so users can assign themselves or any repo collaborator without leaving the app.

**Architecture:** Pure additions to the existing three-layer PR stack (`PRManager` actor → `PRCoordinator` @Observable → SwiftUI views). Four new `gh` CLI ops (`assign`, `unassign`, `whoami`, `collaborators`), one new `[String]` field on `PullRequest`, three new enum cases (`PROrigin.assigned`, `PRFilter.assigned`, `PRTab.assigned`). Assignees arrive via the existing enrichment pipeline — no new fetches for list display. Popover-hosted `AssigneePickerView` loads repo collaborators lazily with 10-minute TTL.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test` / `#expect`), GRDB (no schema changes — assignees not persisted), `gh` CLI wrapping.

**Spec:** [`docs/superpowers/specs/2026-04-17-pr-assign-to-self-design.md`](../specs/2026-04-17-pr-assign-to-self-design.md)

---

## Task Groups

| # | Task | Files |
|---|------|-------|
| 1 | Add `PROrigin.assigned` case | Models, ModelsTests |
| 2 | Add `PullRequest.assignees` field | Models, ModelsTests |
| 3 | Add `Collaborator` type | GitHubOperations, GitHubOperationsTests |
| 4 | Add `PRFilter.assigned` + search args | GitHubOperations, GitHubOperationsTests |
| 5 | Add `whoami(host:)` with caching | GitHubOperations, GitHubOperationsTests |
| 6 | Add `collaborators(repo:host:)` with caching | GitHubOperations, GitHubOperationsTests |
| 7 | Extend `enrichChecks` / `fetchDetail` to decode assignees | GitHubOperations, GitHubOperationsTests |
| 8 | Add `assign` / `unassign` with static arg builder | GitHubOperations, GitHubOperationsTests |
| 9 | Extend `fetchAllPRs` with third `.assigned` search | GitHubOperations, GitHubOperationsTests |
| 10 | Add `PRCoordinator` whoami mirror + `myLogin(forHost:)` | App |
| 11 | Add `PRCoordinator.loadCollaborators(for:)` | App |
| 12 | Add `PRCoordinator` write ops (`assignPRToMe`, etc.) | App |
| 13 | Surface `assignees` through `applyEnrichment` | App |
| 14 | Create `AssigneeAvatar` view + tests | Views, ViewsTests |
| 15 | Add `assigneeSortKey` to `PRSortFilter` | Views, ViewsTests |
| 16 | Create `AssigneePickerView` | Views |
| 17 | Add assignees row to `PRDetailDrawer` | Views |
| 18 | Wire drawer callbacks through `RunwayStore` | App, Views |
| 19 | Add `PRTab.assigned` + filter logic | Views, ViewsTests |
| 20 | Add "Assignees" `TableColumn` to `PRDashboardView` | Views |
| 21 | Final verification: full test + manual smoke | — |

---

## Task 1: Add `PROrigin.assigned` enum case

**Files:**
- Modify: `Sources/Models/PullRequest.swift:89-92`
- Test: `Tests/ModelsTests/PullRequestTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ModelsTests/PullRequestTests.swift`:

```swift
// MARK: - PROrigin.assigned

@Test func prOriginAssignedCase() {
    let origin: PROrigin = .assigned
    #expect(origin.rawValue == "assigned")
}

@Test func prOriginAssignedEncodable() throws {
    let origins: Set<PROrigin> = [.mine, .assigned]
    let data = try JSONEncoder().encode(origins)
    let decoded = try JSONDecoder().decode(Set<PROrigin>.self, from: data)
    #expect(decoded == origins)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ModelsTests.prOriginAssigned"
```
Expected: FAIL — `type 'PROrigin' has no member 'assigned'`.

- [ ] **Step 3: Add the case**

In `Sources/Models/PullRequest.swift`, change:

```swift
public enum PROrigin: String, Codable, Sendable, Hashable {
    case mine
    case reviewRequested
}
```

to:

```swift
public enum PROrigin: String, Codable, Sendable, Hashable {
    case mine
    case reviewRequested
    case assigned
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ModelsTests.prOriginAssigned"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/PullRequest.swift Tests/ModelsTests/PullRequestTests.swift
git commit -m "feat(models): add PROrigin.assigned case"
```

---

## Task 2: Add `PullRequest.assignees` field

**Files:**
- Modify: `Sources/Models/PullRequest.swift:4-85`
- Test: `Tests/ModelsTests/PullRequestTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ModelsTests/PullRequestTests.swift`:

```swift
// MARK: - PullRequest.assignees

@Test func pullRequestAssigneesDefault() {
    let pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    #expect(pr.assignees.isEmpty)
}

@Test func pullRequestAssigneesCodableRoundtrip() throws {
    var pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    pr.assignees = ["alice", "bob-chen"]
    let data = try JSONEncoder().encode(pr)
    let decoded = try JSONDecoder().decode(PullRequest.self, from: data)
    #expect(decoded.assignees == ["alice", "bob-chen"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ModelsTests.pullRequestAssignees"
```
Expected: FAIL — `value of type 'PullRequest' has no member 'assignees'`.

- [ ] **Step 3: Add the field**

In `Sources/Models/PullRequest.swift`, add `assignees` after `lastCommitDate` (line 28):

```swift
    public var lastCommitDate: Date?
    public var assignees: [String]
```

Then add `assignees` to the `init`:

```swift
        lastCommitDate: Date? = nil,
        assignees: [String] = []
    ) {
```

And assign it at the end of `init`:

```swift
        self.lastCommitDate = lastCommitDate
        self.assignees = assignees
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ModelsTests.pullRequestAssignees"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/PullRequest.swift Tests/ModelsTests/PullRequestTests.swift
git commit -m "feat(models): add PullRequest.assignees field"
```

---

## Task 3: Add `Collaborator` type

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift` (append near the "Types" section around line 460)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - Collaborator

@Test func collaboratorIdEqualsLogin() {
    let c = Collaborator(login: "alice", name: "Alice B")
    #expect(c.id == "alice")
}

@Test func collaboratorHashableByLogin() {
    let a1 = Collaborator(login: "alice", name: "Alice")
    let a2 = Collaborator(login: "alice", name: nil)
    #expect(a1 == a1)
    // Different names yield different structs — hashable by all fields is fine
    #expect(a1 != a2)
}

@Test func collaboratorDecodable() throws {
    let json = #"{"login":"alice","name":"Alice Bailey"}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(Collaborator.self, from: json)
    #expect(c.login == "alice")
    #expect(c.name == "Alice Bailey")
}

@Test func collaboratorDecodableWithNullName() throws {
    let json = #"{"login":"bob","name":null}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(Collaborator.self, from: json)
    #expect(c.login == "bob")
    #expect(c.name == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "GitHubOperationsTests.collaborator"
```
Expected: FAIL — `cannot find 'Collaborator' in scope`.

- [ ] **Step 3: Add the type**

In `Sources/GitHubOperations/PRManager.swift`, add before `// MARK: - Types` (line ~460):

```swift
// MARK: - Collaborator

public struct Collaborator: Identifiable, Sendable, Hashable, Codable {
    public let login: String
    public let name: String?

    public init(login: String, name: String? = nil) {
        self.login = login
        self.name = name
    }

    public var id: String { login }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "GitHubOperationsTests.collaborator"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): add Collaborator type"
```

---

## Task 4: Add `PRFilter.assigned` + update search arg builders

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift:462-466` (`PRFilter` enum)
- Modify: `Sources/GitHubOperations/PRManager.swift:388-407` (`buildSearchArgs`)
- Modify: `Sources/GitHubOperations/PRManager.swift:409-427` (`buildListArgs`)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Extract arg builders into testable static helpers**

`buildSearchArgs` and `buildListArgs` are currently private instance methods. To test them, make `buildSearchArgs` a nonisolated static (`buildListArgs` remains private but becomes static too for symmetry). Replace line 388-407 in `Sources/GitHubOperations/PRManager.swift`:

```swift
    nonisolated static func buildSearchArgs(filter: PRFilter) -> [String] {
        var args = [
            "search", "prs",
            "--state", "open",
            "--archived=false",
            "--json", "number,title,state,repository,url,isDraft,createdAt,updatedAt,author",
            "--limit", "50",
        ]

        switch filter {
        case .mine:
            args += ["--author", "@me"]
        case .reviewRequested:
            args += ["--review-requested", "@me"]
        case .assigned:
            args += ["--assignee", "@me"]
        case .all:
            break
        }

        return args
    }
```

Update the caller on line 66 to use `Self.buildSearchArgs(filter: filter)`.

And replace `buildListArgs` (line 409-427) similarly:

```swift
    nonisolated static func buildListArgs(repo: String, filter: PRFilter) -> [String] {
        var args = [
            "pr", "list", "--json",
            "number,title,state,headRefName,baseRefName,author,url,isDraft,additions,deletions,changedFiles,createdAt,updatedAt,reviewDecision",
            "--repo", repo,
        ]

        switch filter {
        case .mine:
            args += ["--author", "@me"]
        case .reviewRequested:
            args += ["--search", "review-requested:@me"]
        case .assigned:
            args += ["--assignee", "@me"]
        case .all:
            break
        }

        args += ["--limit", "50"]
        return args
    }
```

Update the caller on line 57 to use `Self.buildListArgs(repo: repo, filter: filter)`.

Also update `fetchPRsNonisolated` (line 343) to use the new static: replace the inline `var args = [...]` switch block with `var args = Self.buildSearchArgs(filter: filter)`.

Finally, add the new case to `PRFilter` (line 462):

```swift
public enum PRFilter: Sendable {
    case mine
    case reviewRequested
    case assigned
    case all
}
```

- [ ] **Step 2: Write the failing tests**

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - PRFilter.assigned

@Test func prFilterAssignedCase() {
    let filters: [PRFilter] = [.mine, .reviewRequested, .assigned, .all]
    #expect(filters.count == 4)
}

@Test func buildSearchArgsForAssigned() {
    let args = PRManager.buildSearchArgs(filter: .assigned)
    #expect(args.contains("--assignee"))
    #expect(args.contains("@me"))
}

@Test func buildSearchArgsForMine() {
    let args = PRManager.buildSearchArgs(filter: .mine)
    #expect(args.contains("--author"))
    #expect(args.contains("@me"))
    #expect(!args.contains("--assignee"))
}

@Test func buildListArgsForAssigned() {
    let args = PRManager.buildListArgs(repo: "owner/repo", filter: .assigned)
    #expect(args.contains("owner/repo"))
    #expect(args.contains("--assignee"))
    #expect(args.contains("@me"))
}
```

Also update the existing `prFilterCases` test (line 18-22) — it checks `filters.count == 3` but we now have 4:

Replace:
```swift
@Test func prFilterCases() {
    // Verify all filter cases exist and are distinct
    let filters: [PRFilter] = [.mine, .reviewRequested, .all]
    #expect(filters.count == 3)
}
```

with (removing the old test — covered by `prFilterAssignedCase` above):

```swift
// (removed — superseded by prFilterAssignedCase)
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter "GitHubOperationsTests.(prFilter|buildSearchArgs|buildListArgs)"
```
Expected: PASS — new case and arg construction both work.

- [ ] **Step 4: Run the full test suite to catch regressions**

```bash
swift test
```
Expected: PASS. Any previously-passing test that broke means the switch-exhaustiveness warnings exposed something — fix the missing case.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): add PRFilter.assigned + extract arg builders as testable statics"
```

---

## Task 5: Add `whoami(host:)` with per-host caching

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift` (add state vars + method)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

Testing `whoami` directly requires shelling out — which is not mocked. Instead, test the cache accessor via a testable overload that bypasses the shell call. The real `whoami(host:)` is verified by manual smoke test at the end.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - whoami

@Test func whoamiReturnsSeededValue() async {
    let manager = PRManager()
    await manager.seedWhoamiForTest(host: "github.com", login: "alice")
    let result = await manager.cachedWhoami(host: "github.com")
    #expect(result == "alice")
}

@Test func whoamiReturnsNilForUnseededHost() async {
    let manager = PRManager()
    let result = await manager.cachedWhoami(host: "github.com")
    #expect(result == nil)
}

@Test func whoamiDistinctAcrossHosts() async {
    let manager = PRManager()
    await manager.seedWhoamiForTest(host: "github.com", login: "alice")
    await manager.seedWhoamiForTest(host: "ghe.spotify.net", login: "alice-s")
    #expect(await manager.cachedWhoami(host: "github.com") == "alice")
    #expect(await manager.cachedWhoami(host: "ghe.spotify.net") == "alice-s")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "GitHubOperationsTests.whoami"
```
Expected: FAIL — methods don't exist.

- [ ] **Step 3: Add state + methods**

In `Sources/GitHubOperations/PRManager.swift`, add to the actor state (near line 44, after `cachedHosts`):

```swift
    private var cachedWhoamiByHost: [String: String] = [:]
```

The dictionary key treats `nil` host as `""` (canonical form for "default / github.com").

Then add the public and test methods (near the bottom of the actor body, before `// MARK: - Private`):

```swift
    /// Returns the current user's login for the given host, fetching and caching on first call.
    /// Per-host because the same user may have different logins on different GHE instances.
    public func whoami(host: String? = nil) async throws -> String {
        let key = host ?? ""
        if let cached = cachedWhoamiByHost[key] { return cached }
        let output = try await runGH(args: ["api", "user", "-q", ".login"], host: host)
        let login = output.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedWhoamiByHost[key] = login
        return login
    }

    /// Returns the cached whoami for a host without triggering a fetch. Used by UI
    /// that needs synchronous access and can tolerate `nil` until the cache warms.
    public func cachedWhoami(host: String?) -> String? {
        cachedWhoamiByHost[host ?? ""]
    }

    #if DEBUG
    /// Test-only: seed the whoami cache to bypass the gh shellout.
    public func seedWhoamiForTest(host: String?, login: String) {
        cachedWhoamiByHost[host ?? ""] = login
    }
    #endif
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "GitHubOperationsTests.whoami"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): add PRManager.whoami with per-host cache"
```

---

## Task 6: Add `collaborators(repo:host:)` with caching

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift` (add method + parser + cache)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - collaborators parsing

@Test func parseCollaboratorsPages() throws {
    // --paginate --slurp returns [[...], [...]]
    let json = """
    [
      [{"login":"alice","name":"Alice Bailey"}, {"login":"bob","name":null}],
      [{"login":"carol","name":"Carol"}, {"login":"alice","name":"Alice Bailey"}]
    ]
    """
    let collabs = try PRManager.parseCollaborators(json)
    // Dedup by login; preserve first-occurrence order
    #expect(collabs.map(\.login) == ["alice", "bob", "carol"])
    #expect(collabs[0].name == "Alice Bailey")
    #expect(collabs[1].name == nil)
}

@Test func parseCollaboratorsEmpty() throws {
    let collabs = try PRManager.parseCollaborators("[]")
    #expect(collabs.isEmpty)
}

@Test func collaboratorsCacheSeeded() async {
    let manager = PRManager()
    let seed = [Collaborator(login: "alice", name: "Alice")]
    await manager.seedCollaboratorsForTest(repo: "owner/repo", collabs: seed)
    let cached = await manager.cachedCollaborators(for: "owner/repo")
    #expect(cached?.map(\.login) == ["alice"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "GitHubOperationsTests.(parseCollaborators|collaboratorsCache)"
```
Expected: FAIL.

- [ ] **Step 3: Add the parser, cache, and method**

In `Sources/GitHubOperations/PRManager.swift`, add to the actor state (near the whoami cache):

```swift
    private var cachedCollaboratorsByRepo: [String: (data: [Collaborator], fetchedAt: Date)] = [:]
    private let collaboratorsTTL: TimeInterval = 600
```

Add a decodable helper struct near other GH JSON types (before `// MARK: - JSONDecoder for gh output`):

```swift
private struct GHCollaboratorPage: Decodable {
    struct User: Decodable {
        let login: String
        let name: String?
    }
}

// For --slurp output: [[{login,name},...], [...]]
private struct GHCollaboratorUser: Decodable {
    let login: String
    let name: String?
}
```

Add the public method and parser inside the actor (near whoami, before `// MARK: - Private`):

```swift
    /// Fetch the collaborator list for a repo. Cached per-repo with a 10-min TTL.
    public func collaborators(repo: String, host: String? = nil) async throws -> [Collaborator] {
        if let entry = cachedCollaboratorsByRepo[repo],
           Date().timeIntervalSince(entry.fetchedAt) < collaboratorsTTL {
            return entry.data
        }
        let output = try await runGH(
            args: ["api", "repos/\(repo)/collaborators", "--paginate", "--slurp"],
            host: host
        )
        let collabs = try Self.parseCollaborators(output)
        cachedCollaboratorsByRepo[repo] = (collabs, Date())
        return collabs
    }

    public func cachedCollaborators(for repo: String) -> [Collaborator]? {
        guard let entry = cachedCollaboratorsByRepo[repo],
              Date().timeIntervalSince(entry.fetchedAt) < collaboratorsTTL
        else { return nil }
        return entry.data
    }

    #if DEBUG
    public func seedCollaboratorsForTest(repo: String, collabs: [Collaborator]) {
        cachedCollaboratorsByRepo[repo] = (collabs, Date())
    }
    #endif

    /// Parse `gh api repos/.../collaborators --paginate --slurp` output (array of pages).
    /// Dedup by login, preserve first-occurrence order.
    nonisolated static func parseCollaborators(_ json: String) throws -> [Collaborator] {
        guard let data = json.data(using: .utf8) else { return [] }
        let pages = try JSONDecoder().decode([[GHCollaboratorUser]].self, from: data)
        var seen = Set<String>()
        var result: [Collaborator] = []
        for user in pages.flatMap({ $0 }) {
            if seen.insert(user.login).inserted {
                result.append(Collaborator(login: user.login, name: user.name))
            }
        }
        return result
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "GitHubOperationsTests.(parseCollaborators|collaboratorsCache)"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): add PRManager.collaborators with 10-min TTL cache"
```

---

## Task 7: Decode `assignees` via `enrichChecks` + `fetchDetail`

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift` (update `GHEnrichResponse`, `PREnrichResult`, `GHPRItem`, `GHPRDetailResponse`, `PRDetail`)
- Modify: `Sources/Models/PullRequest.swift` (add `assignees` to `PRDetail`)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - Assignee decoding

@Test func enrichResultHasAssignees() {
    let result = PREnrichResult()
    #expect(result.assignees.isEmpty)
}

@Test func enrichResponseDecodesAssignees() throws {
    let json = """
    {
      "statusCheckRollup": [],
      "assignees": [{"login":"alice","name":"Alice"}, {"login":"bob","name":null}]
    }
    """
    // Force-decode via the same path enrichChecks uses.
    // We wrap in the real response shape so the test follows prod code.
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    // Use the public test-seam helper added below
    let result = try PRManager.parseEnrichResponseForTest(data: data, excludeAuthor: nil)
    #expect(result.assignees == ["alice", "bob"])
}

@Test func enrichResponseWithNoAssignees() throws {
    let json = #"{"statusCheckRollup":[]}"#
    let data = json.data(using: .utf8)!
    let result = try PRManager.parseEnrichResponseForTest(data: data, excludeAuthor: nil)
    #expect(result.assignees.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "GitHubOperationsTests.(enrichResult|enrichResponse)"
```
Expected: FAIL.

- [ ] **Step 3: Wire assignees through the enrichment path**

In `Sources/GitHubOperations/PRManager.swift`:

**(a)** Add `assignees` to `PREnrichResult` (around line 4-41):

```swift
public struct PREnrichResult: Sendable {
    public var checks: CheckSummary
    // ... existing fields ...
    public var lastCommitDate: Date?
    public var assignees: [String]

    public init(
        // ... existing params ...
        lastCommitDate: Date? = nil,
        assignees: [String] = []
    ) {
        // ... existing assigns ...
        self.lastCommitDate = lastCommitDate
        self.assignees = assignees
    }
}
```

**(b)** Add `assignees` to `GHEnrichResponse` (around line 768):

```swift
private struct GHEnrichResponse: Decodable {
    // ... existing fields ...
    let assignees: [GHAuthor]?

    func toEnrichResult(excludeAuthor: String? = nil) -> PREnrichResult {
        // ... existing decoding ...
        let assigneeLogins = (assignees ?? []).map(\.login)
        return PREnrichResult(
            // ... existing args ...
            lastCommitDate: lastCommitDate,
            assignees: assigneeLogins
        )
    }
}
```

**(c)** Add `assignees` to the JSON field list in `enrichChecks` (line 128-141):

```swift
        "statusCheckRollup,reviewDecision,headRefName,baseRefName,additions,deletions,changedFiles,mergeable,mergeStateStatus,autoMergeRequest,comments,commits,assignees",
```

**(d)** Add the test seam as a nonisolated static on `PRManager`:

```swift
    #if DEBUG
    /// Test-only: parse an enrich response from raw JSON data.
    nonisolated static func parseEnrichResponseForTest(data: Data, excludeAuthor: String?) throws -> PREnrichResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(GHEnrichResponse.self, from: data)
        return resp.toEnrichResult(excludeAuthor: excludeAuthor)
    }
    #endif
```

**(e)** Also do `fetchDetail`'s path:

Add `assignees` to the JSON field list in `fetchDetail` (line 144-152):

```swift
        "body,reviews,comments,files,statusCheckRollup,reviewDecision,headRefName,baseRefName,additions,deletions,changedFiles,mergeable,mergeStateStatus,autoMergeRequest,assignees",
```

Add `assignees` to `PRDetail` (in `Sources/Models/PullRequest.swift:206-256`):

```swift
public struct PRDetail: Codable, Sendable {
    // ... existing fields ...
    public var autoMergeEnabled: Bool
    public var assignees: [String]

    public init(
        // ... existing params ...
        autoMergeEnabled: Bool = false,
        assignees: [String] = []
    ) {
        // ... existing assigns ...
        self.autoMergeEnabled = autoMergeEnabled
        self.assignees = assignees
    }
}
```

Add `assignees` to `GHPRDetailResponse` (line 633-695):

```swift
private struct GHPRDetailResponse: Decodable {
    // ... existing ...
    let assignees: [GHAuthor]?

    func toPRDetail() -> PRDetail {
        // ... existing ...
        return PRDetail(
            // ... existing args ...
            autoMergeEnabled: autoMergeRequest != nil,
            assignees: (assignees ?? []).map(\.login)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "GitHubOperationsTests.(enrichResult|enrichResponse)"
```
Expected: PASS.

- [ ] **Step 5: Run the full test suite**

```bash
swift test
```
Expected: PASS. Codable round-trip of `PRDetail` and `PREnrichResult` should not have broken.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Sources/Models/PullRequest.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): decode assignees via enrichChecks + fetchDetail"
```

---

## Task 8: Add `assign` / `unassign` with a static arg builder

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift` (add method + helper)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - assign / unassign args

@Test func buildAssignArgsAdd() {
    let args = PRManager.buildAssignArgs(
        repo: "owner/repo", number: 42, logins: ["alice", "bob"], add: true
    )
    #expect(args == ["pr", "edit", "42", "--repo", "owner/repo", "--add-assignee", "alice,bob"])
}

@Test func buildAssignArgsRemove() {
    let args = PRManager.buildAssignArgs(
        repo: "owner/repo", number: 42, logins: ["alice"], add: false
    )
    #expect(args == ["pr", "edit", "42", "--repo", "owner/repo", "--remove-assignee", "alice"])
}

@Test func buildAssignArgsSingle() {
    let args = PRManager.buildAssignArgs(
        repo: "o/r", number: 1, logins: ["me"], add: true
    )
    #expect(args.last == "me")
    #expect(args.contains("--add-assignee"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "GitHubOperationsTests.buildAssignArgs"
```
Expected: FAIL — method doesn't exist.

- [ ] **Step 3: Add the builder and public methods**

In `Sources/GitHubOperations/PRManager.swift`, near the other write operations (around line 220-280, after `approve`/`comment`/etc.):

```swift
    /// Assign the given logins to a PR. Single subprocess (gh accepts comma-joined list).
    public func assign(repo: String, number: Int, logins: [String], host: String? = nil) async throws {
        guard !logins.isEmpty else { return }
        let args = Self.buildAssignArgs(repo: repo, number: number, logins: logins, add: true)
        try await runGH(args: args, host: host)
    }

    /// Remove assignees from a PR. No-op if logins is empty.
    public func unassign(repo: String, number: Int, logins: [String], host: String? = nil) async throws {
        guard !logins.isEmpty else { return }
        let args = Self.buildAssignArgs(repo: repo, number: number, logins: logins, add: false)
        try await runGH(args: args, host: host)
    }

    nonisolated static func buildAssignArgs(repo: String, number: Int, logins: [String], add: Bool) -> [String] {
        let flag = add ? "--add-assignee" : "--remove-assignee"
        return ["pr", "edit", "\(number)", "--repo", repo, flag, logins.joined(separator: ",")]
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "GitHubOperationsTests.buildAssignArgs"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): add assign / unassign PR operations"
```

---

## Task 9: Extend `fetchAllPRs` with third `.assigned` search

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift:80-107` (`fetchAllPRs`)
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

The existing merge logic handles two origin sets. Extend to three. This task is pure refactor + one added parallel call.

- [ ] **Step 1: Write a merge-logic test**

The existing code has no direct test for the origin-merge behavior (it's inline in `fetchAllPRs`). Extract to a static helper first for testability, then add a case for `.assigned`.

Append to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
// MARK: - fetchAllPRs merge

@Test func mergeOriginsSingleList() {
    let pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    let merged = PRManager.mergePRsByOrigin(
        mine: [pr],
        reviewRequested: [],
        assigned: []
    )
    let out = merged.first!
    #expect(out.origin == [.mine])
}

@Test func mergeOriginsAcrossAllThree() {
    let pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    let merged = PRManager.mergePRsByOrigin(
        mine: [pr],
        reviewRequested: [pr],
        assigned: [pr]
    )
    #expect(merged.count == 1)
    #expect(merged.first!.origin == [.mine, .reviewRequested, .assigned])
}

@Test func mergeOriginsAssignedOnly() {
    let pr = PullRequest(
        number: 2, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    let merged = PRManager.mergePRsByOrigin(
        mine: [],
        reviewRequested: [],
        assigned: [pr]
    )
    #expect(merged.first!.origin == [.assigned])
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "GitHubOperationsTests.mergeOrigins"
```
Expected: FAIL — `mergePRsByOrigin` doesn't exist.

- [ ] **Step 3: Extract the merge helper, add the third parallel call**

Replace the body of `fetchAllPRs` (line 80-107):

```swift
    public func fetchAllPRs() async throws -> [PullRequest] {
        let hosts = await discoverHosts()

        async let minePRs: [PullRequest] = Self.fetchPRsNonisolated(hosts: hosts, filter: .mine)
        async let reviewPRs: [PullRequest] = Self.fetchPRsNonisolated(hosts: hosts, filter: .reviewRequested)
        async let assignedPRs: [PullRequest] = Self.fetchPRsNonisolated(hosts: hosts, filter: .assigned)

        let (mine, review, assigned) = await (minePRs, reviewPRs, assignedPRs)
        return Self.mergePRsByOrigin(mine: mine, reviewRequested: review, assigned: assigned)
    }

    nonisolated static func mergePRsByOrigin(
        mine: [PullRequest],
        reviewRequested: [PullRequest],
        assigned: [PullRequest]
    ) -> [PullRequest] {
        var merged: [String: PullRequest] = [:]
        for var pr in mine {
            pr.origin = [.mine]
            merged[pr.id] = pr
        }
        for var pr in reviewRequested {
            pr.origin = [.reviewRequested]
            if var existing = merged[pr.id] {
                existing.origin.insert(.reviewRequested)
                merged[pr.id] = existing
            } else {
                merged[pr.id] = pr
            }
        }
        for var pr in assigned {
            pr.origin = [.assigned]
            if var existing = merged[pr.id] {
                existing.origin.insert(.assigned)
                merged[pr.id] = existing
            } else {
                merged[pr.id] = pr
            }
        }
        return Array(merged.values)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "GitHubOperationsTests.mergeOrigins"
```
Expected: PASS.

- [ ] **Step 5: Run the full test suite**

```bash
swift test
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat(github): fetch assigned PRs in fetchAllPRs parallel merge"
```

---

## Task 10: Add `PRCoordinator.myLogin(forHost:)` + whoami mirror

**Files:**
- Modify: `Sources/App/PRCoordinator.swift` (add mirror state + methods)

This task is UI-facing but has no isolated unit test — the `@Observable` mirror is exercised by the drawer and column at runtime. Tests at the `PRCoordinator` level would require constructing a live store; we rely on the underlying `PRManager` tests + manual verification.

- [ ] **Step 1: Add the whoami mirror state**

In `Sources/App/PRCoordinator.swift`, add to the State section (around line 14-43):

```swift
    /// Mirror of PRManager whoami cache, observable to drive UI highlighting.
    /// Populated lazily on first `myLogin(forHost:)` call per host.
    var whoamiByHost: [String: String] = [:]
```

- [ ] **Step 2: Add the synchronous accessor and async warmer**

Near the other methods (around the "PR Selection" or "PR Actions" section), add:

```swift
    // MARK: - Whoami

    /// Synchronous accessor for the current user's login on a given host.
    /// Returns nil until the first `warmWhoami(host:)` call resolves.
    func myLogin(forHost host: String?) -> String? {
        whoamiByHost[host ?? ""]
    }

    /// Populate the whoami mirror for a host if not already present. Safe to call repeatedly.
    func warmWhoami(host: String?) {
        let key = host ?? ""
        guard whoamiByHost[key] == nil else { return }
        Task { @MainActor in
            if let login = try? await prManager.whoami(host: host) {
                whoamiByHost[key] = login
            }
        }
    }
```

- [ ] **Step 3: Build to verify compile**

```bash
swift build
```
Expected: Success.

- [ ] **Step 4: Run the full test suite**

```bash
swift test
```
Expected: PASS (no new tests, but regression guard).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/PRCoordinator.swift
git commit -m "feat(coordinator): add whoami mirror + myLogin(forHost:)"
```

---

## Task 11: Add `PRCoordinator.loadCollaborators(for:)`

**Files:**
- Modify: `Sources/App/PRCoordinator.swift`

- [ ] **Step 1: Add the state and loader**

In `Sources/App/PRCoordinator.swift`, add to the State section:

```swift
    /// Observable mirror of PRManager collaborators cache. Keyed by repo.
    var collaboratorsByRepo: [String: [Collaborator]] = [:]

    /// Tracks which repos have a load in-flight to avoid duplicate fetches.
    private var loadingCollaboratorsRepos: Set<String> = []
```

Near the other read-side methods, add:

```swift
    // MARK: - Collaborators

    /// Load collaborators for a repo, caching the result. Deduplicates concurrent calls.
    /// Hits the PRManager cache for instant re-reads within the 10-min TTL.
    func loadCollaborators(for repo: String, host: String? = nil) async {
        if let cached = await prManager.cachedCollaborators(for: repo) {
            collaboratorsByRepo[repo] = cached
            return
        }
        guard !loadingCollaboratorsRepos.contains(repo) else { return }
        loadingCollaboratorsRepos.insert(repo)
        defer { loadingCollaboratorsRepos.remove(repo) }
        do {
            let collabs = try await prManager.collaborators(repo: repo, host: host)
            collaboratorsByRepo[repo] = collabs
        } catch {
            store?.statusMessage = .error("Couldn't load collaborators: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 2: Build + run tests**

```bash
swift build && swift test
```
Expected: Success.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/PRCoordinator.swift
git commit -m "feat(coordinator): add loadCollaborators for picker"
```

---

## Task 12: Add `PRCoordinator` write ops (`assignPRToMe`, `unassignMeFromPR`, `updateAssignees`)

**Files:**
- Modify: `Sources/App/PRCoordinator.swift`

- [ ] **Step 1: Add the three write ops**

In `Sources/App/PRCoordinator.swift`, near `approvePR` / `mergePR` (the `// MARK: - PR Actions` section):

```swift
    // MARK: - Assignee Actions

    /// Assign the current user to the PR. Optimistic UI: mutates pr.assignees before refresh.
    func assignPRToMe(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        guard let login = try? await prManager.whoami(host: host) else {
            store?.statusMessage = .error("Couldn't resolve your GitHub login")
            return
        }
        // Populate the mirror for UI
        whoamiByHost[host ?? ""] = login
        await updateAssignees(pr, adding: [login], removing: [])
    }

    /// Unassign the current user from the PR.
    func unassignMeFromPR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        guard let login = try? await prManager.whoami(host: host) else {
            store?.statusMessage = .error("Couldn't resolve your GitHub login")
            return
        }
        whoamiByHost[host ?? ""] = login
        await updateAssignees(pr, adding: [], removing: [login])
    }

    /// Apply a set of assignee changes to a PR. Optimistic on success, reverts via re-enrichment
    /// on failure. Skips the gh subprocess when both lists are empty.
    func updateAssignees(_ pr: PullRequest, adding: [String], removing: [String]) async {
        guard !adding.isEmpty || !removing.isEmpty else { return }

        // Optimistic update
        let originalAssignees: [String]?
        if let idx = pullRequests.firstIndex(where: { $0.id == pr.id }) {
            originalAssignees = pullRequests[idx].assignees
            var current = pullRequests[idx].assignees
            for login in adding where !current.contains(login) { current.append(login) }
            current.removeAll { removing.contains($0) }
            pullRequests[idx].assignees = current
        } else {
            originalAssignees = nil
        }

        let host = prManager.hostFromURL(pr.url)
        do {
            if !adding.isEmpty {
                try await prManager.assign(repo: pr.repo, number: pr.number, logins: adding, host: host)
            }
            if !removing.isEmpty {
                try await prManager.unassign(repo: pr.repo, number: pr.number, logins: removing, host: host)
            }
            let parts: [String] = [
                adding.isEmpty ? nil : "+\(adding.joined(separator: ","))",
                removing.isEmpty ? nil : "-\(removing.joined(separator: ","))",
            ].compactMap { $0 }
            store?.statusMessage = .success("Updated assignees on #\(pr.number): \(parts.joined(separator: " "))")
            await refreshPRAfterAction(pr)
        } catch {
            // Revert optimistic update
            if let original = originalAssignees,
               let idx = pullRequests.firstIndex(where: { $0.id == pr.id }) {
                pullRequests[idx].assignees = original
            }
            store?.statusMessage = .error("Assign failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 2: Build + run tests**

```bash
swift build && swift test
```
Expected: Success.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/PRCoordinator.swift
git commit -m "feat(coordinator): add PR assignee write ops with optimistic UI"
```

---

## Task 13: Surface `assignees` through `applyEnrichment`

**Files:**
- Modify: `Sources/App/PRCoordinator.swift:195-211` (`applyEnrichment`)

Currently `applyEnrichment` copies ten fields from `PREnrichResult` to `PullRequest` but not `assignees`. This is the one-line wire-through.

- [ ] **Step 1: Add the assign line**

In `Sources/App/PRCoordinator.swift`, inside `applyEnrichment` (line 195-211), add after `pr.enrichedAt = Date()`:

```swift
    private func applyEnrichment(_ result: PREnrichResult, to pr: inout PullRequest) {
        pr.checks = result.checks
        pr.reviewDecision = result.reviewDecision
        if !result.headBranch.isEmpty {
            pr.headBranch = result.headBranch
            pr.baseBranch = result.baseBranch
        }
        pr.additions = result.additions
        pr.deletions = result.deletions
        pr.changedFiles = result.changedFiles
        pr.mergeable = result.mergeable
        pr.mergeStateStatus = result.mergeStateStatus
        pr.autoMergeEnabled = result.autoMergeEnabled
        pr.commentsSinceLastCommit = result.commentsSinceLastCommit
        pr.lastCommitDate = result.lastCommitDate
        pr.assignees = result.assignees
        pr.enrichedAt = Date()
    }
```

- [ ] **Step 2: Build + run tests**

```bash
swift build && swift test
```
Expected: Success.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/PRCoordinator.swift
git commit -m "feat(coordinator): surface assignees via applyEnrichment"
```

---

## Task 14: Create `AssigneeAvatar` view + tests

**Files:**
- Create: `Sources/Views/Shared/AssigneeAvatar.swift`
- Create: `Tests/ViewsTests/AssigneeAvatarTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ViewsTests/AssigneeAvatarTests.swift`:

```swift
import Foundation
import Testing

@testable import Views

// MARK: - Initials extraction

@Test func initialsHyphenSplit() {
    #expect(AssigneeAvatar.initials(for: "alice-bailey") == "AB")
}

@Test func initialsNoHyphenUsesFirstTwo() {
    #expect(AssigneeAvatar.initials(for: "mnicholson") == "MN")
}

@Test func initialsShortName() {
    #expect(AssigneeAvatar.initials(for: "mn") == "MN")
}

@Test func initialsSingleChar() {
    #expect(AssigneeAvatar.initials(for: "a") == "A")
}

@Test func initialsEmpty() {
    #expect(AssigneeAvatar.initials(for: "") == "?")
}

@Test func initialsMultipleHyphens() {
    // Only the first two hyphen-separated parts matter
    #expect(AssigneeAvatar.initials(for: "a-b-c") == "AB")
}

// MARK: - Stable color index

@Test func colorIndexDeterministic() {
    let i1 = AssigneeAvatar.colorIndex(for: "alice", paletteCount: 8)
    let i2 = AssigneeAvatar.colorIndex(for: "alice", paletteCount: 8)
    #expect(i1 == i2)
}

@Test func colorIndexWithinPalette() {
    let idx = AssigneeAvatar.colorIndex(for: "alice", paletteCount: 8)
    #expect(idx >= 0)
    #expect(idx < 8)
}

@Test func colorIndexDoesNotUseHashValue() {
    // Swift's .hashValue is randomized per-launch. Our hash must be stable.
    // Simulating a "restart" by computing the same input — should match.
    let input = "mnicholson"
    let expected = input.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & Int.max }
    #expect(AssigneeAvatar.colorIndex(for: input, paletteCount: 8) == expected % 8)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ViewsTests.(initials|colorIndex)"
```
Expected: FAIL — `AssigneeAvatar` doesn't exist.

- [ ] **Step 3: Create the view**

Create `Sources/Views/Shared/AssigneeAvatar.swift`:

```swift
import SwiftUI
import Theme

/// Small circular avatar rendering two-letter initials.
/// Color is deterministically hashed from the login so the same user
/// always gets the same color. The `isMe` variant uses the theme green.
public struct AssigneeAvatar: View {
    public let login: String
    public let isMe: Bool
    public let size: CGFloat

    @Environment(\.theme) private var theme

    public init(login: String, isMe: Bool = false, size: CGFloat = 18) {
        self.login = login
        self.isMe = isMe
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(Self.initials(for: login))
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(theme.chrome.background, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        if isMe { return theme.chrome.green }
        let idx = Self.colorIndex(for: login, paletteCount: Self.palette.count)
        return Self.palette[idx]
    }

    // MARK: - Pure helpers (testable)

    /// Two-letter initials. Splits on '-' first (alice-bailey → AB), else first two chars.
    /// Returns "?" for empty strings so the UI never renders a blank circle.
    public static func initials(for login: String) -> String {
        guard !login.isEmpty else { return "?" }
        let parts = login.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 2,
           let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        let chars = Array(login)
        if chars.count >= 2 {
            return "\(chars[0])\(chars[1])".uppercased()
        }
        return String(chars[0]).uppercased()
    }

    /// Deterministic palette index for a login. Uses a stable UTF-8 FNV-like hash
    /// so color is consistent across app launches. **Do not use `String.hashValue`**:
    /// Swift randomizes the seed per process, which would change colors every launch.
    public static func colorIndex(for login: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let hash = login.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & Int.max }
        return hash % paletteCount
    }

    private static let palette: [Color] = [
        Color(red: 0.48, green: 0.38, blue: 1.00),  // purple
        Color(red: 0.37, green: 0.77, blue: 0.89),  // cyan
        Color(red: 0.96, green: 0.56, blue: 0.33),  // orange
        Color(red: 0.87, green: 0.37, blue: 0.54),  // pink
        Color(red: 0.37, green: 0.56, blue: 0.89),  // blue
        Color(red: 0.89, green: 0.72, blue: 0.37),  // amber
        Color(red: 0.56, green: 0.37, blue: 0.78),  // violet
        Color(red: 0.37, green: 0.78, blue: 0.56),  // teal
    ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ViewsTests.(initials|colorIndex)"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/Shared/AssigneeAvatar.swift Tests/ViewsTests/AssigneeAvatarTests.swift
git commit -m "feat(views): add AssigneeAvatar with stable color hash + initials"
```

---

## Task 15: Add `assigneeSortKey` to `PRSortFilter`

**Files:**
- Modify: `Sources/Views/PRDashboard/PRSortFilter.swift` (append to the extension that holds `reviewSortRank`)
- Test: `Tests/ViewsTests/PRSortFilterTests.swift`

- [ ] **Step 1: Write failing test**

Append to `Tests/ViewsTests/PRSortFilterTests.swift`:

```swift
// MARK: - assigneeSortKey

@Test func assigneeSortKeyEmpty() {
    let pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    #expect(pr.assigneeSortKey == 0)
}

@Test func assigneeSortKeyCount() {
    var pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    pr.assignees = ["alice", "bob", "carol"]
    #expect(pr.assigneeSortKey == 3)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ViewsTests.assigneeSortKey"
```
Expected: FAIL.

- [ ] **Step 3: Add the sort key**

In `Sources/Views/PRDashboard/PRSortFilter.swift`, in the `PullRequest` extension (near line 128-150), add:

```swift
    /// Sort key for the "Assignees" table column — count of assignees.
    /// PRs with no assignees sort first when ascending.
    public var assigneeSortKey: Int {
        assignees.count
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ViewsTests.assigneeSortKey"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/PRDashboard/PRSortFilter.swift Tests/ViewsTests/PRSortFilterTests.swift
git commit -m "feat(views): add assigneeSortKey computed property"
```

---

## Task 16: Create `AssigneePickerView`

**Files:**
- Create: `Sources/Views/PRDashboard/AssigneePicker.swift`

This task has no isolated unit test — SwiftUI view rendering is validated manually. The internal filtering logic is trivially testable via a static helper.

- [ ] **Step 1: Write failing tests for the static filter helper**

Append to `Tests/ViewsTests/AssigneeAvatarTests.swift` (or a new file, but keep co-located for now):

```swift
// MARK: - AssigneePicker filter

@Test func pickerFilterMatchesLogin() {
    let collabs = [
        Collaborator(login: "alice-bailey", name: "Alice B"),
        Collaborator(login: "bob-chen", name: "Bob C"),
    ]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "alice")
    #expect(filtered.count == 1)
    #expect(filtered.first?.login == "alice-bailey")
}

@Test func pickerFilterMatchesName() {
    let collabs = [
        Collaborator(login: "ab", name: "Alice B"),
        Collaborator(login: "bc", name: "Bob C"),
    ]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "bob")
    #expect(filtered.first?.login == "bc")
}

@Test func pickerFilterEmptyQueryReturnsAll() {
    let collabs = [
        Collaborator(login: "a", name: nil),
        Collaborator(login: "b", name: nil),
    ]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "")
    #expect(filtered.count == 2)
}

@Test func pickerFilterCaseInsensitive() {
    let collabs = [Collaborator(login: "Alice", name: "Alice")]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "ALICE")
    #expect(filtered.count == 1)
}
```

You'll also need to update the import: at the top of the test file, add `import GitHubOperations` so `Collaborator` is visible.

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ViewsTests.pickerFilter"
```
Expected: FAIL.

- [ ] **Step 3: Create the view**

Create `Sources/Views/PRDashboard/AssigneePicker.swift`:

```swift
import GitHubOperations
import Models
import SwiftUI
import Theme

/// Popover-hosted picker for PR assignees. Shows a top "Assign to me" pill,
/// a search field, and a scrollable list of repo collaborators with
/// check indicators for currently-assigned logins.
public struct AssigneePickerView: View {
    let pr: PullRequest
    let myLogin: String?
    let collaborators: [Collaborator]
    let isLoading: Bool
    let onAssignToMe: () -> Void
    let onUnassignMe: () -> Void
    let onToggle: (String) -> Void

    @State private var query: String = ""
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        myLogin: String?,
        collaborators: [Collaborator],
        isLoading: Bool,
        onAssignToMe: @escaping () -> Void,
        onUnassignMe: @escaping () -> Void,
        onToggle: @escaping (String) -> Void
    ) {
        self.pr = pr
        self.myLogin = myLogin
        self.collaborators = collaborators
        self.isLoading = isLoading
        self.onAssignToMe = onAssignToMe
        self.onUnassignMe = onUnassignMe
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(spacing: 8) {
            mePill
            Divider()
            searchField
            Divider()
            listContent
        }
        .padding(12)
        .frame(width: 360, height: 420)
        .background(theme.chrome.surface)
    }

    // MARK: - Pill

    @ViewBuilder
    private var mePill: some View {
        if let myLogin {
            let isAssigned = pr.assignees.contains(myLogin)
            Button {
                if isAssigned { onUnassignMe() } else { onAssignToMe() }
            } label: {
                HStack {
                    Image(systemName: isAssigned ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                    Text(isAssigned ? "Unassign me" : "Assign to me")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.chrome.green.opacity(0.15))
                )
                .foregroundColor(theme.chrome.green)
            }
            .buttonStyle(.plain)
        } else {
            Text("Resolving your login…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter collaborators…", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.chrome.background))
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if isLoading && collaborators.isEmpty {
            VStack { Spacer(); ProgressView("Loading collaborators…"); Spacer() }
        } else {
            let filtered = Self.filter(collaborators: collaborators, query: query)
            if filtered.isEmpty {
                VStack { Spacer(); Text("No matches").foregroundStyle(.secondary); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { c in
                            row(for: c)
                        }
                    }
                }
            }
        }
    }

    private func row(for c: Collaborator) -> some View {
        let isAssigned = pr.assignees.contains(c.login)
        let isMe = c.login == myLogin
        return Button {
            onToggle(c.login)
        } label: {
            HStack(spacing: 8) {
                AssigneeAvatar(login: c.login, isMe: isMe, size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.login).font(.callout)
                    if let name = c.name, !name.isEmpty {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isAssigned {
                    Image(systemName: "checkmark").foregroundColor(theme.chrome.green)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pure helper (testable)

    public static func filter(collaborators: [Collaborator], query: String) -> [Collaborator] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return collaborators }
        return collaborators.filter { c in
            if c.login.lowercased().contains(q) { return true }
            if let name = c.name?.lowercased(), name.contains(q) { return true }
            return false
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ViewsTests.pickerFilter"
```
Expected: PASS.

- [ ] **Step 5: Build to verify the view compiles**

```bash
swift build
```
Expected: Success.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/PRDashboard/AssigneePicker.swift Tests/ViewsTests/AssigneeAvatarTests.swift
git commit -m "feat(views): add AssigneePickerView with search + Assign to me pill"
```

---

## Task 17: Add assignees row to `PRDetailDrawer`

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDetailDrawer.swift`

- [ ] **Step 1: Add callback parameters**

In `Sources/Views/PRDashboard/PRDetailDrawer.swift`, extend the struct's fields (around line 16-21):

```swift
    var onEnableAutoMerge: ((MergeStrategy) -> Void)?
    var onDisableAutoMerge: (() -> Void)?
    var onClosePR: (() -> Void)?
    var onAssignToMe: (() -> Void)?
    var onUnassignMe: (() -> Void)?
    var onToggleAssignee: ((String) -> Void)?
    var myLogin: String?
    var collaborators: [Collaborator] = []
    var isLoadingCollaborators: Bool = false
    var onLoadCollaborators: (() -> Void)?
```

Extend the `init` signature (around line 39-67) similarly — add matching params with defaults.

Add new state:

```swift
    @State private var showAssigneePicker: Bool = false
```

Also add `import GitHubOperations` at the top.

- [ ] **Step 2: Add the row view**

In the drawer body, between the metadata row and the merge status badge (around line 136, after the `// Review decision` section), add:

```swift
            // Assignees
            assigneesRow
```

Then, in the `// MARK: - Header` section (near the `detailReviewBadge` helper), add:

```swift
    @ViewBuilder
    private var assigneesRow: some View {
        HStack(spacing: 8) {
            Text("Assignees")
                .font(.callout)
                .foregroundColor(theme.chrome.textDim)
            ForEach(pr.assignees, id: \.self) { login in
                AssigneeAvatar(login: login, isMe: login == myLogin, size: 18)
                    .help(login)
            }
            Button {
                onLoadCollaborators?()
                showAssigneePicker = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit assignees")
            .popover(isPresented: $showAssigneePicker, arrowEdge: .bottom) {
                AssigneePickerView(
                    pr: pr,
                    myLogin: myLogin,
                    collaborators: collaborators,
                    isLoading: isLoadingCollaborators,
                    onAssignToMe: { onAssignToMe?(); showAssigneePicker = false },
                    onUnassignMe: { onUnassignMe?(); showAssigneePicker = false },
                    onToggle: { login in onToggleAssignee?(login) }
                )
            }
            Spacer()
        }
        .font(.callout)
    }
```

- [ ] **Step 3: Build to verify**

```bash
swift build
```
Expected: Success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/PRDashboard/PRDetailDrawer.swift
git commit -m "feat(views): add assignees row + picker popover to PRDetailDrawer"
```

---

## Task 18: Wire drawer callbacks through `RunwayStore`

**Files:**
- Modify: `Sources/App/RunwayStore.swift` (or wherever `PRDetailDrawer` is instantiated)
- Modify: `Sources/App/RunwayApp.swift` (likely the call site — confirm via grep)

Before writing, confirm the actual call site — the drawer may be constructed in multiple places.

- [ ] **Step 1: Find every `PRDetailDrawer(` call site**

```bash
grep -rn "PRDetailDrawer(" Sources/
```

Typical result (confirm before editing): `Sources/App/RunwayApp.swift` or `Sources/Views/PRDashboard/PRDashboardView.swift`.

- [ ] **Step 2: Add the new callbacks at each call site**

For each `PRDetailDrawer(...)` invocation, add:

```swift
PRDetailDrawer(
    pr: pr,
    detail: detail,
    // ... existing params ...
    onAssignToMe: { [weak store] in Task { await store?.prCoordinator.assignPRToMe(pr) } },
    onUnassignMe: { [weak store] in Task { await store?.prCoordinator.unassignMeFromPR(pr) } },
    onToggleAssignee: { [weak store] login in
        Task {
            guard let store else { return }
            if pr.assignees.contains(login) {
                await store.prCoordinator.updateAssignees(pr, adding: [], removing: [login])
            } else {
                await store.prCoordinator.updateAssignees(pr, adding: [login], removing: [])
            }
        }
    },
    myLogin: store.prCoordinator.myLogin(forHost: store.prCoordinator.prManager.hostFromURL(pr.url)),
    collaborators: store.prCoordinator.collaboratorsByRepo[pr.repo] ?? [],
    isLoadingCollaborators: false,  // loading state reflected by empty list + in-flight task
    onLoadCollaborators: { [weak store] in
        Task { await store?.prCoordinator.loadCollaborators(for: pr.repo) }
    }
)
```

Use the form that matches the surrounding code (e.g., `self` instead of `[weak store]` if the caller is non-optional).

Also, at a point where the drawer first appears, trigger `warmWhoami`:

```swift
.task {
    store.prCoordinator.warmWhoami(host: store.prCoordinator.prManager.hostFromURL(pr.url))
}
```

- [ ] **Step 3: Build**

```bash
swift build
```
Expected: Success.

- [ ] **Step 4: Run the full test suite**

```bash
swift test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/ Sources/Views/
git commit -m "feat(app): wire assignee callbacks from drawer to PRCoordinator"
```

---

## Task 19: Add `PRTab.assigned` + filter logic

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:478-482` (`PRTab` enum)
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:110-127` (`applyFilters`)
- Test: `Tests/ViewsTests/PRGroupingTests.swift` (or a new `PRTabFilterTests.swift`)

- [ ] **Step 1: Write failing tests**

Append to `Tests/ViewsTests/PRGroupingTests.swift`:

```swift
// MARK: - PRTab.assigned

@Test func prTabAssignedCaseExists() {
    let tabs = PRTab.allCases
    #expect(tabs.contains(.assigned))
    #expect(tabs.count == 4)
}

@Test func prTabAssignedRawValue() {
    #expect(PRTab.assigned.rawValue == "Assigned")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ViewsTests.prTab"
```
Expected: FAIL.

- [ ] **Step 3: Add the case and filter branch**

In `Sources/Views/PRDashboard/PRDashboardView.swift`, line 478-482:

```swift
public enum PRTab: String, CaseIterable, Sendable {
    case all = "All"
    case mine = "Mine"
    case reviewRequested = "Review Requests"
    case assigned = "Assigned"
}
```

In the same file, `applyFilters` (line 110-120), add the case:

```swift
    private func applyFilters(to prs: [PullRequest], tab: PRTab) -> [PullRequest] {
        var result = prs

        switch tab {
        case .all:
            break
        case .mine:
            result = result.filter { $0.origin.contains(.mine) }
        case .reviewRequested:
            result = result.filter { $0.origin.contains(.reviewRequested) }
        case .assigned:
            result = result.filter { $0.origin.contains(.assigned) }
        }

        if showSessionPRsOnly {
            result = result.filter { sessionPRIDs.contains($0.id) }
        }

        return result
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ViewsTests.prTab"
```
Expected: PASS.

- [ ] **Step 5: Run the full test suite**

```bash
swift test
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift Tests/ViewsTests/PRGroupingTests.swift
git commit -m "feat(views): add Assigned tab to PR dashboard"
```

---

## Task 20: Add "Assignees" `TableColumn` to `PRDashboardView`

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift` (insert a new `TableColumn` between Author and Age)

- [ ] **Step 1: Ensure the view has access to `PRCoordinator`**

Grep for how `PRDashboardView` currently accesses the coordinator:

```bash
grep -n "prCoordinator\|PRCoordinator" Sources/Views/PRDashboard/PRDashboardView.swift
```

If it isn't already wired in, add a `@Environment` or injected binding for `myLogin(forHost:)` lookups. Looking at the existing fields (around line 6-105), use whatever pattern matches (e.g., if the view already takes callbacks like `onSelectPR`, add a `myLoginForHost: (String?) -> String?` closure).

Preferred approach — add a closure parameter rather than a strong `@Environment` reference (keeps Views module independent of App):

```swift
    let myLoginForHost: (String?) -> String?
```

Plumb it through the init + call site (`RunwayApp.swift` or wherever `PRDashboardView(…)` is invoked) as:

```swift
myLoginForHost: { host in store.prCoordinator.myLogin(forHost: host) }
```

- [ ] **Step 2: Insert the new TableColumn**

In `Sources/Views/PRDashboard/PRDashboardView.swift`, between the "Author" column (line 240-246) and the "Age" column (line 248-253), add:

```swift
            TableColumn("Assignees", value: \.assigneeSortKey) { pr in
                if !pr.assignees.isEmpty {
                    let me = myLoginForHost(hostFromURL(pr.url))
                    HStack(spacing: -4) {
                        ForEach(pr.assignees.prefix(3), id: \.self) { login in
                            AssigneeAvatar(login: login, isMe: login == me, size: 14)
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

Add a tiny helper in the same file (near the other cell helpers around line 366):

```swift
    private func hostFromURL(_ url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host else { return nil }
        return host == "github.com" ? nil : host
    }
```

- [ ] **Step 3: Update call site**

At the `PRDashboardView(…)` call site, add the new closure:

```swift
PRDashboardView(
    // ... existing params ...
    myLoginForHost: { host in store.prCoordinator.myLogin(forHost: host) }
)
```

- [ ] **Step 4: Build**

```bash
swift build
```
Expected: Success.

- [ ] **Step 5: Run the full test suite**

```bash
swift test
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift Sources/App/
git commit -m "feat(views): add Assignees TableColumn to PR dashboard"
```

---

## Task 21: Final verification — tests + manual smoke

**Files:** none

- [ ] **Step 1: Full test suite**

```bash
swift test
```
Expected: PASS. No new warnings.

- [ ] **Step 2: Format + lint**

```bash
make check
```
Expected: All checks pass (build + test + lint + format).

- [ ] **Step 3: Manual smoke test**

Launch the app:

```bash
swift run Runway
```

Checklist:

- [ ] PR dashboard loads with four tabs: All, Mine, Review Requests, Assigned.
- [ ] "Assigned" tab shows only PRs you're assigned to (verify by assigning yourself via GitHub web UI to a PR, wait <60s for poll, see it appear).
- [ ] The "Assignees" column shows avatars for PRs with assignees, nothing for PRs without.
- [ ] Hovering an avatar shows the login in a tooltip (macOS `.help()`).
- [ ] Opening a PR drawer shows the "Assignees" row with avatars.
- [ ] Clicking "+" opens the popover picker. "Assign to me" pill is visible.
- [ ] Clicking "Assign to me" closes the popover, updates the avatar row instantly (optimistic), and the PR appears in the "Assigned" tab after refresh.
- [ ] Clicking "Unassign me" reverses the action.
- [ ] Searching the picker filters by login and name (type "alice" — only "alice-*" matches).
- [ ] Toggling a non-me collaborator's row adds/removes them.
- [ ] Closing and reopening the picker within 10 minutes loads instantly (collaborator cache hit).
- [ ] The "me" avatar uses the theme green; other avatars use the hash palette.
- [ ] Avatar colors stay the same after restarting the app (stable hash — do `Cmd+Q` then relaunch).

- [ ] **Step 4: Final push**

```bash
git push
```

Create PR via the project's normal flow (`/simplify` → `/pre-ship` → `/ship-it`, or manual `gh pr create`).

---

## Notes for Implementers

- **TDD discipline:** Write the failing test first, run it to see the failure, then implement. Skipping the red step hides bugs in the test itself.
- **Commit granularity:** Each task ends in one commit. If a task grows, split it — don't batch.
- **Optimistic UI revert:** The revert path in `updateAssignees` is best-effort. If `refreshPRAfterAction` runs and the server state disagrees, enrichment will overwrite — which is the desired safety net.
- **`whoami` host semantics:** `nil` host maps to `""` in the cache dictionary (canonical for github.com). Keep this consistent across reads and writes.
- **Test fixtures:** JSON test fixtures use real GitHub response shapes. If a test fails after a `gh` version bump, check whether the CLI's JSON output changed shape.
- **Existing `ManageAssigneesSheet`:** The Issues view has a similar component. For v1, keep the PR picker separate to avoid coupling two unrelated flows. A future refactor can extract shared primitives if both surfaces evolve together.
