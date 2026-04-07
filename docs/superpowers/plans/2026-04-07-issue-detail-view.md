# Issue Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend GitHub Issues to full PR parity — detail drawer with body, full timeline, comments, and all mutation actions (edit, close/reopen, label/assignee management).

**Architecture:** Mirror the PR pattern exactly. `IssueDetail` lazy-loaded struct fetched via `IssueManager`, displayed in `IssueDetailDrawer` with tabs, wired through `RunwayStore` and `ProjectPageView`. Project-scoped only (inside `ProjectIssuesTab`).

**Tech Stack:** Swift, SwiftUI, `gh` CLI, GRDB (existing), Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-04-07-issue-detail-view-design.md`

---

### Task 1: Add `repo` Field to `GitHubIssue` and New Model Types

**Files:**
- Modify: `Sources/Models/GitHubIssue.swift`
- Modify: `Sources/GitHubOperations/IssueManager.swift:151-169` (GHIssueItem.toGitHubIssue)
- Test: `Tests/GitHubOperationsTests/IssueManagerTests.swift` (new file)

- [ ] **Step 1: Create test file with model tests**

Create `Tests/GitHubOperationsTests/IssueManagerTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import GitHubOperations

// MARK: - IssueDetail

@Test func issueDetailDefaults() {
    let detail = IssueDetail()
    #expect(detail.body.isEmpty)
    #expect(detail.comments.isEmpty)
    #expect(detail.timelineEvents.isEmpty)
    #expect(detail.labels.isEmpty)
    #expect(detail.assignees.isEmpty)
    #expect(detail.milestone == nil)
    #expect(detail.stateReason == nil)
}

@Test func issueDetailWithData() {
    let comment = IssueComment(id: "1", author: "alice", body: "Looks good")
    let event = IssueTimelineEvent(
        id: "labeled-alice-2026-01-01",
        event: "labeled",
        actor: "alice",
        createdAt: Date(),
        label: IssueDetailLabel(name: "bug", color: "d73a4a")
    )

    let detail = IssueDetail(
        body: "## Bug Report\nSomething is broken",
        comments: [comment],
        timelineEvents: [event],
        labels: [IssueDetailLabel(name: "bug", color: "d73a4a")],
        assignees: ["alice"]
    )

    #expect(detail.body.contains("Bug Report"))
    #expect(detail.comments.count == 1)
    #expect(detail.comments.first?.author == "alice")
    #expect(detail.timelineEvents.count == 1)
    #expect(detail.timelineEvents.first?.event == "labeled")
    #expect(detail.labels.first?.name == "bug")
    #expect(detail.assignees == ["alice"])
}

// MARK: - IssueComment

@Test func issueCommentIdentifiable() {
    let c = IssueComment(id: "42", author: "bob", body: "test")
    #expect(c.id == "42")
}

// MARK: - IssueTimelineEvent

@Test func timelineEventCrossReference() {
    let ref = IssueReference(type: "pullRequest", number: 45, title: "Fix bug", url: "https://github.com/owner/repo/pull/45")
    let event = IssueTimelineEvent(
        id: "xref-1",
        event: "cross-referenced",
        actor: "alice",
        createdAt: Date(),
        source: ref
    )
    #expect(event.source?.type == "pullRequest")
    #expect(event.source?.number == 45)
}

@Test func timelineEventRename() {
    let rename = IssueRename(from: "Old title", to: "New title")
    let event = IssueTimelineEvent(
        id: "rename-1",
        event: "renamed",
        actor: "bob",
        createdAt: Date(),
        rename: rename
    )
    #expect(event.rename?.from == "Old title")
    #expect(event.rename?.to == "New title")
}

// MARK: - CloseReason

@Test func closeReasonDisplayNames() {
    #expect(CloseReason.completed.displayName == "Completed")
    #expect(CloseReason.notPlanned.displayName == "Not planned")
}

@Test func closeReasonCaseIterable() {
    #expect(CloseReason.allCases.count == 2)
}

// MARK: - GitHubIssue repo field

@Test func gitHubIssueHasRepo() {
    let issue = GitHubIssue(
        number: 42,
        title: "Test",
        state: .open,
        author: "alice",
        repo: "owner/repo"
    )
    #expect(issue.repo == "owner/repo")
    #expect(issue.id == "owner/repo#42")
}

// MARK: - IssueManager Actor

@Test func issueManagerCanBeCreated() async {
    let manager = IssueManager()
    _ = manager
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IssueManagerTests 2>&1 | tail -20`
Expected: Compilation errors — `IssueDetail`, `IssueComment`, `IssueTimelineEvent`, `CloseReason` not found, `GitHubIssue` missing `repo` parameter.

- [ ] **Step 3: Add `repo` field to `GitHubIssue`**

In `Sources/Models/GitHubIssue.swift`, add `repo` to the struct and init:

```swift
public struct GitHubIssue: Identifiable, Codable, Sendable {
    public let id: String  // "owner/repo#123"
    public let number: Int
    public var title: String
    public var state: IssueState
    public var author: String
    public var repo: String
    public var labels: [String]
    public var assignees: [String]
    public var url: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        number: Int, title: String, state: IssueState, author: String, repo: String,
        labels: [String] = [], assignees: [String] = [], url: String = "",
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = "\(repo)#\(number)"
        self.number = number
        self.title = title
        self.state = state
        self.author = author
        self.repo = repo
        self.labels = labels
        self.assignees = assignees
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

Note: The `repo` parameter already exists in the init (used to build `id`), but was not stored as a field. Add `self.repo = repo` and the property declaration.

Also add a custom decoder for backwards compatibility with cached JSON that doesn't have `repo`:

```swift
extension GitHubIssue {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.number = try container.decode(Int.self, forKey: .number)
        self.title = try container.decode(String.self, forKey: .title)
        self.state = try container.decode(IssueState.self, forKey: .state)
        self.author = try container.decode(String.self, forKey: .author)
        self.labels = try container.decode([String].self, forKey: .labels)
        self.assignees = try container.decode([String].self, forKey: .assignees)
        self.url = try container.decode(String.self, forKey: .url)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Backwards compat: derive repo from id ("owner/repo#123" → "owner/repo")
        if let repo = try container.decodeIfPresent(String.self, forKey: .repo) {
            self.repo = repo
        } else if let hashIndex = id.lastIndex(of: "#") {
            self.repo = String(id[id.startIndex..<hashIndex])
        } else {
            self.repo = ""
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, title, state, author, repo, labels, assignees, url, createdAt, updatedAt
    }
}
```

- [ ] **Step 4: Add `IssueDetail` and supporting types**

Append to `Sources/Models/GitHubIssue.swift` after the `IssueState` enum:

```swift
// MARK: - Issue Detail (lazy-loaded)

public struct IssueDetail: Codable, Sendable {
    public var body: String
    public var comments: [IssueComment]
    public var timelineEvents: [IssueTimelineEvent]
    public var labels: [IssueDetailLabel]
    public var assignees: [String]
    public var milestone: String?
    public var stateReason: String?

    public init(
        body: String = "",
        comments: [IssueComment] = [],
        timelineEvents: [IssueTimelineEvent] = [],
        labels: [IssueDetailLabel] = [],
        assignees: [String] = [],
        milestone: String? = nil,
        stateReason: String? = nil
    ) {
        self.body = body
        self.comments = comments
        self.timelineEvents = timelineEvents
        self.labels = labels
        self.assignees = assignees
        self.milestone = milestone
        self.stateReason = stateReason
    }
}

public struct IssueComment: Identifiable, Codable, Sendable {
    public let id: String
    public var author: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, author: String, body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct IssueTimelineEvent: Identifiable, Codable, Sendable {
    public let id: String
    public var event: String
    public var actor: String
    public var createdAt: Date
    public var label: IssueDetailLabel?
    public var assignee: String?
    public var source: IssueReference?
    public var rename: IssueRename?

    public init(
        id: String, event: String, actor: String, createdAt: Date = Date(),
        label: IssueDetailLabel? = nil, assignee: String? = nil,
        source: IssueReference? = nil, rename: IssueRename? = nil
    ) {
        self.id = id
        self.event = event
        self.actor = actor
        self.createdAt = createdAt
        self.label = label
        self.assignee = assignee
        self.source = source
        self.rename = rename
    }
}

public struct IssueDetailLabel: Codable, Sendable, Hashable {
    public var name: String
    public var color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct IssueReference: Codable, Sendable {
    public var type: String
    public var number: Int
    public var title: String
    public var url: String

    public init(type: String, number: Int, title: String, url: String) {
        self.type = type
        self.number = number
        self.title = title
        self.url = url
    }
}

public struct IssueRename: Codable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

// MARK: - Close Reason

public enum CloseReason: String, Codable, Sendable, CaseIterable {
    case completed
    case notPlanned = "not planned"

    public var displayName: String {
        switch self {
        case .completed: "Completed"
        case .notPlanned: "Not planned"
        }
    }
}
```

- [ ] **Step 5: Update `GHIssueItem.toGitHubIssue` to pass `repo` through**

In `Sources/GitHubOperations/IssueManager.swift`, the `toGitHubIssue(repo:)` method already receives `repo` and passes it to the init. Since the init already had `repo` as a parameter (used for building `id`), and we just added storage, no change is needed here. Verify that the existing code at line 152 already works:

```swift
func toGitHubIssue(repo: String) -> GitHubIssue {
    // ... existing code passes repo: repo in GitHubIssue init — this now also stores it
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter IssueManagerTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Models/GitHubIssue.swift Tests/GitHubOperationsTests/IssueManagerTests.swift
git commit -m "feat: add IssueDetail model types and repo field on GitHubIssue"
```

---

### Task 2: Add `IssueManager` Detail Fetching and Mutations

**Files:**
- Modify: `Sources/GitHubOperations/IssueManager.swift`
- Test: `Tests/GitHubOperationsTests/IssueManagerTests.swift`

- [ ] **Step 1: Add detail cache and eviction to `IssueManager`**

Add inside the `IssueManager` actor, after the `init()`:

```swift
// MARK: - Detail Cache

private var detailCache: [String: (detail: IssueDetail, fetchedAt: Date)] = [:]
private let detailTTL: TimeInterval = 300

/// Evict cached detail for an issue (call after mutations).
public func evictDetail(repo: String, number: Int) {
    detailCache.removeValue(forKey: "\(repo)#\(number)")
}
```

- [ ] **Step 2: Add `fetchDetail` method**

Add after the `fetchLabels` method:

```swift
/// Fetch full issue detail: body, comments, labels, assignees, timeline.
public func fetchDetail(repo: String, number: Int, host: String? = nil) async throws -> IssueDetail {
    let key = "\(repo)#\(number)"
    if let cached = detailCache[key], Date().timeIntervalSince(cached.fetchedAt) < detailTTL {
        return cached.detail
    }

    // Call 1: issue metadata + comments
    let viewArgs = [
        "issue", "view", String(number),
        "--repo", repo,
        "--json", "body,comments,labels,assignees,milestone,stateReason",
    ]
    let viewOutput = try await runGH(args: viewArgs, host: host)

    // Call 2: full timeline via REST API
    let timelineArgs = [
        "api", "repos/\(repo)/issues/\(number)/timeline",
        "--paginate",
    ]
    let timelineOutput = try await runGH(args: timelineArgs, host: host)

    let detail = try parseIssueDetail(viewJSON: viewOutput, timelineJSON: timelineOutput)
    detailCache[key] = (detail, Date())
    return detail
}
```

- [ ] **Step 3: Add mutation methods**

Add after `fetchDetail`:

```swift
// MARK: - Mutations

/// Edit issue title and/or body.
public func editIssue(repo: String, number: Int, host: String? = nil, title: String?, body: String?) async throws {
    var args = ["issue", "edit", String(number), "--repo", repo]
    if let title { args += ["--title", title] }
    if let body { args += ["--body", body] }
    try await runGH(args: args, host: host)
    evictDetail(repo: repo, number: number)
}

/// Add a comment to an issue.
public func addComment(repo: String, number: Int, host: String? = nil, body: String) async throws {
    let args = ["issue", "comment", String(number), "--repo", repo, "--body", body]
    try await runGH(args: args, host: host)
    evictDetail(repo: repo, number: number)
}

/// Close an issue with a reason.
public func closeIssue(repo: String, number: Int, host: String? = nil, reason: CloseReason) async throws {
    var args = ["issue", "close", String(number), "--repo", repo]
    switch reason {
    case .completed:
        args += ["--reason", "completed"]
    case .notPlanned:
        args += ["--reason", "not planned"]
    }
    try await runGH(args: args, host: host)
    evictDetail(repo: repo, number: number)
}

/// Reopen a closed issue.
public func reopenIssue(repo: String, number: Int, host: String? = nil) async throws {
    let args = ["issue", "reopen", String(number), "--repo", repo]
    try await runGH(args: args, host: host)
    evictDetail(repo: repo, number: number)
}

/// Update labels on an issue (add and/or remove).
public func updateLabels(repo: String, number: Int, host: String? = nil, add: [String], remove: [String]) async throws {
    var args = ["issue", "edit", String(number), "--repo", repo]
    for label in add { args += ["--add-label", label] }
    for label in remove { args += ["--remove-label", label] }
    try await runGH(args: args, host: host)
    evictDetail(repo: repo, number: number)
}

/// Update assignees on an issue (add and/or remove).
public func updateAssignees(repo: String, number: Int, host: String? = nil, add: [String], remove: [String]) async throws {
    var args = ["issue", "edit", String(number), "--repo", repo]
    for assignee in add { args += ["--add-assignee", assignee] }
    for assignee in remove { args += ["--remove-assignee", assignee] }
    try await runGH(args: args, host: host)
    evictDetail(repo: repo, number: number)
}
```

- [ ] **Step 4: Add JSON parsing for issue detail**

Add to the `// MARK: - Private` section:

```swift
private func parseIssueDetail(viewJSON: String, timelineJSON: String) throws -> IssueDetail {
    guard let viewData = viewJSON.data(using: .utf8) else {
        return IssueDetail()
    }
    let viewItem = try JSONDecoder.issueGH.decode(GHIssueViewItem.self, from: viewData)

    // Parse comments from gh issue view
    let comments: [IssueComment] = (viewItem.comments ?? []).map { c in
        IssueComment(
            id: String(c.id ?? UUID().uuidString),
            author: c.author?.login ?? "",
            body: c.body ?? "",
            createdAt: c.createdAt ?? Date(),
            updatedAt: c.updatedAt ?? c.createdAt ?? Date()
        )
    }

    // Parse labels
    let labels: [IssueDetailLabel] = (viewItem.labels ?? []).map { l in
        IssueDetailLabel(name: l.name, color: l.color ?? "")
    }

    // Parse assignees
    let assignees: [String] = (viewItem.assignees ?? []).map { $0.login }

    // Parse milestone
    let milestone = viewItem.milestone?.title

    // Parse timeline events (filtering out "commented" — we use richer comments from above)
    var timelineEvents: [IssueTimelineEvent] = []
    if let timelineData = timelineJSON.data(using: .utf8) {
        let rawEvents = (try? JSONDecoder.issueGH.decode([GHTimelineEvent].self, from: timelineData)) ?? []
        for (index, raw) in rawEvents.enumerated() {
            guard let event = raw.event, event != "commented" else { continue }
            let actor = raw.actor?.login ?? ""
            let id = "\(event)-\(actor)-\(index)"
            var label: IssueDetailLabel?
            if let l = raw.label {
                label = IssueDetailLabel(name: l.name, color: l.color ?? "")
            }
            var assignee: String?
            if let a = raw.assignee {
                assignee = a.login
            }
            var source: IssueReference?
            if let s = raw.source?.issue {
                let type = s.pullRequest != nil ? "pullRequest" : "issue"
                source = IssueReference(
                    type: type,
                    number: s.number ?? 0,
                    title: s.title ?? "",
                    url: s.htmlURL ?? ""
                )
            }
            var rename: IssueRename?
            if let r = raw.rename {
                rename = IssueRename(from: r.from ?? "", to: r.to ?? "")
            }
            timelineEvents.append(IssueTimelineEvent(
                id: id,
                event: event,
                actor: actor,
                createdAt: raw.createdAt ?? Date(),
                label: label,
                assignee: assignee,
                source: source,
                rename: rename
            ))
        }
    }

    return IssueDetail(
        body: viewItem.body ?? "",
        comments: comments,
        timelineEvents: timelineEvents,
        labels: labels,
        assignees: assignees,
        milestone: milestone,
        stateReason: viewItem.stateReason
    )
}
```

- [ ] **Step 5: Add GH JSON decode structs for detail parsing**

Add at the bottom of the file, in the private GH JSON section:

```swift
// MARK: - GH Issue View JSON

private struct GHIssueViewItem: Decodable {
    let body: String?
    let comments: [GHIssueCommentItem]?
    let labels: [GHIssueViewLabel]?
    let assignees: [GHIssueAssignee]?
    let milestone: GHMilestone?
    let stateReason: String?
}

private struct GHIssueCommentItem: Decodable {
    let id: String?
    let author: GHIssueAuthor?
    let body: String?
    let createdAt: Date?
    let updatedAt: Date?
}

private struct GHIssueViewLabel: Decodable {
    let name: String
    let color: String?
}

private struct GHMilestone: Decodable {
    let title: String?
}

// MARK: - GH Timeline JSON

private struct GHTimelineEvent: Decodable {
    let event: String?
    let actor: GHIssueAuthor?
    let createdAt: Date?
    let label: GHTimelineLabel?
    let assignee: GHIssueAssignee?
    let source: GHTimelineSource?
    let rename: GHTimelineRename?

    enum CodingKeys: String, CodingKey {
        case event, actor, label, assignee, source, rename
        case createdAt = "created_at"
    }
}

private struct GHTimelineLabel: Decodable {
    let name: String
    let color: String?
}

private struct GHTimelineSource: Decodable {
    let issue: GHTimelineSourceIssue?
}

private struct GHTimelineSourceIssue: Decodable {
    let number: Int?
    let title: String?
    let htmlURL: String?
    let pullRequest: GHTimelinePullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number, title, pullRequest
        case htmlURL = "html_url"
    }
}

private struct GHTimelinePullRequestMarker: Decodable {}

private struct GHTimelineRename: Decodable {
    let from: String?
    let to: String?
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter IssueManagerTests 2>&1 | tail -20`
Expected: All tests PASS. (Mutation methods call `runGH` which needs a real `gh` CLI — we test model parsing and initialization, not CLI invocation.)

- [ ] **Step 7: Commit**

```bash
git add Sources/GitHubOperations/IssueManager.swift Tests/GitHubOperationsTests/IssueManagerTests.swift
git commit -m "feat: add IssueManager detail fetching and mutation methods"
```

---

### Task 3: Add Issue Detail State and Actions to `RunwayStore`

**Files:**
- Modify: `Sources/App/RunwayStore.swift`

- [ ] **Step 1: Add issue detail state variables**

In `Sources/App/RunwayStore.swift`, after line 64 (`issueLastFetched`), add:

```swift
var selectedIssueID: String?
var issueDetail: IssueDetail?
var isLoadingIssueDetail: Bool = false
```

- [ ] **Step 2: Add `selectIssue` method**

In the `// MARK: - Issues` section, after `openIssueInBrowser` (line 977), add:

```swift
func selectIssue(_ issue: GitHubIssue?) async {
    selectedIssueID = issue?.id
    issueDetail = nil
    guard let issue else { return }

    isLoadingIssueDetail = true
    defer { isLoadingIssueDetail = false }

    do {
        let host = issue.url.contains("github.com") ? nil : extractHost(from: issue.url)
        let detail = try await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: host)
        issueDetail = detail
    } catch {
        print("[Runway] Failed to fetch issue detail: \(error)")
    }
}

private func extractHost(from urlString: String) -> String? {
    guard let url = URL(string: urlString), let host = url.host, host != "github.com" else { return nil }
    return host
}
```

- [ ] **Step 3: Add mutation methods**

Add after `selectIssue`:

```swift
func editIssue(_ issue: GitHubIssue, title: String?, body: String?) async {
    guard let project = projectForIssue(issue) else { return }
    do {
        try await issueManager.editIssue(repo: issue.repo, number: issue.number, host: project.ghHost, title: title, body: body)
        statusMessage = .success("Issue #\(issue.number) updated")
        issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
        await fetchIssues(forProject: project.id)
    } catch {
        statusMessage = .error("Edit failed: \(error.localizedDescription)")
    }
}

func commentOnIssue(_ issue: GitHubIssue, body: String) async {
    guard let project = projectForIssue(issue) else { return }
    do {
        try await issueManager.addComment(repo: issue.repo, number: issue.number, host: project.ghHost, body: body)
        issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
    } catch {
        statusMessage = .error("Comment failed: \(error.localizedDescription)")
    }
}

func closeIssue(_ issue: GitHubIssue, reason: CloseReason) async {
    guard let project = projectForIssue(issue) else { return }
    do {
        try await issueManager.closeIssue(repo: issue.repo, number: issue.number, host: project.ghHost, reason: reason)
        statusMessage = .success("Closed #\(issue.number)")
        issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
        await fetchIssues(forProject: project.id)
    } catch {
        statusMessage = .error("Close failed: \(error.localizedDescription)")
    }
}

func reopenIssue(_ issue: GitHubIssue) async {
    guard let project = projectForIssue(issue) else { return }
    do {
        try await issueManager.reopenIssue(repo: issue.repo, number: issue.number, host: project.ghHost)
        statusMessage = .success("Reopened #\(issue.number)")
        issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
        await fetchIssues(forProject: project.id)
    } catch {
        statusMessage = .error("Reopen failed: \(error.localizedDescription)")
    }
}

func updateIssueLabels(_ issue: GitHubIssue, add: [String], remove: [String]) async {
    guard let project = projectForIssue(issue) else { return }
    do {
        try await issueManager.updateLabels(repo: issue.repo, number: issue.number, host: project.ghHost, add: add, remove: remove)
        statusMessage = .success("Labels updated")
        issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
        await fetchIssues(forProject: project.id)
    } catch {
        statusMessage = .error("Label update failed: \(error.localizedDescription)")
    }
}

func updateIssueAssignees(_ issue: GitHubIssue, add: [String], remove: [String]) async {
    guard let project = projectForIssue(issue) else { return }
    do {
        try await issueManager.updateAssignees(repo: issue.repo, number: issue.number, host: project.ghHost, add: add, remove: remove)
        statusMessage = .success("Assignees updated")
        issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
        await fetchIssues(forProject: project.id)
    } catch {
        statusMessage = .error("Assignee update failed: \(error.localizedDescription)")
    }
}

private func projectForIssue(_ issue: GitHubIssue) -> Project? {
    projects.first(where: { $0.ghRepo == issue.repo })
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: add issue detail state and mutation actions to RunwayStore"
```

---

### Task 4: Create `EditIssueSheet`

**Files:**
- Create: `Sources/Views/ProjectPage/EditIssueSheet.swift`

- [ ] **Step 1: Create `EditIssueSheet`**

Create `Sources/Views/ProjectPage/EditIssueSheet.swift`:

```swift
import Models
import SwiftUI
import Theme

public struct EditIssueSheet: View {
    let issue: GitHubIssue
    let currentBody: String
    let onSave: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var title: String
    @State private var issueBody: String

    public init(
        issue: GitHubIssue,
        currentBody: String,
        onSave: @escaping (String?, String?) -> Void
    ) {
        self.issue = issue
        self.currentBody = currentBody
        self.onSave = onSave
        self._title = State(initialValue: issue.title)
        self._issueBody = State(initialValue: currentBody)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Issue #\(issue.number)")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Title field
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextField("Issue title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Body text area
            VStack(alignment: .leading, spacing: 4) {
                Text("Body")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextEditor(text: $issueBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.chrome.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer(minLength: 0)

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTitle = title != issue.title ? title : nil
                    let newBody = issueBody != currentBody ? issueBody : nil
                    if newTitle != nil || newBody != nil {
                        onSave(newTitle, newBody)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/ProjectPage/EditIssueSheet.swift
git commit -m "feat: add EditIssueSheet for editing issue title and body"
```

---

### Task 5: Create `ManageLabelsSheet` and `ManageAssigneesSheet`

**Files:**
- Create: `Sources/Views/ProjectPage/ManageLabelsSheet.swift`
- Create: `Sources/Views/ProjectPage/ManageAssigneesSheet.swift`

- [ ] **Step 1: Create `ManageLabelsSheet`**

Create `Sources/Views/ProjectPage/ManageLabelsSheet.swift`:

```swift
import GitHubOperations
import Models
import SwiftUI
import Theme

public struct ManageLabelsSheet: View {
    let availableLabels: [IssueLabel]
    let currentLabels: [IssueDetailLabel]
    let onSave: ([String], [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var selectedNames: Set<String>

    public init(
        availableLabels: [IssueLabel],
        currentLabels: [IssueDetailLabel],
        onSave: @escaping ([String], [String]) -> Void
    ) {
        self.availableLabels = availableLabels
        self.currentLabels = currentLabels
        self.onSave = onSave
        self._selectedNames = State(initialValue: Set(currentLabels.map(\.name)))
    }

    private var originalNames: Set<String> {
        Set(currentLabels.map(\.name))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Labels")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableLabels) { label in
                        Button {
                            if selectedNames.contains(label.name) {
                                selectedNames.remove(label.name)
                            } else {
                                selectedNames.insert(label.name)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedNames.contains(label.name) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedNames.contains(label.name) ? theme.chrome.accent : theme.chrome.textDim)
                                Circle()
                                    .fill(Color(hex: label.color) ?? theme.chrome.accent)
                                    .frame(width: 12, height: 12)
                                Text(label.name)
                                    .font(.body)
                                    .foregroundColor(theme.chrome.text)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let add = Array(selectedNames.subtracting(originalNames))
                    let remove = Array(originalNames.subtracting(selectedNames))
                    if !add.isEmpty || !remove.isEmpty {
                        onSave(add, remove)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350, height: 400)
    }
}
```

- [ ] **Step 2: Create `ManageAssigneesSheet`**

Create `Sources/Views/ProjectPage/ManageAssigneesSheet.swift`:

```swift
import Models
import SwiftUI
import Theme

public struct ManageAssigneesSheet: View {
    let currentAssignees: [String]
    let onSave: ([String], [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var assignees: [String]
    @State private var newAssignee: String = ""

    public init(
        currentAssignees: [String],
        onSave: @escaping ([String], [String]) -> Void
    ) {
        self.currentAssignees = currentAssignees
        self.onSave = onSave
        self._assignees = State(initialValue: currentAssignees)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Assignees")
                .font(.title3)
                .fontWeight(.semibold)

            // Add assignee field
            HStack(spacing: 8) {
                TextField("Username", text: $newAssignee)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addAssignee() }
                Button("Add") { addAssignee() }
                    .disabled(newAssignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Current assignees list
            if assignees.isEmpty {
                Text("No assignees")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(assignees, id: \.self) { assignee in
                            HStack {
                                Label(assignee, systemImage: "person")
                                    .font(.body)
                                Spacer()
                                Button {
                                    assignees.removeAll { $0 == assignee }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(theme.chrome.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let originalSet = Set(currentAssignees)
                    let currentSet = Set(assignees)
                    let add = Array(currentSet.subtracting(originalSet))
                    let remove = Array(originalSet.subtracting(currentSet))
                    if !add.isEmpty || !remove.isEmpty {
                        onSave(add, remove)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350, height: 350)
    }

    private func addAssignee() {
        let trimmed = newAssignee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !assignees.contains(trimmed) else { return }
        assignees.append(trimmed)
        newAssignee = ""
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/ProjectPage/ManageLabelsSheet.swift Sources/Views/ProjectPage/ManageAssigneesSheet.swift
git commit -m "feat: add ManageLabelsSheet and ManageAssigneesSheet"
```

---

### Task 6: Create `IssueDetailDrawer`

**Files:**
- Create: `Sources/Views/ProjectPage/IssueDetailDrawer.swift`

This is the largest new file. It mirrors `PRDetailDrawer` (Sources/Views/PRDashboard/PRDetailDrawer.swift) with Issue-specific tabs: Overview and Timeline.

- [ ] **Step 1: Create `IssueDetailDrawer` with header and action bar**

Create `Sources/Views/ProjectPage/IssueDetailDrawer.swift`:

```swift
import GitHubOperations
import Models
import SwiftUI
import Theme

/// Detail drawer for a selected GitHub issue, showing body, timeline, and actions.
public struct IssueDetailDrawer: View {
    let issue: GitHubIssue
    let detail: IssueDetail?
    let labels: [IssueLabel]
    let isLoading: Bool
    let onClose: () -> Void
    let onComment: (String) -> Void
    let onClose_issue: (CloseReason) -> Void
    let onReopen: () -> Void
    let onEdit: (String?, String?) -> Void
    let onUpdateLabels: ([String], [String]) -> Void
    let onUpdateAssignees: ([String], [String]) -> Void

    @State private var selectedTab: IssueDetailTab = .overview
    @State private var inlineCommentText: String = ""
    @State private var activeSheet: ActiveSheet?

    enum ActiveSheet: Identifiable {
        case edit
        case labels
        case assignees

        var id: String { String(describing: self) }
    }

    @Environment(\.theme) private var theme

    public init(
        issue: GitHubIssue,
        detail: IssueDetail? = nil,
        labels: [IssueLabel] = [],
        isLoading: Bool = false,
        onClose: @escaping () -> Void = {},
        onComment: @escaping (String) -> Void = { _ in },
        onCloseIssue: @escaping (CloseReason) -> Void = { _ in },
        onReopen: @escaping () -> Void = {},
        onEdit: @escaping (String?, String?) -> Void = { _, _ in },
        onUpdateLabels: @escaping ([String], [String]) -> Void = { _, _ in },
        onUpdateAssignees: @escaping ([String], [String]) -> Void = { _, _ in }
    ) {
        self.issue = issue
        self.detail = detail
        self.labels = labels
        self.isLoading = isLoading
        self.onClose = onClose
        self.onComment = onComment
        self.onClose_issue = onCloseIssue
        self.onReopen = onReopen
        self.onEdit = onEdit
        self.onUpdateLabels = onUpdateLabels
        self.onUpdateAssignees = onUpdateAssignees
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            if isLoading && detail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tabContent
            }
        }
        .background(theme.chrome.background)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit:
                EditIssueSheet(
                    issue: issue,
                    currentBody: detail?.body ?? "",
                    onSave: onEdit
                )
            case .labels:
                ManageLabelsSheet(
                    availableLabels: labels,
                    currentLabels: detail?.labels ?? [],
                    onSave: onUpdateLabels
                )
            case .assignees:
                ManageAssigneesSheet(
                    currentAssignees: detail?.assignees ?? issue.assignees,
                    onSave: onUpdateAssignees
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                stateBadge
                Text("#\(issue.number)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(issue.title)
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Label(issue.author, systemImage: "person")
                Text(issue.createdAt, style: .relative)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Labels
            let detailLabels = detail?.labels ?? []
            if !detailLabels.isEmpty {
                FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(detailLabels, id: \.name) { label in
                        IssueLabelPill(label: label)
                    }
                }
            }

            // Assignees
            let assignees = detail?.assignees ?? issue.assignees
            if !assignees.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(assignees, id: \.self) { assignee in
                        Text(assignee)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Action bar
            HStack(spacing: 8) {
                if issue.state == .open {
                    Menu {
                        Button("Completed") { onClose_issue(.completed) }
                        Button("Not planned") { onClose_issue(.notPlanned) }
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                } else {
                    Button("Reopen") { onReopen() }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.chrome.green)
                        .controlSize(.small)
                }

                Button("Edit") { activeSheet = .edit }
                    .controlSize(.small)

                Button("Labels") { activeSheet = .labels }
                    .controlSize(.small)

                Button("Assignees") { activeSheet = .assignees }
                    .controlSize(.small)

                Spacer()

                Button {
                    if let url = URL(string: issue.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .controlSize(.small)
                .help("Open in browser")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch issue.state {
        case .open:
            Label("Open", systemImage: "circle.fill")
                .font(.callout)
                .foregroundColor(theme.chrome.green)
        case .closed:
            Label("Closed", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundColor(theme.chrome.purple)
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(IssueDetailTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text(tabTitle(tab))
                                .font(.subheadline)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                            Text("^\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundColor(selectedTab == tab ? theme.chrome.accent : theme.chrome.textDim)

                        Rectangle()
                            .fill(selectedTab == tab ? theme.chrome.accent : .clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
            Spacer()
        }
        .background(theme.chrome.surface)
    }

    private func tabTitle(_ tab: IssueDetailTab) -> String {
        switch tab {
        case .overview:
            return "Overview"
        case .timeline:
            let count = (detail?.comments.count ?? 0) + (detail?.timelineEvents.count ?? 0)
            return count > 0 ? "Timeline (\(count))" : "Timeline"
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .timeline:
            timelineTab
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let body = detail?.body, !body.isEmpty {
                    renderMarkdown(body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
                } else {
                    Text("No description provided")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Timeline Tab

    private var timelineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let items = timelineItems
                ForEach(items) { item in
                    switch item {
                    case .comment(let comment):
                        commentCard(comment)
                    case .event(let event):
                        eventRow(event)
                    }
                }

                // Comment input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a comment")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $inlineCommentText)
                        .frame(height: 60)
                        .font(.body)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.chrome.border, lineWidth: 1)
                        )
                    HStack {
                        Spacer()
                        Button("Comment") {
                            guard !inlineCommentText.isEmpty else { return }
                            onComment(inlineCommentText)
                            inlineCommentText = ""
                        }
                        .controlSize(.small)
                        .disabled(inlineCommentText.isEmpty)
                    }
                }
            }
            .padding(12)
        }
    }

    /// Unified timeline: comments + events sorted chronologically.
    private enum TimelineItem: Identifiable {
        case comment(IssueComment)
        case event(IssueTimelineEvent)

        var id: String {
            switch self {
            case .comment(let c): "comment-\(c.id)"
            case .event(let e): "event-\(e.id)"
            }
        }

        var date: Date {
            switch self {
            case .comment(let c): c.createdAt
            case .event(let e): e.createdAt
            }
        }
    }

    private var timelineItems: [TimelineItem] {
        var all: [TimelineItem] = []
        if let comments = detail?.comments {
            all += comments.map { .comment($0) }
        }
        if let events = detail?.timelineEvents {
            all += events.map { .event($0) }
        }
        return all.sorted { $0.date < $1.date }
    }

    private func commentCard(_ comment: IssueComment) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.chrome.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(comment.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                renderMarkdown(comment.body, inlineOnly: true)
                    .font(.body)
                    .foregroundColor(theme.chrome.text)
                    .textSelection(.enabled)
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .cornerRadius(6)
    }

    @ViewBuilder
    private func eventRow(_ event: IssueTimelineEvent) -> some View {
        HStack(spacing: 6) {
            eventIcon(event.event)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(event.actor)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            eventDescription(event)

            Spacer()

            Text(event.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }

    private func eventIcon(_ event: String) -> some View {
        let icon: String = switch event {
        case "labeled", "unlabeled": "tag"
        case "assigned", "unassigned": "person.badge.plus"
        case "closed": "xmark.circle"
        case "reopened": "arrow.counterclockwise"
        case "cross-referenced": "link"
        case "renamed": "pencil"
        case "milestoned", "demilestoned": "flag"
        default: "circle.fill"
        }
        return Image(systemName: icon)
    }

    @ViewBuilder
    private func eventDescription(_ event: IssueTimelineEvent) -> some View {
        switch event.event {
        case "labeled":
            HStack(spacing: 4) {
                Text("added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let label = event.label {
                    IssueLabelPill(label: label)
                }
            }
        case "unlabeled":
            HStack(spacing: 4) {
                Text("removed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let label = event.label {
                    IssueLabelPill(label: label)
                }
            }
        case "assigned":
            Text("assigned **\(event.assignee ?? "")**")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "unassigned":
            Text("unassigned **\(event.assignee ?? "")**")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "closed":
            Text("closed this")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "reopened":
            Text("reopened this")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "cross-referenced":
            if let source = event.source {
                HStack(spacing: 4) {
                    Text("referenced in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: source.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("\(source.type == "pullRequest" ? "PR" : "Issue") #\(source.number)")
                            .font(.caption)
                            .foregroundColor(theme.chrome.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        case "renamed":
            if let rename = event.rename {
                Text("renamed from \"\(rename.from)\" to \"\(rename.to)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        default:
            Text(event.event)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func renderMarkdown(_ source: String, inlineOnly: Bool = false) -> Text {
        let syntax: AttributedString.MarkdownParsingOptions.InterpretedSyntax =
            inlineOnly ? .inlineOnlyPreservingWhitespace : .full
        if let attributed = try? AttributedString(
            markdown: source, options: .init(interpretedSyntax: syntax)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }
}

// MARK: - Tab Enum

enum IssueDetailTab: String, CaseIterable {
    case overview
    case timeline
}

// MARK: - Issue Label Pill (shared within issue views)

struct IssueLabelPill: View {
    let label: IssueDetailLabel

    @Environment(\.theme) private var theme

    private var pillColor: Color {
        Color(hex: label.color) ?? theme.chrome.accent
    }

    var body: some View {
        Text(label.name)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.15))
            .overlay(Capsule().strokeBorder(pillColor.opacity(0.5), lineWidth: 0.5))
            .clipShape(Capsule())
            .foregroundColor(pillColor)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds. The `FlowLayout` and `Color(hex:)` are defined in `NewIssueSheet.swift` which is in the same Views target. `IssueLabelPill` uses `IssueDetailLabel` from Models.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/ProjectPage/IssueDetailDrawer.swift
git commit -m "feat: add IssueDetailDrawer with Overview and Timeline tabs"
```

---

### Task 7: Convert `ProjectIssuesTab` to Split-Pane Layout

**Files:**
- Modify: `Sources/Views/ProjectPage/ProjectIssuesTab.swift`

- [ ] **Step 1: Update `ProjectIssuesTab` parameters and layout**

Replace the full content of `Sources/Views/ProjectPage/ProjectIssuesTab.swift`:

```swift
import GitHubOperations
import Models
import SwiftUI
import Theme

// MARK: - Issue Filter

private enum IssueFilter: String, CaseIterable {
    case open = "Open"
    case closed = "Closed"
}

// MARK: - ProjectIssuesTab

public struct ProjectIssuesTab: View {
    let issues: [GitHubIssue]
    let labels: [IssueLabel]
    let isLoading: Bool
    let issuesEnabled: Bool
    let onRefresh: () -> Void
    let onCreate: (String, String, [String]) -> Void
    let onSelectIssue: (GitHubIssue?) -> Void
    let onFetchLabels: () -> Void
    var selectedIssueID: String?
    var issueDetail: IssueDetail?
    var isLoadingDetail: Bool = false
    var onComment: ((GitHubIssue, String) -> Void)?
    var onCloseIssue: ((GitHubIssue, CloseReason) -> Void)?
    var onReopen: ((GitHubIssue) -> Void)?
    var onEdit: ((GitHubIssue, String?, String?) -> Void)?
    var onUpdateLabels: ((GitHubIssue, [String], [String]) -> Void)?
    var onUpdateAssignees: ((GitHubIssue, [String], [String]) -> Void)?

    @Environment(\.theme) private var theme
    @State private var filter: IssueFilter = .open
    @State private var showNewIssue: Bool = false

    public init(
        issues: [GitHubIssue],
        labels: [IssueLabel],
        isLoading: Bool,
        issuesEnabled: Bool,
        onRefresh: @escaping () -> Void,
        onCreate: @escaping (String, String, [String]) -> Void,
        onSelectIssue: @escaping (GitHubIssue?) -> Void,
        onFetchLabels: @escaping () -> Void,
        selectedIssueID: String? = nil,
        issueDetail: IssueDetail? = nil,
        isLoadingDetail: Bool = false,
        onComment: ((GitHubIssue, String) -> Void)? = nil,
        onCloseIssue: ((GitHubIssue, CloseReason) -> Void)? = nil,
        onReopen: ((GitHubIssue) -> Void)? = nil,
        onEdit: ((GitHubIssue, String?, String?) -> Void)? = nil,
        onUpdateLabels: ((GitHubIssue, [String], [String]) -> Void)? = nil,
        onUpdateAssignees: ((GitHubIssue, [String], [String]) -> Void)? = nil
    ) {
        self.issues = issues
        self.labels = labels
        self.isLoading = isLoading
        self.issuesEnabled = issuesEnabled
        self.onRefresh = onRefresh
        self.onCreate = onCreate
        self.onSelectIssue = onSelectIssue
        self.onFetchLabels = onFetchLabels
        self.selectedIssueID = selectedIssueID
        self.issueDetail = issueDetail
        self.isLoadingDetail = isLoadingDetail
        self.onComment = onComment
        self.onCloseIssue = onCloseIssue
        self.onReopen = onReopen
        self.onEdit = onEdit
        self.onUpdateLabels = onUpdateLabels
        self.onUpdateAssignees = onUpdateAssignees
    }

    private var filteredIssues: [GitHubIssue] {
        issues.filter { issue in
            switch filter {
            case .open: issue.state == .open
            case .closed: issue.state == .closed
            }
        }
    }

    private var selectedIssue: GitHubIssue? {
        issues.first(where: { $0.id == selectedIssueID })
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Picker("Filter", selection: $filter) {
                    ForEach(IssueFilter.allCases, id: \.self) { filterOption in
                        Text(filterOption.rawValue).tag(filterOption)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("Refresh issues")

                Button {
                    onFetchLabels()
                    showNewIssue = true
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("New issue")
                .disabled(!issuesEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !issuesEnabled {
                issuesDisabledView
            } else if isLoading && issues.isEmpty {
                loadingView
            } else if filteredIssues.isEmpty {
                emptyStateView
            } else if let issue = selectedIssue {
                HStack(spacing: 0) {
                    issuesList
                        .frame(maxWidth: 320)
                    Divider()
                    IssueDetailDrawer(
                        issue: issue,
                        detail: issueDetail,
                        labels: labels,
                        isLoading: isLoadingDetail,
                        onClose: { onSelectIssue(nil) },
                        onComment: { body in onComment?(issue, body) },
                        onCloseIssue: { reason in onCloseIssue?(issue, reason) },
                        onReopen: { onReopen?(issue) },
                        onEdit: { title, body in onEdit?(issue, title, body) },
                        onUpdateLabels: { add, remove in onUpdateLabels?(issue, add, remove) },
                        onUpdateAssignees: { add, remove in onUpdateAssignees?(issue, add, remove) }
                    )
                }
            } else {
                issuesList
            }
        }
        .sheet(isPresented: $showNewIssue) {
            NewIssueSheet(labels: labels, onCreate: onCreate)
        }
    }

    // MARK: - Subviews

    private var issuesDisabledView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Issues not enabled")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enable issues in Project Settings to use this feature.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading issues\u{2026}")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No \(filter.rawValue.lowercased()) issues")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var issuesList: some View {
        List {
            ForEach(filteredIssues) { issue in
                IssueRowView(issue: issue, labels: labels, isSelected: issue.id == selectedIssueID)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectIssue(issue) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Issue Row

private struct IssueRowView: View {
    let issue: GitHubIssue
    let labels: [IssueLabel]
    var isSelected: Bool = false

    @Environment(\.theme) private var theme

    private var stateDotColor: Color {
        issue.state == .open ? theme.chrome.green : theme.chrome.textDim
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(stateDotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("#\(issue.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(issue.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels, id: \.self) { labelName in
                            LabelPill(labelName: labelName, labels: labels)
                        }
                    }
                }

                Text(issue.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.leading, isSelected ? 0 : 3)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.chrome.accent)
                    .frame(width: 3)
            }
        }
    }
}

// MARK: - Label Pill

private struct LabelPill: View {
    let labelName: String
    let labels: [IssueLabel]

    @Environment(\.theme) private var theme

    private var pillColor: Color {
        if let label = labels.first(where: { $0.name == labelName }),
            let color = Color(hex: label.color)
        {
            return color
        }
        return theme.chrome.accent
    }

    var body: some View {
        Text(labelName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.15))
            .overlay(Capsule().strokeBorder(pillColor.opacity(0.5), lineWidth: 0.5))
            .clipShape(Capsule())
            .foregroundColor(pillColor)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build fails — `ProjectPageView` still passes `onOpenIssue` which no longer exists. That's expected; we fix it in the next task.

- [ ] **Step 3: Commit (work in progress)**

```bash
git add Sources/Views/ProjectPage/ProjectIssuesTab.swift
git commit -m "feat: convert ProjectIssuesTab to split-pane layout with detail drawer"
```

---

### Task 8: Wire Everything Through `ProjectPageView` and `RunwayApp`

**Files:**
- Modify: `Sources/Views/ProjectPage/ProjectPageView.swift`
- Modify: `Sources/App/RunwayApp.swift`

- [ ] **Step 1: Update `ProjectPageView` to pass issue detail callbacks**

In `Sources/Views/ProjectPage/ProjectPageView.swift`, replace the `onOpenIssue` callback and add issue detail properties.

Replace the properties and init to include:

```swift
public struct ProjectPageView: View {
    let project: Project
    let issues: [GitHubIssue]
    let pullRequests: [PullRequest]
    let labels: [IssueLabel]
    let isLoadingIssues: Bool
    let onRefreshIssues: () -> Void
    let onCreateIssue: (String, String, [String]) -> Void
    let onSelectIssue: (GitHubIssue?) -> Void
    let onSelectPR: (PullRequest) -> Void
    let onRefreshPRs: () -> Void
    var selectedIssueID: String?
    var issueDetail: IssueDetail?
    var isLoadingIssueDetail: Bool = false
    var onCommentOnIssue: ((GitHubIssue, String) -> Void)?
    var onCloseIssue: ((GitHubIssue, CloseReason) -> Void)?
    var onReopenIssue: ((GitHubIssue) -> Void)?
    var onEditIssue: ((GitHubIssue, String?, String?) -> Void)?
    var onUpdateIssueLabels: ((GitHubIssue, [String], [String]) -> Void)?
    var onUpdateIssueAssignees: ((GitHubIssue, [String], [String]) -> Void)?
    var selectedPRID: String?
    var prDetail: PRDetail?
    var onApprovePR: ((PullRequest) -> Void)?
    var onCommentPR: ((PullRequest, String) -> Void)?
    var onRequestChangesPR: ((PullRequest, String) -> Void)?
    var onMergePR: ((PullRequest, MergeStrategy) -> Void)?
    var onToggleDraftPR: ((PullRequest) -> Void)?
    var onReviewPR: ((PullRequest) -> Void)?
    let onUpdateProject: (Project) -> Void
    let onDetectRepo: () async -> (repo: String, host: String?)?
    let onFetchLabels: () -> Void
```

Update the `init` to match (replace `onOpenIssue` with `onSelectIssue` and add all new parameters).

Update the issues tab content (around line 159) to pass all new callbacks:

```swift
case .issues:
    ProjectIssuesTab(
        issues: issues,
        labels: labels,
        isLoading: isLoadingIssues,
        issuesEnabled: project.issuesEnabled,
        onRefresh: onRefreshIssues,
        onCreate: onCreateIssue,
        onSelectIssue: onSelectIssue,
        onFetchLabels: onFetchLabels,
        selectedIssueID: selectedIssueID,
        issueDetail: issueDetail,
        isLoadingDetail: isLoadingIssueDetail,
        onComment: onCommentOnIssue,
        onCloseIssue: onCloseIssue,
        onReopen: onReopenIssue,
        onEdit: onEditIssue,
        onUpdateLabels: onUpdateIssueLabels,
        onUpdateAssignees: onUpdateIssueAssignees
    )
```

- [ ] **Step 2: Update `RunwayApp.swift` to wire store methods**

In `Sources/App/RunwayApp.swift`, around line 337-361 where `ProjectPageView` is instantiated, replace `onOpenIssue` and add new callbacks:

```swift
ProjectPageView(
    project: project,
    issues: store.projectIssues[projectID] ?? [],
    pullRequests: store.pullRequests.filter { $0.repo == project.ghRepo },
    labels: store.projectLabels[projectID] ?? [],
    isLoadingIssues: store.isLoadingIssues,
    onRefreshIssues: { Task { await store.fetchIssues(forProject: projectID) } },
    onCreateIssue: { title, body, labels in
        Task { await store.createIssue(forProject: projectID, title: title, body: body, labels: labels) }
    },
    onSelectIssue: { issue in Task { await store.selectIssue(issue) } },
    onSelectPR: { pr in Task { await store.selectPR(pr, navigate: false) } },
    onRefreshPRs: { Task { await store.refreshPRsIfStale() } },
    selectedIssueID: store.selectedIssueID,
    issueDetail: store.issueDetail,
    isLoadingIssueDetail: store.isLoadingIssueDetail,
    onCommentOnIssue: { issue, body in Task { await store.commentOnIssue(issue, body: body) } },
    onCloseIssue: { issue, reason in Task { await store.closeIssue(issue, reason: reason) } },
    onReopenIssue: { issue in Task { await store.reopenIssue(issue) } },
    onEditIssue: { issue, title, body in Task { await store.editIssue(issue, title: title, body: body) } },
    onUpdateIssueLabels: { issue, add, remove in Task { await store.updateIssueLabels(issue, add: add, remove: remove) } },
    onUpdateIssueAssignees: { issue, add, remove in Task { await store.updateIssueAssignees(issue, add: add, remove: remove) } },
    selectedPRID: store.selectedPRID,
    prDetail: store.prDetail,
    onApprovePR: { pr in Task { await store.approvePR(pr) } },
    onCommentPR: { pr, body in Task { await store.commentOnPR(pr, body: body) } },
    onRequestChangesPR: { pr, body in Task { await store.requestChangesOnPR(pr, body: body) } },
    onMergePR: { pr, strategy in Task { await store.mergePR(pr, strategy: strategy) } },
    onToggleDraftPR: { pr in Task { await store.togglePRDraft(pr) } },
    onReviewPR: { pr in store.reviewPR(pr) },
    onUpdateProject: { store.updateProjectSettings($0) },
    onDetectRepo: { await store.detectGHRepo(for: project) },
    onFetchLabels: { Task { await store.fetchLabels(forProject: projectID) } }
)
```

- [ ] **Step 3: Remove `openIssueInBrowser` from `RunwayStore`**

In `Sources/App/RunwayStore.swift`, delete the `openIssueInBrowser` method (lines 973-977). The "Open in browser" action now lives inside `IssueDetailDrawer`'s action bar.

- [ ] **Step 4: Build to verify full compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/ProjectPage/ProjectPageView.swift Sources/App/RunwayApp.swift Sources/App/RunwayStore.swift
git commit -m "feat: wire issue detail drawer through ProjectPageView and RunwayApp"
```

---

### Task 9: Final Verification and Cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run full build**

Run: `swift build 2>&1 | tail -20`
Expected: Clean build, no warnings.

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass (existing + new IssueManagerTests).

- [ ] **Step 3: Verify no compilation warnings**

Run: `swift build 2>&1 | grep -i warning | head -20`
Expected: No warnings related to our changes.

- [ ] **Step 4: Commit any cleanup**

If any fixes were needed, commit them:

```bash
git add -A
git commit -m "chore: cleanup and fix any build issues from issue detail feature"
```
