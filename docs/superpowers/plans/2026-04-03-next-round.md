# Next Round Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PR actions, global default permission mode, sidebar context menus with drag reorder, ANSI color sync, persisted layout widths, and terminal selection/copy-paste/drag-drop.

**Architecture:** Seven independent-to-loosely-coupled features built incrementally. Model changes first (Session.sortOrder, MergeStrategy enum), then PRManager additions, then UI work. Each task produces a buildable, testable commit.

**Tech Stack:** SwiftUI, GRDB/SQLite, SwiftTerm, `gh` CLI, NSPasteboard, NSWorkspace

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Sources/Models/Session.swift` | Add `sortOrder` property |
| Modify | `Sources/Models/PullRequest.swift` | Add `MergeStrategy` enum |
| Modify | `Sources/Persistence/Records.swift` | Add `sortOrder` to SessionRecord |
| Modify | `Sources/Persistence/Database.swift` | v5 migration + reorder methods |
| Modify | `Sources/GitHubOperations/PRManager.swift` | Add requestChanges, merge, toggleDraft |
| Modify | `Sources/App/RunwayStore.swift` | Wire new PR actions, reorder methods, rename methods |
| Modify | `Sources/Views/Settings/SettingsPlaceholder.swift` | Add default permission mode picker |
| Modify | `Sources/Views/Shared/NewSessionDialog.swift` | Read global default permission |
| Modify | `Sources/Views/PRDashboard/PRDetailDrawer.swift` | Add action bar with all PR actions |
| Modify | `Sources/Views/Sidebar/ProjectTreeView.swift` | Full context menus, drag reorder |
| Modify | `Sources/TerminalView/TerminalPane.swift` | ANSI color sync, drag-drop support |
| Modify | `Sources/TerminalView/TerminalKeyEventMonitor.swift` | Fix to find SwiftTerm views too |
| Modify | `Sources/App/RunwayApp.swift` | Persisted sidebar width via GeometryReader |
| Modify | `Sources/Views/PRDashboard/PRDashboardView.swift` | Persisted PR list width |
| Modify | `Sources/Views/SessionDetail/SessionDetailView.swift` | Add "View PR" action |
| Create | `Tests/ViewsTests/SettingsTests.swift` | Test default permission mode storage |
| Modify | `Tests/ModelsTests/SessionTests.swift` | Test sortOrder on Session |
| Modify | `Tests/GitHubOperationsTests/PRManagerTests.swift` | Test new PR action methods |
| Modify | `Tests/PersistenceTests/DatabaseTests.swift` | Test v5 migration + reorder |

---

### Task 1: Add sortOrder to Session Model

**Files:**
- Modify: `Sources/Models/Session.swift:4-54`
- Modify: `Sources/Persistence/Records.swift:7-70`
- Modify: `Sources/Persistence/Database.swift:38-148`
- Modify: `Tests/ModelsTests/SessionTests.swift`
- Modify: `Tests/PersistenceTests/DatabaseTests.swift`

- [ ] **Step 1: Add sortOrder property to Session**

In `Sources/Models/Session.swift`, add `sortOrder` to the struct and init:

```swift
public struct Session: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var groupID: String?
    public var path: String
    public var tool: Tool
    public var status: SessionStatus
    public var worktreeBranch: String?
    public var parentID: String?
    public var command: String?
    public var permissionMode: PermissionMode
    public var sortOrder: Int
    public var createdAt: Date
    public var lastAccessedAt: Date

    public init(
        id: String = Session.generateID(),
        title: String,
        groupID: String? = nil,
        path: String,
        tool: Tool = .claude,
        status: SessionStatus = .starting,
        worktreeBranch: String? = nil,
        parentID: String? = nil,
        command: String? = nil,
        permissionMode: PermissionMode = .default,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.groupID = groupID
        self.path = path
        self.tool = tool
        self.status = status
        self.worktreeBranch = worktreeBranch
        self.parentID = parentID
        self.command = command
        self.permissionMode = permissionMode
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
```

- [ ] **Step 2: Update SessionRecord to include sortOrder**

In `Sources/Persistence/Records.swift`, add `sortOrder` to `SessionRecord`:

```swift
struct SessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sessions"

    var id: String
    var title: String
    var groupID: String?
    var path: String
    var tool: String
    var status: String
    var worktreeBranch: String?
    var parentID: String?
    var command: String?
    var permissionMode: String
    var sortOrder: Int
    var createdAt: Date
    var lastAccessedAt: Date

    init(_ session: Session) {
        self.id = session.id
        self.title = session.title
        self.groupID = session.groupID
        self.path = session.path
        self.tool = Self.encodeTool(session.tool)
        self.status = session.status.rawValue
        self.worktreeBranch = session.worktreeBranch
        self.parentID = session.parentID
        self.command = session.command
        self.permissionMode = session.permissionMode.rawValue
        self.sortOrder = session.sortOrder
        self.createdAt = session.createdAt
        self.lastAccessedAt = session.lastAccessedAt
    }

    func toSession() -> Session {
        Session(
            id: id,
            title: title,
            groupID: groupID,
            path: path,
            tool: Self.decodeTool(tool),
            status: SessionStatus(rawValue: status) ?? .stopped,
            worktreeBranch: worktreeBranch,
            parentID: parentID,
            command: command,
            permissionMode: PermissionMode(rawValue: permissionMode) ?? .default,
            sortOrder: sortOrder,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
    }
```

- [ ] **Step 3: Add v5 migration for session sortOrder**

In `Sources/Persistence/Database.swift`, after the v4_pr_cache migration, add:

```swift
migrator.registerMigration("v5_session_sort_order") { db in
    try db.alter(table: "sessions") { t in
        t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
    }
}
```

- [ ] **Step 4: Add reorder helper methods to Database**

Add these methods after the existing session CRUD in `Sources/Persistence/Database.swift`:

```swift
// MARK: - Reordering

public func updateSessionSortOrder(id: String, sortOrder: Int) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: "UPDATE sessions SET sortOrder = ? WHERE id = ?",
            arguments: [sortOrder, id]
        )
    }
}

public func updateProjectSortOrder(id: String, sortOrder: Int) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: "UPDATE projects SET sortOrder = ? WHERE id = ?",
            arguments: [sortOrder, id]
        )
    }
}
```

Also update `allSessions()` to sort by sortOrder:

```swift
public func allSessions() throws -> [Session] {
    try dbQueue.read { db in
        try SessionRecord.order(Column("sortOrder"), Column("createdAt")).fetchAll(db).map { $0.toSession() }
    }
}
```

- [ ] **Step 5: Write tests for sortOrder**

Add to `Tests/ModelsTests/SessionTests.swift`:

```swift
func testSessionSortOrderDefaultsToZero() {
    let session = Session(title: "test", path: "/tmp")
    XCTAssertEqual(session.sortOrder, 0)
}

func testSessionSortOrderPreserved() {
    let session = Session(title: "test", path: "/tmp", sortOrder: 5)
    XCTAssertEqual(session.sortOrder, 5)
}
```

Add to `Tests/PersistenceTests/DatabaseTests.swift`:

```swift
func testSessionSortOrderPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "test", path: "/tmp", sortOrder: 3)
    try db.saveSession(session)
    let loaded = try db.session(id: session.id)
    XCTAssertEqual(loaded?.sortOrder, 3)
}

func testUpdateSessionSortOrder() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "test", path: "/tmp", sortOrder: 0)
    try db.saveSession(session)
    try db.updateSessionSortOrder(id: session.id, sortOrder: 5)
    let loaded = try db.session(id: session.id)
    XCTAssertEqual(loaded?.sortOrder, 5)
}

func testSessionsOrderedBySortOrder() throws {
    let db = try Database(inMemory: true)
    let s1 = Session(title: "c", path: "/tmp", sortOrder: 2)
    let s2 = Session(title: "a", path: "/tmp", sortOrder: 0)
    let s3 = Session(title: "b", path: "/tmp", sortOrder: 1)
    try db.saveSession(s1)
    try db.saveSession(s2)
    try db.saveSession(s3)
    let all = try db.allSessions()
    XCTAssertEqual(all.map(\.title), ["a", "b", "c"])
}
```

- [ ] **Step 6: Run tests**

Run: `swift test`
Expected: All tests pass including new sortOrder tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/Models/Session.swift Sources/Persistence/Records.swift Sources/Persistence/Database.swift Tests/
git commit -m "feat: add sortOrder to Session model with DB migration v5"
```

---

### Task 2: Add MergeStrategy Enum and PRManager Actions

**Files:**
- Modify: `Sources/Models/PullRequest.swift:60-77`
- Modify: `Sources/GitHubOperations/PRManager.swift:76-93`
- Modify: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Add MergeStrategy enum to PullRequest.swift**

After the `PRState` enum (line 68), add:

```swift
// MARK: - Merge Strategy

public enum MergeStrategy: String, Codable, Sendable, CaseIterable {
    case squash
    case merge
    case rebase

    public var displayName: String {
        switch self {
        case .squash: "Squash and merge"
        case .merge: "Merge commit"
        case .rebase: "Rebase and merge"
        }
    }

    public var cliFlag: String {
        switch self {
        case .squash: "--squash"
        case .merge: "--merge"
        case .rebase: "--rebase"
        }
    }
}
```

- [ ] **Step 2: Add requestChanges, merge, and toggleDraft to PRManager**

In `Sources/GitHubOperations/PRManager.swift`, after the `openInBrowser` method (line 93), add:

```swift
/// Request changes on a PR.
public func requestChanges(repo: String, number: Int, body: String, host: String? = nil) async throws {
    try await runGH(
        args: ["pr", "review", "\(number)", "--repo", repo, "--request-changes", "--body", body],
        host: host
    )
}

/// Merge a PR with the specified strategy.
public func merge(repo: String, number: Int, strategy: MergeStrategy = .squash, host: String? = nil) async throws {
    try await runGH(
        args: ["pr", "merge", "\(number)", "--repo", repo, strategy.cliFlag, "--delete-branch"],
        host: host
    )
}

/// Toggle draft state. `gh pr ready` to mark ready; GraphQL mutation to convert to draft.
public func toggleDraft(repo: String, number: Int, isDraft: Bool, host: String? = nil) async throws {
    if isDraft {
        // Currently ready → convert to draft via GraphQL
        // First get the node ID
        let nodeOutput = try await runGH(
            args: ["pr", "view", "\(number)", "--repo", repo, "--json", "id", "-q", ".id"],
            host: host
        )
        let nodeID = nodeOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        try await runGH(
            args: [
                "api", "graphql",
                "-f", "query=mutation { convertPullRequestToDraft(input: {pullRequestId: \"\(nodeID)\"}) { pullRequest { isDraft } } }",
            ],
            host: host
        )
    } else {
        // Currently draft → mark as ready
        try await runGH(
            args: ["pr", "ready", "\(number)", "--repo", repo],
            host: host
        )
    }
}
```

- [ ] **Step 3: Write tests for new PRManager methods**

Add to `Tests/GitHubOperationsTests/PRManagerTests.swift` — these test argument construction since we can't run `gh` in CI. Verify the methods exist and the enum values are correct:

```swift
func testMergeStrategyCliFlags() {
    XCTAssertEqual(MergeStrategy.squash.cliFlag, "--squash")
    XCTAssertEqual(MergeStrategy.merge.cliFlag, "--merge")
    XCTAssertEqual(MergeStrategy.rebase.cliFlag, "--rebase")
}

func testMergeStrategyDisplayNames() {
    XCTAssertEqual(MergeStrategy.squash.displayName, "Squash and merge")
    XCTAssertEqual(MergeStrategy.merge.displayName, "Merge commit")
    XCTAssertEqual(MergeStrategy.rebase.displayName, "Rebase and merge")
}

func testMergeStrategyCaseIterable() {
    XCTAssertEqual(MergeStrategy.allCases.count, 3)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/PullRequest.swift Sources/GitHubOperations/PRManager.swift Tests/
git commit -m "feat: add requestChanges, merge, toggleDraft to PRManager"
```

---

### Task 3: Wire PR Actions into RunwayStore

**Files:**
- Modify: `Sources/App/RunwayStore.swift:440-466`

- [ ] **Step 1: Add new PR action methods to RunwayStore**

After `commentOnPR` (line 460), add these methods:

```swift
func requestChangesOnPR(_ pr: PullRequest, body: String) async {
    let host = await prManager.hostFromURL(pr.url)
    do {
        try await prManager.requestChanges(repo: pr.repo, number: pr.number, body: body, host: host)
        statusMessage = .success("Requested changes on #\(pr.number)")
        // Refresh detail to show updated review state
        prDetail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number, host: host)
        await fetchPRs()
    } catch {
        statusMessage = .error("Request changes failed: \(error.localizedDescription)")
    }
}

func mergePR(_ pr: PullRequest, strategy: MergeStrategy = .squash) async {
    let host = await prManager.hostFromURL(pr.url)
    do {
        try await prManager.merge(repo: pr.repo, number: pr.number, strategy: strategy, host: host)
        statusMessage = .success("Merged #\(pr.number)")
        await fetchPRs()
    } catch {
        statusMessage = .error("Merge failed: \(error.localizedDescription)")
    }
}

func togglePRDraft(_ pr: PullRequest) async {
    let host = await prManager.hostFromURL(pr.url)
    do {
        try await prManager.toggleDraft(repo: pr.repo, number: pr.number, isDraft: !pr.isDraft, host: host)
        statusMessage = .success(pr.isDraft ? "Marked #\(pr.number) as ready" : "Converted #\(pr.number) to draft")
        await fetchPRs()
    } catch {
        statusMessage = .error("Draft toggle failed: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: Add rename and reorder methods to RunwayStore**

After `deleteProject` (line 294), add:

```swift
// MARK: - Renaming

func renameSession(id: String, title: String) {
    if let idx = sessions.firstIndex(where: { $0.id == id }) {
        sessions[idx].title = title
        try? database?.saveSession(sessions[idx])
    }
}

func renameProject(id: String, name: String) {
    if let idx = projects.firstIndex(where: { $0.id == id }) {
        projects[idx].name = name
        try? database?.saveProject(projects[idx])
    }
}

// MARK: - Reordering

func reorderSessions(in projectID: String?, fromOffsets: IndexSet, toOffset: Int) {
    var subset = sessions.filter { $0.groupID == projectID }
    subset.move(fromOffsets: fromOffsets, toOffset: toOffset)
    // Update sort orders
    for (i, session) in subset.enumerated() {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].sortOrder = i
            try? database?.updateSessionSortOrder(id: session.id, sortOrder: i)
        }
    }
}

func reorderProjects(fromOffsets: IndexSet, toOffset: Int) {
    projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
    for (i, project) in projects.enumerated() {
        projects[i].sortOrder = i
        try? database?.updateProjectSortOrder(id: project.id, sortOrder: i)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: wire PR actions and reorder methods into RunwayStore"
```

---

### Task 4: Global Default Permission Mode Setting

**Files:**
- Modify: `Sources/Views/Settings/SettingsPlaceholder.swift:170-197`
- Modify: `Sources/Views/Shared/NewSessionDialog.swift:16`

- [ ] **Step 1: Add permission mode picker to General settings tab**

In `Sources/Views/Settings/SettingsPlaceholder.swift`, add an `@AppStorage` property after the existing ones (line 8):

```swift
@AppStorage("defaultPermissionMode") private var defaultPermissionMode: String = "default"
```

Then replace the `generalSettings` computed property (lines 171-197) with:

```swift
private var generalSettings: some View {
    Form {
        Section("Session Defaults") {
            Picker("Default Permission Mode", selection: $defaultPermissionMode) {
                ForEach(PermissionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if defaultPermissionMode == PermissionMode.bypassAll.rawValue {
                Text("New sessions will skip all permission prompts by default")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }

        Section("Hooks") {
            LabeledContent("Hook Server Port") {
                Text("47437")
                    .foregroundColor(.secondary)
            }
            LabeledContent("Status") {
                Text("Running")
                    .foregroundColor(.green)
            }
        }

        Section("About") {
            LabeledContent("Version") {
                Text("0.1.0")
                    .foregroundColor(.secondary)
            }
            LabeledContent("Config Directory") {
                Text("~/.runway/")
                    .foregroundColor(.secondary)
            }
        }
    }
    .formStyle(.grouped)
    .padding()
}
```

Also add `import Models` at the top of the file if not already present.

- [ ] **Step 2: Read default permission in NewSessionDialog**

In `Sources/Views/Shared/NewSessionDialog.swift`, add an `@AppStorage` property after the existing `@State` declarations (around line 16):

```swift
@AppStorage("defaultPermissionMode") private var defaultPermissionMode: String = "default"
```

Then change the initial `permissionMode` state (line 16) from:

```swift
@State private var permissionMode: PermissionMode = .default
```

to use `onAppear` to read the stored default. Actually, since `@AppStorage` is available at init, we can read it directly. Replace line 16:

```swift
@State private var permissionMode: PermissionMode = .default
```

And add an `.onAppear` to the body's outermost VStack:

```swift
.onAppear {
    if let mode = PermissionMode(rawValue: defaultPermissionMode) {
        permissionMode = mode
    }
}
```

Add this after the `.frame(width: 420)` on line 132.

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/Settings/SettingsPlaceholder.swift Sources/Views/Shared/NewSessionDialog.swift
git commit -m "feat: global default permission mode in Settings → General"
```

---

### Task 5: ANSI Color Palette Sync

**Files:**
- Modify: `Sources/TerminalView/TerminalPane.swift:106-111`

- [ ] **Step 1: Apply ANSI colors in applyTheme**

SwiftTerm's `TerminalView` exposes `installColors(_ colors: [Color])` which takes 16 SwiftUI `Color` values. Replace the `applyTheme` method in `Sources/TerminalView/TerminalPane.swift` (lines 106-111):

```swift
private func applyTheme(_ terminal: LocalProcessTerminalView) {
    let palette = theme.terminal
    terminal.nativeForegroundColor = NSColor(palette.foreground)
    terminal.nativeBackgroundColor = NSColor(palette.background)
    terminal.selectedTextBackgroundColor = NSColor(palette.selection)

    // Apply ANSI palette (16 colors: 0-7 normal, 8-15 bright)
    terminal.installColors(palette.ansi)

    // Force redraw to apply new colors
    terminal.needsDisplay = true
}
```

Note: `installColors` accepts `[SwiftUI.Color]` and SwiftTerm internally converts them. The `TerminalPalette.ansi` array is already `[Color]` with exactly 16 entries (enforced by precondition).

- [ ] **Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/TerminalView/TerminalPane.swift
git commit -m "feat: sync ANSI color palette from theme to SwiftTerm"
```

---

### Task 6: PR Action Bar in PRDetailDrawer

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDetailDrawer.swift:6-30,98-111`
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift:6-148`
- Modify: `Sources/App/RunwayApp.swift:217-235`

- [ ] **Step 1: Add new callbacks to PRDetailDrawer**

In `Sources/Views/PRDashboard/PRDetailDrawer.swift`, expand the callback properties and add state for action sheets:

Replace the property declarations and init (lines 6-29):

```swift
public struct PRDetailDrawer: View {
    let pr: PullRequest
    let detail: PRDetail?
    let onClose: () -> Void
    let onApprove: () -> Void
    let onComment: (String) -> Void
    let onRequestChanges: (String) -> Void
    let onMerge: (MergeStrategy) -> Void
    let onToggleDraft: () -> Void

    @State private var selectedTab: PRDetailTab = .overview
    @State private var commentText: String = ""
    @State private var showMergeConfirm: Bool = false
    @State private var selectedMergeStrategy: MergeStrategy = .squash
    @State private var showRequestChanges: Bool = false
    @State private var requestChangesText: String = ""
    @State private var showCommentSheet: Bool = false
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        detail: PRDetail? = nil,
        onClose: @escaping () -> Void = {},
        onApprove: @escaping () -> Void = {},
        onComment: @escaping (String) -> Void = { _ in },
        onRequestChanges: @escaping (String) -> Void = { _ in },
        onMerge: @escaping (MergeStrategy) -> Void = { _ in },
        onToggleDraft: @escaping () -> Void = {}
    ) {
        self.pr = pr
        self.detail = detail
        self.onClose = onClose
        self.onApprove = onApprove
        self.onComment = onComment
        self.onRequestChanges = onRequestChanges
        self.onMerge = onMerge
        self.onToggleDraft = onToggleDraft
    }
```

- [ ] **Step 2: Replace the action buttons in the header**

Replace the existing action buttons section (lines 98-111 in the header) with a full action bar:

```swift
// Action bar
HStack(spacing: 8) {
    Button("Approve") { onApprove() }
        .buttonStyle(.borderedProminent)
        .tint(theme.chrome.green)
        .controlSize(.small)

    Button("Request Changes") { showRequestChanges = true }
        .controlSize(.small)

    Button("Comment") { showCommentSheet = true }
        .controlSize(.small)

    Spacer()

    // Draft toggle
    if pr.isDraft {
        Button("Mark Ready") { onToggleDraft() }
            .controlSize(.small)
            .tint(theme.chrome.accent)
    } else {
        Button("Convert to Draft") { onToggleDraft() }
            .controlSize(.small)
    }

    // Merge button with strategy menu
    if !pr.isDraft && pr.state == .open {
        Menu {
            ForEach(MergeStrategy.allCases, id: \.self) { strategy in
                Button(strategy.displayName) {
                    selectedMergeStrategy = strategy
                    showMergeConfirm = true
                }
            }
        } label: {
            Label("Merge", systemImage: "arrow.triangle.merge")
                .controlSize(.small)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    Button {
        if let url = URL(string: pr.url) {
            NSWorkspace.shared.open(url)
        }
    } label: {
        Image(systemName: "safari")
    }
    .controlSize(.small)
    .help("Open in browser")
}
.alert("Merge Pull Request", isPresented: $showMergeConfirm) {
    Button("Cancel", role: .cancel) {}
    Button("Merge", role: .destructive) {
        onMerge(selectedMergeStrategy)
    }
} message: {
    Text("This will \(selectedMergeStrategy.displayName.lowercased()) #\(pr.number) into \(pr.baseBranch).")
}
.sheet(isPresented: $showRequestChanges) {
    VStack(spacing: 12) {
        Text("Request Changes on #\(pr.number)")
            .font(.headline)
        TextEditor(text: $requestChangesText)
            .frame(minHeight: 100)
            .border(Color.secondary.opacity(0.3))
        HStack {
            Button("Cancel") { showRequestChanges = false }
            Spacer()
            Button("Submit") {
                onRequestChanges(requestChangesText)
                requestChangesText = ""
                showRequestChanges = false
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.chrome.orange)
            .disabled(requestChangesText.isEmpty)
        }
    }
    .padding()
    .frame(width: 400)
}
.sheet(isPresented: $showCommentSheet) {
    VStack(spacing: 12) {
        Text("Comment on #\(pr.number)")
            .font(.headline)
        TextEditor(text: $commentText)
            .frame(minHeight: 100)
            .border(Color.secondary.opacity(0.3))
        HStack {
            Button("Cancel") { showCommentSheet = false }
            Spacer()
            Button("Comment") {
                onComment(commentText)
                commentText = ""
                showCommentSheet = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(commentText.isEmpty)
        }
    }
    .padding()
    .frame(width: 400)
}
```

- [ ] **Step 3: Update PRDashboardView to pass new callbacks**

In `Sources/Views/PRDashboard/PRDashboardView.swift`, add the new callback properties to `PRDashboardView`:

Add after existing callbacks (around line 12):

```swift
var onRequestChanges: ((PullRequest, String) -> Void)?
var onMerge: ((PullRequest, MergeStrategy) -> Void)?
var onToggleDraft: ((PullRequest) -> Void)?
```

Update the `PRDetailDrawer` instantiation inside the view body to pass the new callbacks:

```swift
PRDetailDrawer(
    pr: selectedPR,
    detail: detail,
    onClose: { onSelectPR?(nil) },
    onApprove: { onApprove?(selectedPR) },
    onComment: { body in onComment?(selectedPR, body) },
    onRequestChanges: { body in onRequestChanges?(selectedPR, body) },
    onMerge: { strategy in onMerge?(selectedPR, strategy) },
    onToggleDraft: { onToggleDraft?(selectedPR) }
)
```

- [ ] **Step 4: Wire callbacks in RunwayApp ContentView**

In `Sources/App/RunwayApp.swift`, update the `PRDashboardView` instantiation (around lines 218-235) to include the new callbacks:

```swift
PRDashboardView(
    pullRequests: store.pullRequests,
    selectedPRID: store.selectedPRID,
    detail: store.prDetail,
    isLoading: store.isLoadingPRs,
    onSelectPR: { pr in Task { await store.selectPR(pr) } },
    onFilterChange: { tab in
        let filter: PRFilter =
            switch tab {
            case .all: .all
            case .mine: .mine
            case .reviewRequested: .reviewRequested
            }
        Task { await store.fetchPRs(filter: filter) }
    },
    onRefresh: { Task { await store.fetchPRs() } },
    onApprove: { pr in Task { await store.approvePR(pr) } },
    onComment: { pr, body in Task { await store.commentOnPR(pr, body: body) } },
    onRequestChanges: { pr, body in Task { await store.requestChangesOnPR(pr, body: body) } },
    onMerge: { pr, strategy in Task { await store.mergePR(pr, strategy: strategy) } },
    onToggleDraft: { pr in Task { await store.togglePRDraft(pr) } }
)
```

- [ ] **Step 5: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/PRDashboard/PRDetailDrawer.swift Sources/Views/PRDashboard/PRDashboardView.swift Sources/App/RunwayApp.swift
git commit -m "feat: PR action bar with approve, request changes, merge, draft toggle"
```

---

### Task 7: Sidebar Context Menus

**Files:**
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift`
- Modify: `Sources/App/RunwayStore.swift`
- Modify: `Sources/App/RunwayApp.swift`

- [ ] **Step 1: Add new callbacks to ProjectTreeView**

In `Sources/Views/Sidebar/ProjectTreeView.swift`, extend the callback properties (lines 11-14):

```swift
var onRestart: ((String) -> Void)?
var onDelete: ((String) -> Void)?
var onNewSession: ((String?) -> Void)?
var onNewProject: (() -> Void)?
var onRenameSession: ((String, String) -> Void)?
var onRenameProject: ((String, String) -> Void)?
var onDeleteProject: ((String) -> Void)?
var onViewPR: ((String) -> Void)?
```

Update the init to include new params (add defaults so existing callers don't break):

```swift
public init(
    projects: [Project],
    sessions: [Session],
    sessionPRs: [String: PullRequest] = [:],
    selectedSessionID: Binding<String?>,
    onRestart: ((String) -> Void)? = nil,
    onDelete: ((String) -> Void)? = nil,
    onNewSession: ((String?) -> Void)? = nil,
    onNewProject: (() -> Void)? = nil,
    onRenameSession: ((String, String) -> Void)? = nil,
    onRenameProject: ((String, String) -> Void)? = nil,
    onDeleteProject: ((String) -> Void)? = nil,
    onViewPR: ((String) -> Void)? = nil
) {
```

And set the new properties in the init body.

- [ ] **Step 2: Replace SessionRowView context menu**

In `SessionRowView`, replace the existing `.contextMenu` (lines 248-262) with:

```swift
.contextMenu {
    Button {
        isRenaming = true
    } label: {
        Label("Rename Session", systemImage: "pencil")
    }

    Divider()

    Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.path, forType: .string)
    } label: {
        Label("Copy Worktree Path", systemImage: "doc.on.doc")
    }

    if let branch = session.worktreeBranch {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch, forType: .string)
        } label: {
            Label("Copy Branch Name", systemImage: "arrow.triangle.branch")
        }
    }

    Button {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.path)
    } label: {
        Label("Open in Finder", systemImage: "folder")
    }

    Button {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", session.path]
        try? process.run()
    } label: {
        Label("Open in Terminal", systemImage: "terminal")
    }

    if linkedPR != nil {
        Divider()

        Button {
            onViewPR?(session.id)
        } label: {
            Label("View PR", systemImage: "arrow.triangle.pull")
        }

        Button {
            if let url = URL(string: linkedPR!.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open PR in Browser", systemImage: "safari")
        }
    }

    Divider()

    Button {
        onRestart?(session.id)
    } label: {
        Label("Restart Session", systemImage: "arrow.counterclockwise")
    }

    Button(role: .destructive) {
        onDelete?(session.id)
    } label: {
        Label("Delete Session", systemImage: "trash")
    }
}
```

Also add state and callback properties to `SessionRowView`:

```swift
var onRenameSession: ((String, String) -> Void)?
var onViewPR: ((String) -> Void)?
@State private var isRenaming = false
@State private var editTitle: String = ""
```

And modify the title text to support inline editing — wrap the session title display:

```swift
if isRenaming {
    TextField("Session name", text: $editTitle, onCommit: {
        if !editTitle.isEmpty {
            onRenameSession?(session.id, editTitle)
        }
        isRenaming = false
    })
    .textFieldStyle(.plain)
    .font(.system(.body, design: .default))
    .onAppear { editTitle = session.title }
} else {
    Text(session.title)
        .font(.system(.body, design: .default))
        .foregroundColor(theme.chrome.text)
}
```

- [ ] **Step 3: Add project context menu to ProjectSection**

In `ProjectSection`, add callbacks and state:

```swift
var onRenameProject: ((String, String) -> Void)?
var onDeleteProject: ((String) -> Void)?
@State private var isRenaming = false
@State private var editName: String = ""
```

Add a `.contextMenu` to the DisclosureGroup label:

```swift
} label: {
    HStack(spacing: 4) {
        if isRenaming {
            TextField("Project name", text: $editName, onCommit: {
                if !editName.isEmpty {
                    onRenameProject?(project.id, editName)
                }
                isRenaming = false
            })
            .textFieldStyle(.plain)
            .font(.system(.title3, weight: .semibold))
            .onAppear { editName = project.name }
        } else {
            Text(project.name)
                .font(.system(.title3, weight: .semibold))
                .foregroundColor(theme.chrome.text)
        }
        Spacer()
        // ... existing hover button ...
    }
    .onHover { hovering in isHeaderHovered = hovering }
}
.contextMenu {
    Button {
        isRenaming = true
    } label: {
        Label("Rename Project", systemImage: "pencil")
    }

    Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path, forType: .string)
    } label: {
        Label("Copy Path", systemImage: "doc.on.doc")
    }

    Button {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
    } label: {
        Label("Open in Finder", systemImage: "folder")
    }

    Divider()

    Button(role: .destructive) {
        onDeleteProject?(project.id)
    } label: {
        Label("Remove Project", systemImage: "folder.badge.minus")
    }
}
```

- [ ] **Step 4: Pass new callbacks from ContentView to ProjectTreeView**

In `Sources/App/RunwayApp.swift`, update the `ProjectTreeView` instantiation (around line 168) to include new callbacks:

```swift
ProjectTreeView(
    projects: store.projects,
    sessions: store.sessions,
    sessionPRs: store.sessionPRs,
    selectedSessionID: Binding(
        get: { store.selectedSessionID },
        set: { store.selectedSessionID = $0 }
    ),
    onRestart: { id in Task { await store.restartSession(id: id) } },
    onDelete: { id in store.deleteSession(id: id) },
    onNewSession: { projectID in
        store.newSessionProjectID = projectID
        store.showNewSessionDialog = true
    },
    onNewProject: { store.showNewProjectDialog = true },
    onRenameSession: { id, name in store.renameSession(id: id, title: name) },
    onRenameProject: { id, name in store.renameProject(id: id, name: name) },
    onDeleteProject: { id in store.deleteProject(id: id) },
    onViewPR: { sessionID in
        if let pr = store.sessionPRs[sessionID] {
            store.currentView = .prs
            Task { await store.selectPR(pr) }
        }
    }
)
```

- [ ] **Step 5: Thread callbacks through ProjectSection and SessionRowView**

Make sure `ProjectSection` passes `onRenameSession`, `onViewPR` down to each `SessionRowView`, and update its init. Similarly thread `onRenameProject` and `onDeleteProject` from `ProjectTreeView` to `ProjectSection`.

- [ ] **Step 6: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/Views/Sidebar/ProjectTreeView.swift Sources/App/RunwayApp.swift Sources/App/RunwayStore.swift
git commit -m "feat: full sidebar context menus for sessions and projects"
```

---

### Task 8: Drag Reorder in Sidebar

**Files:**
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift`

- [ ] **Step 1: Add drag reorder for projects**

In `ProjectTreeView.body`, the top-level `ForEach(projects)` needs to support `.onMove`. Add reorder callbacks:

```swift
var onReorderSessions: ((String?, IndexSet, Int) -> Void)?
var onReorderProjects: ((IndexSet, Int) -> Void)?
```

In the body, change the projects `ForEach`:

```swift
ForEach(projects) { project in
    ProjectSection(
        project: project,
        sessions: sessions.filter { $0.groupID == project.id },
        sessionPRs: sessionPRs,
        onRestart: onRestart,
        onDelete: onDelete,
        onNewSession: { onNewSession?(project.id) },
        onRenameSession: onRenameSession,
        onRenameProject: onRenameProject,
        onDeleteProject: onDeleteProject,
        onViewPR: onViewPR,
        onReorderSessions: { fromOffsets, toOffset in
            onReorderSessions?(project.id, fromOffsets, toOffset)
        }
    )
}
.onMove { fromOffsets, toOffset in
    onReorderProjects?(fromOffsets, toOffset)
}
```

- [ ] **Step 2: Add drag reorder for sessions within ProjectSection**

In `ProjectSection`, add an `onReorderSessions` callback and use `.onMove`:

```swift
var onReorderSessions: ((IndexSet, Int) -> Void)?
```

In the `DisclosureGroup` content:

```swift
DisclosureGroup(isExpanded: $isExpanded) {
    ForEach(sessions) { session in
        SessionRowView(
            session: session,
            linkedPR: sessionPRs[session.id],
            onRestart: onRestart,
            onDelete: onDelete,
            onRenameSession: onRenameSession,
            onViewPR: onViewPR
        )
        .tag(session.id)
    }
    .onMove { fromOffsets, toOffset in
        onReorderSessions?(fromOffsets, toOffset)
    }
}
```

- [ ] **Step 3: Wire reorder callbacks in ContentView**

In `Sources/App/RunwayApp.swift`, add to the `ProjectTreeView` init:

```swift
onReorderSessions: { projectID, fromOffsets, toOffset in
    store.reorderSessions(in: projectID, fromOffsets: fromOffsets, toOffset: toOffset)
},
onReorderProjects: { fromOffsets, toOffset in
    store.reorderProjects(fromOffsets: fromOffsets, toOffset: toOffset)
}
```

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/Sidebar/ProjectTreeView.swift Sources/App/RunwayApp.swift
git commit -m "feat: drag-to-reorder sessions and projects in sidebar"
```

---

### Task 9: Persisted Layout Widths

**Files:**
- Modify: `Sources/App/RunwayApp.swift:64-72,185`
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift`

- [ ] **Step 1: Persist sidebar width**

In `Sources/App/RunwayApp.swift`, add `@AppStorage` to `ContentView`:

```swift
@AppStorage("sidebarWidth") private var sidebarWidth: Double = 280
```

Wrap the sidebar content in a `GeometryReader` to observe width changes. Replace the sidebar section:

```swift
private var sidebar: some View {
    VStack(spacing: 0) {
        viewPicker
        Divider()
        ProjectTreeView(
            // ... existing params ...
        )
    }
    .frame(minWidth: 200, idealWidth: CGFloat(sidebarWidth), maxWidth: 500)
    .background(
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.size.width) { _, newWidth in
                    // Debounce: only update if changed significantly
                    if abs(Double(newWidth) - sidebarWidth) > 5 {
                        sidebarWidth = Double(newWidth)
                    }
                }
        }
    )
}
```

Also update the `NavigationSplitView` to use column width:

```swift
NavigationSplitView(columnVisibility: .constant(.all)) {
    sidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: CGFloat(sidebarWidth), max: 500)
        .background(theme.chrome.surface)
} detail: {
    detail
}
```

- [ ] **Step 2: Persist PR list width**

In `Sources/Views/PRDashboard/PRDashboardView.swift`, add:

```swift
@AppStorage("prListWidth") private var prListWidth: Double = 380
```

If the PR dashboard uses an `HSplitView` or a manual split, bind the width. If it uses `GeometryReader`, use the same approach as sidebar. Look at how the PR list is laid out and persist its width accordingly.

The PR dashboard likely uses an `HStack` with a fixed-width list and a flexible detail. Update the list frame:

```swift
.frame(width: CGFloat(prListWidth))
```

And add a draggable divider or use `GeometryReader` to track manual resizing.

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/RunwayApp.swift Sources/Views/PRDashboard/PRDashboardView.swift
git commit -m "feat: persist sidebar and PR list widths across restarts"
```

---

### Task 10: Terminal Selection, Copy/Paste, and Drag-Drop

**Files:**
- Modify: `Sources/TerminalView/TerminalPane.swift:27-47,106-111,139-153`
- Modify: `Sources/TerminalView/TerminalKeyEventMonitor.swift:60-80,168-180`

- [ ] **Step 1: Fix TerminalKeyEventMonitor to find SwiftTerm views**

The `findTerminalView` method (line 168) only looks for `AppTerminalView` (Ghostty). It also needs to find `LocalProcessTerminalView` (SwiftTerm). Also, the Cmd+C interception (line 77) should only send to the terminal when there's no selection — otherwise Cmd+C should copy.

In `Sources/TerminalView/TerminalKeyEventMonitor.swift`, replace `findTerminalView` (lines 168-180):

```swift
private func findTerminalView(in view: NSView?) -> NSView? {
    guard let view else { return nil }
    for subview in view.subviews {
        let name = String(describing: type(of: subview))
        // Match Ghostty's AppTerminalView or SwiftTerm's LocalProcessTerminalView/TerminalView
        if subview.acceptsFirstResponder
            && (name.contains("AppTerminalView") || name.contains("TerminalView"))
            && !(subview is NSTextField)
            && !(subview is NSButton)
            && !(subview is NSScrollView)
        {
            return subview
        }
        if let found = findTerminalView(in: subview) {
            return found
        }
    }
    return nil
}
```

Also update the Cmd+C handling (lines 75-79) to allow copy when text is selected:

```swift
if event.modifierFlags.contains(.command) && event.type == .keyDown {
    let key = event.charactersIgnoringModifiers ?? ""
    if key == "c" {
        // Cmd+C: if terminal has selected text, copy it; otherwise send SIGINT
        // Let it through to the terminal's keyDown handler which handles both cases
    } else if key == "v" {
        // Cmd+V: let terminal handle paste
    } else if !key.isEmpty {
        return false  // Let other Cmd+key through to menu system
    }
}
```

- [ ] **Step 2: Ensure TerminalContainerView doesn't intercept mouse events**

In `Sources/TerminalView/TerminalPane.swift`, the `TerminalContainerView` (lines 139-153) should pass through all mouse events. Add to the class:

```swift
class TerminalContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass mouse events through to the terminal subview
        return subviews.first?.hitTest(convert(point, to: subviews.first)) ?? super.hitTest(point)
    }

    func embed(_ terminal: NSView) {
        for subview in subviews { subview.removeFromSuperview() }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
```

- [ ] **Step 3: Add drag-drop support to TerminalPane**

Create a subclass or extension that registers for drag types. Add a new helper class in `Sources/TerminalView/TerminalPane.swift` after `TerminalContainerView`:

```swift
// MARK: - Drag & Drop Support

class TerminalDropView: NSView {
    var terminal: LocalProcessTerminalView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }

        let paths = items.map { url -> String in
            // Shell-escape the path
            url.path.replacingOccurrences(of: " ", with: "\\ ")
                .replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)")
                .replacingOccurrences(of: "'", with: "\\'")
        }

        let text = paths.joined(separator: " ")
        terminal?.send(txt: text)
        return true
    }
}
```

Then in `makeNSView`, register the container for drag types:

```swift
public func makeNSView(context: Context) -> NSView {
    let container = TerminalContainerView()

    let terminal = TerminalSessionCache.shared.terminalView(
        forSessionID: sessionID,
        tabID: tabID
    ) {
        createTerminal()
    }

    container.embed(terminal)
    context.coordinator.terminal = terminal

    // Register for file drag-drop
    container.registerForDraggedTypes([.fileURL])

    // Request focus
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        terminal.window?.makeFirstResponder(terminal)
    }

    return container
}
```

And update `TerminalContainerView` to forward drag operations:

```swift
class TerminalContainerView: NSView {
    private var terminalRef: LocalProcessTerminalView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return subviews.first?.hitTest(convert(point, to: subviews.first)) ?? super.hitTest(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        let paths = items.map { url -> String in
            url.path.replacingOccurrences(of: " ", with: "\\ ")
                .replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)")
                .replacingOccurrences(of: "'", with: "\\'")
        }
        terminalRef?.send(txt: paths.joined(separator: " "))
        return true
    }

    func embed(_ terminal: NSView) {
        for subview in subviews { subview.removeFromSuperview() }
        if let localTerminal = terminal as? LocalProcessTerminalView {
            terminalRef = localTerminal
        }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        registerForDraggedTypes([.fileURL])
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
```

Remove the separate `TerminalDropView` class since we merged drag-drop into `TerminalContainerView`.

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/TerminalView/TerminalPane.swift Sources/TerminalView/TerminalKeyEventMonitor.swift
git commit -m "feat: terminal selection, copy/paste fix, and file drag-drop"
```

---

### Task 11: Final Build and Test Verification

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 2: Run full build**

Run: `swift build`
Expected: Clean build with no warnings.

- [ ] **Step 3: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: address build/test issues from next-round feature batch"
```
