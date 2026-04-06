# PR Review Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable creating a Claude session from a PR number — resolve the PR, create a worktree on its branch, and launch a session with a pre-filled review prompt.

**Architecture:** Two entry points (⌘⇧R dialog and PR dashboard "Review" button) converge on a shared `ReviewPRSheet` confirmation view. `PRManager.resolvePR()` fetches PR data, `WorktreeManager.checkoutWorktree()` creates a worktree on the existing remote branch, and `RunwayStore.handleReviewPR()` orchestrates session creation with immediate PR linking.

**Tech Stack:** SwiftUI, Swift Testing, GRDB (SQLite), `gh` CLI, `git` CLI, tmux

---

### Task 1: Add `prNumber` to Session Model + DB Migration

**Files:**
- Modify: `Sources/Models/Session.swift:4-47`
- Modify: `Sources/Persistence/Records.swift:7-73`
- Modify: `Sources/Persistence/Database.swift:178-184`
- Test: `Tests/ModelsTests/SessionTests.swift`
- Test: `Tests/PersistenceTests/DatabaseTests.swift`

- [ ] **Step 1: Write failing test for Session.prNumber**

Add to `Tests/ModelsTests/SessionTests.swift`:

```swift
@Test func sessionPRNumberDefaultsToNil() {
    let session = Session(title: "test", path: "/tmp")
    #expect(session.prNumber == nil)
}

@Test func sessionPRNumberPreserved() {
    let session = Session(title: "review", path: "/tmp", prNumber: 247)
    #expect(session.prNumber == 247)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter sessionPRNumber`
Expected: FAIL — `Session` has no `prNumber` parameter

- [ ] **Step 3: Add `prNumber` to Session model**

In `Sources/Models/Session.swift`, add the property after `worktreeBranch`:

```swift
public var prNumber: Int?
```

Add to the `init` parameter list after `worktreeBranch`:

```swift
prNumber: Int? = nil,
```

Add to the `init` body after `self.worktreeBranch = worktreeBranch`:

```swift
self.prNumber = prNumber
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter sessionPRNumber`
Expected: PASS

- [ ] **Step 5: Write failing test for DB round-trip**

Add to `Tests/PersistenceTests/DatabaseTests.swift`:

```swift
@Test func sessionPRNumberPersistence() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "review", path: "/tmp", prNumber: 42)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.prNumber == 42)
}

@Test func sessionPRNumberNilPersistence() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test", path: "/tmp")
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.prNumber == nil)
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `swift test --filter sessionPRNumber`
Expected: FAIL — `SessionRecord` doesn't have `prNumber`, DB column missing

- [ ] **Step 7: Update SessionRecord and add migration v9**

In `Sources/Persistence/Records.swift`, add to `SessionRecord`:

```swift
var prNumber: Int?
```

In `SessionRecord.init(_ session:)`, add after `self.sortOrder = session.sortOrder`:

```swift
self.prNumber = session.prNumber
```

In `SessionRecord.toSession()`, add `prNumber: prNumber` to the `Session(...)` call after `sortOrder: sortOrder`.

In `Sources/Persistence/Database.swift`, add after the `v8_project_branch_prefix` migration (before `try migrator.migrate(dbQueue)`):

```swift
migrator.registerMigration("v9_session_pr_number") { db in
    try db.alter(table: "sessions") { t in
        t.add(column: "prNumber", .integer)
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter sessionPRNumber`
Expected: PASS

- [ ] **Step 9: Run full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 10: Commit**

```bash
git add Sources/Models/Session.swift Sources/Persistence/Records.swift Sources/Persistence/Database.swift Tests/ModelsTests/SessionTests.swift Tests/PersistenceTests/DatabaseTests.swift
git commit -m "feat: add prNumber field to Session model with DB migration v9"
```

---

### Task 2: Add `PRManager.resolvePR()` and `PRResolveError`

**Files:**
- Modify: `Sources/GitHubOperations/PRManager.swift:30-296`
- Test: `Tests/GitHubOperationsTests/PRManagerTests.swift`

- [ ] **Step 1: Write failing test for PRResolveError**

Add to `Tests/GitHubOperationsTests/PRManagerTests.swift`:

```swift
@Test func prResolveErrorNotFoundDescription() {
    let error = PRResolveError.notFound(number: 247, repo: "owner/repo")
    #expect(error.errorDescription?.contains("247") == true)
    #expect(error.errorDescription?.contains("owner/repo") == true)
}

@Test func prResolveErrorNoProjectDescription() {
    let error = PRResolveError.noProject
    #expect(error.errorDescription != nil)
    #expect(!error.errorDescription!.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter prResolveError`
Expected: FAIL — `PRResolveError` doesn't exist

- [ ] **Step 3: Add `PRResolveError` to PRManager.swift**

Add after the existing `GHError` enum (around line 306-315) in `Sources/GitHubOperations/PRManager.swift`:

```swift
public enum PRResolveError: Error, LocalizedError {
    case notFound(number: Int, repo: String)
    case noProject

    public var errorDescription: String? {
        switch self {
        case .notFound(let number, let repo):
            "PR #\(number) not found in \(repo)"
        case .noProject:
            "No project matches the PR repository"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter prResolveError`
Expected: PASS

- [ ] **Step 5: Add `resolvePR()` method to PRManager**

Add inside the `PRManager` actor, after the `fetchPRForWorktree` method (around line 155):

```swift
/// Resolve a PR by number — used by PR review session creation.
/// Returns a full PullRequest with branch info, state, and checks.
public func resolvePR(repo: String, number: Int, host: String? = nil) async throws -> PullRequest {
    let output = try await runGH(
        args: [
            "pr", "view", "\(number)",
            "--repo", repo,
            "--json",
            "number,title,state,headRefName,baseRefName,author,url,isDraft,additions,deletions,changedFiles,createdAt,updatedAt,reviewDecision,statusCheckRollup",
        ], host: host)
    guard let pr = try parseSinglePR(output) else {
        throw PRResolveError.notFound(number: number, repo: repo)
    }
    return pr
}
```

- [ ] **Step 6: Run full test suite**

Run: `swift test`
Expected: All tests pass (no integration test for `resolvePR` since it requires `gh` CLI + network)

- [ ] **Step 7: Commit**

```bash
git add Sources/GitHubOperations/PRManager.swift Tests/GitHubOperationsTests/PRManagerTests.swift
git commit -m "feat: add PRManager.resolvePR() for PR review session resolution"
```

---

### Task 3: Add `WorktreeManager.checkoutWorktree()`

**Files:**
- Modify: `Sources/GitOperations/WorktreeManager.swift:5-107`
- Test: `Tests/GitOperationsTests/WorktreeManagerTests.swift`

- [ ] **Step 1: Write integration test for checkoutWorktree**

Add to `Tests/GitOperationsTests/WorktreeManagerTests.swift`. This test creates a branch in the local repo (simulating a fetched remote branch) and checks it out as a worktree:

```swift
@Test func checkoutExistingBranch() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        // Create a branch to simulate an existing remote branch
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "git branch existing-feature"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let worktreePath = try await manager.checkoutWorktree(
            repoPath: repoPath,
            branch: "existing-feature"
        )

        #expect(FileManager.default.fileExists(atPath: worktreePath))

        // Verify the worktree is on the correct branch
        let branch = await manager.currentBranch(path: worktreePath)
        #expect(branch == "existing-feature")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter checkoutExistingBranch`
Expected: FAIL — `checkoutWorktree` method doesn't exist

- [ ] **Step 3: Implement `checkoutWorktree()`**

Add to `Sources/GitOperations/WorktreeManager.swift` inside the actor, after `createWorktree()`:

```swift
/// Create a worktree for an existing branch (e.g., a PR's remote branch).
///
/// Unlike `createWorktree()` which creates a new branch, this checks out
/// an existing branch. Fetches from origin first, then creates a tracking worktree.
/// Falls back to using an existing local branch if the tracking branch creation fails.
///
/// - Parameters:
///   - repoPath: Path to the main repository
///   - branch: Name of the existing branch to check out
/// - Returns: Path to the created worktree directory
public func checkoutWorktree(
    repoPath: String,
    branch: String
) async throws -> String {
    let sanitized = sanitizeBranchName(branch)
    let worktreePath = "\(repoPath)/.worktrees/\(sanitized)"

    // Fetch the branch from origin (non-fatal if no remote)
    try? await runGit(in: repoPath, args: ["fetch", "origin", branch])

    // Try creating worktree tracking the remote branch
    do {
        try await runGit(in: repoPath, args: [
            "worktree", "add", "--track", "-b", sanitized, worktreePath, "origin/\(branch)",
        ])
    } catch {
        // Fallback: local branch already exists — reuse it
        try await runGit(in: repoPath, args: [
            "worktree", "add", worktreePath, sanitized,
        ])
    }

    return worktreePath
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter checkoutExistingBranch`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/GitOperations/WorktreeManager.swift Tests/GitOperationsTests/WorktreeManagerTests.swift
git commit -m "feat: add WorktreeManager.checkoutWorktree() for existing branches"
```

---

### Task 4: Add `TmuxSessionManager.sendText()` for prompt pre-fill

**Files:**
- Modify: `Sources/Terminal/TmuxSessionManager.swift:16-129`

- [ ] **Step 1: Add `sendText()` method**

Add to `Sources/Terminal/TmuxSessionManager.swift` inside the actor, after `attachCommand()`:

```swift
/// Send text to a tmux session without pressing Enter.
/// Used to pre-fill terminal input (e.g., initial review prompt).
public func sendText(sessionName: String, text: String) async throws {
    // send-keys -l sends literal text (no key interpretation)
    try await runTmux(args: ["send-keys", "-t", sessionName, "-l", text])
}
```

- [ ] **Step 2: Run full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add Sources/Terminal/TmuxSessionManager.swift
git commit -m "feat: add TmuxSessionManager.sendText() for terminal pre-fill"
```

---

### Task 5: Add `reviewPR()` to SidebarActions protocol

**Files:**
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift:6-24`

- [ ] **Step 1: Add method to protocol**

In `Sources/Views/Sidebar/ProjectTreeView.swift`, add to the `SidebarActions` protocol after the `selectPR` method:

```swift
func reviewPR(_ pr: PullRequest)
```

- [ ] **Step 2: Build to check for compile errors**

Run: `swift build 2>&1 | head -20`
Expected: Compile error — `RunwayStore` doesn't conform (missing `reviewPR`). This is expected; we'll add conformance in Task 7.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/Sidebar/ProjectTreeView.swift
git commit -m "feat: add reviewPR to SidebarActions protocol"
```

---

### Task 6: Create `ReviewPRSheet` view

**Files:**
- Create: `Sources/Views/Shared/ReviewPRSheet.swift`

- [ ] **Step 1: Create the ReviewPRSheet view**

Create `Sources/Views/Shared/ReviewPRSheet.swift`:

```swift
import Models
import SwiftUI
import Theme

/// Confirmation sheet for creating a PR review session.
///
/// Shows PR info, editable session name, project picker, and initial prompt.
/// Used by both the ⌘⇧R dialog (after PR resolution) and the PR dashboard "Review" button.
public struct ReviewPRSheet: View {
    let pr: PullRequest
    let projects: [Project]
    let onCreate: (String, String?, String) -> Void  // (sessionName, projectID, initialPrompt)

    @State private var sessionName: String
    @State private var selectedProjectID: String?
    @State private var initialPrompt: String = "Review this PR"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        projects: [Project],
        onCreate: @escaping (String, String?, String) -> Void
    ) {
        self.pr = pr
        self.projects = projects
        self.onCreate = onCreate

        // Default session name from PR title (truncated)
        let truncatedTitle = pr.title.count > 60 ? String(pr.title.prefix(57)) + "..." : pr.title
        self._sessionName = State(initialValue: "Review: \(truncatedTitle)")

        // Auto-detect project from PR repo
        let matched = projects.first(where: { $0.ghRepo == pr.repo })
        self._selectedProjectID = State(initialValue: matched?.id)
    }

    private var autoDetected: Bool {
        projects.first(where: { $0.ghRepo == pr.repo })?.id == selectedProjectID
    }

    private var projectsWithRepo: [Project] {
        projects.filter { $0.ghRepo != nil }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // PR info banner
            prBanner

            // Form fields
            VStack(alignment: .leading, spacing: 12) {
                formField("Session Name") {
                    TextField("Session name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                }

                formField("Project") {
                    HStack {
                        Picker("Project", selection: $selectedProjectID) {
                            Text("None").tag(nil as String?)
                            ForEach(projectsWithRepo) { project in
                                Text(project.name).tag(project.id as String?)
                            }
                        }
                        .labelsHidden()

                        if autoDetected {
                            Text("Auto-detected")
                                .font(.caption)
                                .foregroundColor(theme.chrome.accent)
                        }
                    }
                }

                formField("Initial Prompt") {
                    TextField("Prompt to pre-fill in terminal", text: $initialPrompt)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Review Session") {
                    onCreate(sessionName, selectedProjectID, initialPrompt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sessionName.isEmpty || selectedProjectID == nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    // MARK: - Subviews

    private var prBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PRStateBadge(state: pr.state)
                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
            }
            Text(pr.title)
                .font(.headline)
            HStack(spacing: 12) {
                Text("by \(pr.author)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(pr.headBranch)
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
                .foregroundColor(theme.chrome.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .cornerRadius(8)
    }

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            content()
        }
    }
}

// MARK: - PR State Badge (reusable inline)

private struct PRStateBadge: View {
    let state: PRState
    @Environment(\.theme) private var theme

    var body: some View {
        Text(state.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(.white)
            .background(badgeColor)
            .cornerRadius(4)
    }

    private var badgeColor: Color {
        switch state {
        case .open: theme.chrome.green
        case .draft: theme.chrome.textDim
        case .merged: theme.chrome.purple
        case .closed: theme.chrome.red
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | head -20`
Expected: Build succeeds (or only fails on `RunwayStore` missing `reviewPR` conformance from Task 5)

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/Shared/ReviewPRSheet.swift
git commit -m "feat: add ReviewPRSheet confirmation dialog for PR review sessions"
```

---

### Task 7: Wire up RunwayStore — state, handleReviewPR, SidebarActions conformance

**Files:**
- Modify: `Sources/App/RunwayStore.swift`

- [ ] **Step 1: Add review PR state properties**

In `Sources/App/RunwayStore.swift`, add after `focusSidebarSearch` (around line 41):

```swift
var showReviewPRDialog: Bool = false
var showReviewPRSheet: Bool = false
var reviewPRCandidate: PullRequest? = nil
var isResolvingPR: Bool = false
```

- [ ] **Step 2: Add `handleReviewPR()` method**

Add a new `// MARK: - PR Review Session` section after the `// MARK: - Issues` section (before the `SidebarActions` extension):

```swift
// MARK: - PR Review Session

func handleReviewPR(pr: PullRequest, sessionName: String, projectID: String?, initialPrompt: String) async {
    guard let project = projects.first(where: { $0.id == projectID }) else {
        statusMessage = .error("No project selected for PR review")
        return
    }

    // 1. Create worktree for existing branch
    let worktreePath: String
    do {
        worktreePath = try await worktreeManager.checkoutWorktree(
            repoPath: project.path,
            branch: pr.headBranch
        )
    } catch {
        statusMessage = .error("Worktree failed: \(error.localizedDescription)")
        return
    }

    // 2. Resolve permission mode
    let resolvedMode = project.permissionMode ?? .default

    // 3. Create session
    var session = Session(
        title: sessionName,
        projectID: projectID,
        path: worktreePath,
        tool: .claude,
        status: .starting,
        worktreeBranch: pr.headBranch,
        prNumber: pr.number,
        permissionMode: resolvedMode
    )

    // 4. Create tmux session
    if tmuxAvailable {
        let tmuxName = "runway-\(session.id)"
        let command = ([session.tool.command] + session.permissionMode.cliFlags).joined(separator: " ")

        do {
            try await tmuxManager.createSession(
                name: tmuxName,
                workDir: worktreePath,
                command: command,
                env: [
                    "RUNWAY_SESSION_ID": session.id,
                    "RUNWAY_TITLE": session.title,
                ]
            )
            session.status = .running
        } catch {
            statusMessage = .error("tmux session failed: \(error.localizedDescription)")
        }
    }

    // 5. Save and select
    sessions.append(session)
    do {
        try database?.saveSession(session)
    } catch {
        statusMessage = .error("Failed to save session: \(error.localizedDescription)")
    }
    selectedSessionID = session.id
    currentView = .sessions

    // 6. Link PR immediately
    sessionPRs[session.id] = pr

    // 7. Pre-fill initial prompt (without Enter — user decides when to send)
    if !initialPrompt.isEmpty, tmuxAvailable {
        let tmuxName = "runway-\(session.id)"
        // Small delay to let the shell/claude start before sending text
        try? await Task.sleep(for: .milliseconds(500))
        try? await tmuxManager.sendText(sessionName: tmuxName, text: initialPrompt)
    }
}

func resolvePRForReview(number: Int, repo: String, host: String?) async {
    isResolvingPR = true
    defer { isResolvingPR = false }

    do {
        let pr = try await prManager.resolvePR(repo: repo, number: number, host: host)
        reviewPRCandidate = pr
        showReviewPRSheet = true
    } catch {
        statusMessage = .error("Failed to resolve PR #\(number): \(error.localizedDescription)")
    }
}
```

- [ ] **Step 3: Add `reviewPR(_:)` to SidebarActions conformance**

In the `extension RunwayStore: SidebarActions` block, add after `selectPR`:

```swift
public func reviewPR(_ pr: PullRequest) {
    reviewPRCandidate = pr
    showReviewPRSheet = true
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: add RunwayStore PR review session handling and state"
```

---

### Task 8: Wire up RunwayApp — keyboard shortcut, sheets, PR number dialog

**Files:**
- Modify: `Sources/App/RunwayApp.swift`

- [ ] **Step 1: Add ⌘⇧R keyboard shortcut**

In `Sources/App/RunwayApp.swift`, inside the `.commands` block, add after the "Search Sessions" button:

```swift
Button("Review PR") { store.showReviewPRDialog = true }
    .keyboardShortcut("r", modifiers: [.command, .shift])
```

- [ ] **Step 2: Add ReviewPRSheet presentation**

In `ContentView`, add a new `.sheet` modifier after the existing `NewProjectDialog` sheet (around line 136):

```swift
.sheet(
    isPresented: Binding(
        get: { store.showReviewPRSheet },
        set: { store.showReviewPRSheet = $0 }
    )
) {
    if let pr = store.reviewPRCandidate {
        ReviewPRSheet(
            pr: pr,
            projects: store.projects
        ) { sessionName, projectID, initialPrompt in
            Task {
                await store.handleReviewPR(
                    pr: pr,
                    sessionName: sessionName,
                    projectID: projectID,
                    initialPrompt: initialPrompt
                )
            }
            store.reviewPRCandidate = nil
        }
        .theme(theme)
    }
}
.sheet(
    isPresented: Binding(
        get: { store.showReviewPRDialog },
        set: { store.showReviewPRDialog = $0 }
    )
) {
    ReviewPRNumberDialog(
        projects: store.projects,
        isResolving: store.isResolvingPR,
        onResolve: { number, repo, host in
            Task { await store.resolvePRForReview(number: number, repo: repo, host: host) }
            store.showReviewPRDialog = false
        }
    )
    .theme(theme)
}
```

- [ ] **Step 3: Create `ReviewPRNumberDialog`**

This is the small ⌘⇧R entry dialog. Add it to `Sources/Views/Shared/ReviewPRSheet.swift` (same file as `ReviewPRSheet` since they're closely related):

```swift
/// Small dialog for entering a PR number — opened via ⌘⇧R.
public struct ReviewPRNumberDialog: View {
    let projects: [Project]
    let isResolving: Bool
    let onResolve: (Int, String, String?) -> Void  // (number, repo, host)

    @State private var prNumberText: String = ""
    @State private var selectedProjectID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    public init(
        projects: [Project],
        isResolving: Bool,
        onResolve: @escaping (Int, String, String?) -> Void
    ) {
        self.projects = projects
        self.isResolving = isResolving
        self.onResolve = onResolve

        // Default to first project with a ghRepo
        let firstWithRepo = projects.first(where: { $0.ghRepo != nil })
        self._selectedProjectID = State(initialValue: firstWithRepo?.id)
    }

    private var selectedProject: Project? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    private var projectsWithRepo: [Project] {
        projects.filter { $0.ghRepo != nil }
    }

    private var canResolve: Bool {
        guard let number = Int(prNumberText), number > 0 else { return false }
        return selectedProject?.ghRepo != nil && !isResolving
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review PR")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("PR number", text: $prNumberText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { resolve() }

                if projectsWithRepo.count > 1 {
                    Picker("in", selection: $selectedProjectID) {
                        ForEach(projectsWithRepo) { project in
                            Text(project.name).tag(project.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                } else if let project = selectedProject {
                    Text("in \(project.name)")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
            }

            if isResolving {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Resolving PR...")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Resolve") { resolve() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canResolve)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func resolve() {
        guard let number = Int(prNumberText), let project = selectedProject, let repo = project.ghRepo else { return }
        onResolve(number, repo, project.ghHost)
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RunwayApp.swift Sources/Views/Shared/ReviewPRSheet.swift
git commit -m "feat: wire up ⌘⇧R shortcut and ReviewPR sheets in RunwayApp"
```

---

### Task 9: Add "Review" button to PR dashboard and project PR rows

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDashboardView.swift`
- Modify: `Sources/Views/ProjectPage/ProjectPRsTab.swift`
- Modify: `Sources/Views/ProjectPage/ProjectPageView.swift`
- Modify: `Sources/App/RunwayApp.swift` (pass callback through)

- [ ] **Step 1: Add `onReviewPR` callback to `PRDashboardView`**

In `Sources/Views/PRDashboard/PRDashboardView.swift`, add a new property after `onSendToSession`:

```swift
var onReviewPR: ((PullRequest) -> Void)?
```

Add the parameter to the `init` (after `onSendToSession`):

```swift
onReviewPR: ((PullRequest) -> Void)? = nil
```

Add to init body:

```swift
self.onReviewPR = onReviewPR
```

- [ ] **Step 2: Add Review button to `PRRowView`**

`PRRowView` is a private struct inside `PRDashboardView.swift`. It needs access to the callback. The simplest approach: add the callback as a property and pass it from the `List`.

Modify `PRRowView` to accept a callback:

```swift
struct PRRowView: View {
    let pr: PullRequest
    var onReview: (() -> Void)?
    @Environment(\.theme) private var theme
```

Add a context menu to the `PRRowView` body, after `.opacity(pr.isDraft ? 0.5 : 1.0)`:

```swift
.contextMenu {
    if let onReview {
        Button("Open Review Session") { onReview() }
    }
}
```

Update the `List` in `PRDashboardView.body` to pass the callback:

```swift
PRRowView(pr: pr, onReview: onReviewPR.map { callback in { callback(pr) } })
```

- [ ] **Step 3: Add `onReviewPR` to `ProjectPRsTab`**

In `Sources/Views/ProjectPage/ProjectPRsTab.swift`, add property:

```swift
var onReviewPR: ((PullRequest) -> Void)?
```

Add to init:

```swift
onReviewPR: ((PullRequest) -> Void)? = nil
```

Add to init body:

```swift
self.onReviewPR = onReviewPR
```

Add context menu to `ProjectPRRowView`. Similar to above — add an `onReview` closure property to `ProjectPRRowView`:

```swift
private struct ProjectPRRowView: View {
    let pr: PullRequest
    var onReview: (() -> Void)?
    @Environment(\.theme) private var theme
```

Add after `.padding(.vertical, 4)`:

```swift
.contextMenu {
    if let onReview {
        Button("Open Review Session") { onReview() }
    }
}
```

Update the `ForEach` in `prList` to pass through:

```swift
ProjectPRRowView(pr: pr, onReview: onReviewPR.map { callback in { callback(pr) } })
```

- [ ] **Step 4: Thread `onReviewPR` through `ProjectPageView`**

In `Sources/Views/ProjectPage/ProjectPageView.swift`, add property:

```swift
var onReviewPR: ((PullRequest) -> Void)?
```

Add to init with default nil. Pass it through to `ProjectPRsTab`:

```swift
ProjectPRsTab(
    // ... existing parameters ...
    onReviewPR: onReviewPR
)
```

- [ ] **Step 5: Pass callback from `RunwayApp` ContentView**

In `Sources/App/RunwayApp.swift`, update the `PRDashboardView` instantiation to pass `onReviewPR`:

```swift
onReviewPR: { pr in store.reviewPR(pr) }
```

Update the `ProjectPageView` instantiation to pass `onReviewPR`:

```swift
onReviewPR: { pr in store.reviewPR(pr) }
```

- [ ] **Step 6: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add Sources/Views/PRDashboard/PRDashboardView.swift Sources/Views/ProjectPage/ProjectPRsTab.swift Sources/Views/ProjectPage/ProjectPageView.swift Sources/App/RunwayApp.swift
git commit -m "feat: add Review button and context menu to PR dashboard and project PR rows"
```

---

### Task 10: Final integration test — full build and verify

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Run full build**

Run: `swift build`
Expected: Build succeeds with no warnings

- [ ] **Step 3: Verify no regressions in existing features**

Run: `swift test 2>&1 | tail -5`
Expected: "Test Suite 'All tests' passed"

- [ ] **Step 4: Commit any final fixes if needed**

Only if previous steps revealed issues.
