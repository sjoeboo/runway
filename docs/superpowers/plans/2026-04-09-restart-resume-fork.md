# Restart Resume, Fork Session, and Happy Indicator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make restart resume previous agent conversations, add session forking via worktree branching, and show Happy/fork indicators in sidebar and header.

**Architecture:** Add `resumeArguments` to `AgentProfile`, extract a shared `buildAgentCommand` helper in `RunwayStore`, add fork pre-population state to drive `NewSessionDialog`, and extend sidebar row + header views with indicator badges. The `NewSessionRequest` gains a `baseBranch` field for fork worktree creation.

**Tech Stack:** Swift, SwiftUI, Swift Testing, GRDB

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Models/AgentProfile.swift` | Modify | Add `resumeArguments` field to struct + init + built-ins |
| `Sources/Models/NewSessionRequest.swift` | Modify | Add `baseBranch: String?` field |
| `Sources/App/RunwayStore.swift` | Modify | Extract `buildAgentCommand`, update `restartSession` + `startTmuxSession`, add fork state + `forkSession` method, pass `baseBranch` in `handleNewSessionRequest` |
| `Sources/Views/Sidebar/ProjectTreeView.swift` | Modify | Add `forkSession` to protocol, fork context menu, fork + Happy indicators in row |
| `Sources/Views/SessionDetail/SessionHeaderView.swift` | Modify | Add Happy to tool badge, add "Forked from" line |
| `Sources/Views/Shared/NewSessionDialog.swift` | Modify | Accept fork pre-population via new init parameters |
| `Sources/App/RunwayApp.swift` | Modify | Pass fork state to `NewSessionDialog` |
| `Tests/ModelsTests/AgentProfileTests.swift` | Modify | Test `resumeArguments` on built-ins + JSON decoding |

---

### Task 1: Add `resumeArguments` to AgentProfile

**Files:**
- Modify: `Sources/Models/AgentProfile.swift:5-50` (struct + init)
- Modify: `Sources/Models/AgentProfile.swift:56-157` (built-in profiles)
- Modify: `Sources/Models/AgentProfile.swift:163-176` (defaultProfile)
- Test: `Tests/ModelsTests/AgentProfileTests.swift`

- [ ] **Step 1: Write failing tests for resumeArguments**

Add to `Tests/ModelsTests/AgentProfileTests.swift`:

```swift
@Test func claudeProfileHasResumeArguments() {
    #expect(AgentProfile.claude.resumeArguments == ["--continue"])
}

@Test func geminiProfileHasResumeArguments() {
    #expect(AgentProfile.gemini.resumeArguments == ["--resume"])
}

@Test func codexProfileHasResumeArguments() {
    #expect(AgentProfile.codex.resumeArguments == ["--continue"])
}

@Test func shellProfileHasEmptyResumeArguments() {
    #expect(AgentProfile.shell.resumeArguments.isEmpty)
}

@Test func customProfileHasEmptyResumeArguments() {
    let profile = AgentProfile.defaultProfile(for: .custom("aider"))
    #expect(profile.resumeArguments.isEmpty)
}

@Test func agentProfileJSONDecodingWithResumeArguments() throws {
    let json = """
        {
            "id": "cursor",
            "name": "Cursor",
            "command": "cursor",
            "arguments": [],
            "resumeArguments": ["--resume-last"],
            "runningPatterns": [],
            "waitingPatterns": [],
            "idlePatterns": ["$"],
            "lineStartIdlePatterns": [],
            "spinnerChars": [],
            "hookEnabled": false,
            "icon": "terminal.fill"
        }
        """
    let data = try #require(json.data(using: .utf8))
    let profile = try JSONDecoder().decode(AgentProfile.self, from: data)
    #expect(profile.resumeArguments == ["--resume-last"])
}

@Test func agentProfileJSONDecodingWithoutResumeArguments() throws {
    let json = """
        {
            "id": "aider",
            "name": "Aider",
            "command": "aider",
            "arguments": ["--watch"],
            "runningPatterns": ["Applying edit"],
            "waitingPatterns": ["Add these files?"],
            "idlePatterns": ["aider>"],
            "lineStartIdlePatterns": [],
            "spinnerChars": [],
            "hookEnabled": false,
            "icon": "terminal.fill"
        }
        """
    let data = try #require(json.data(using: .utf8))
    let profile = try JSONDecoder().decode(AgentProfile.self, from: data)
    #expect(profile.resumeArguments.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentProfileTests 2>&1 | tail -20`
Expected: Multiple failures — `resumeArguments` does not exist on `AgentProfile`.

- [ ] **Step 3: Add `resumeArguments` field to AgentProfile**

In `Sources/Models/AgentProfile.swift`, add the field to the struct (after `spinnerChars`):

```swift
/// CLI arguments to resume a previous conversation (e.g., ["--continue"]).
public let resumeArguments: [String]
```

Update the `init` — add parameter with default `[]` (after `spinnerChars`):

```swift
public init(
    id: String,
    name: String,
    command: String,
    arguments: [String] = [],
    runningPatterns: [String] = [],
    waitingPatterns: [String] = [],
    idlePatterns: [String] = [],
    lineStartIdlePatterns: [String] = [],
    spinnerChars: [String] = [],
    resumeArguments: [String] = [],
    hookEnabled: Bool = false,
    icon: String = "terminal.fill"
) {
    self.id = id
    self.name = name
    self.command = command
    self.arguments = arguments
    self.runningPatterns = runningPatterns
    self.waitingPatterns = waitingPatterns
    self.idlePatterns = idlePatterns
    self.lineStartIdlePatterns = lineStartIdlePatterns
    self.spinnerChars = spinnerChars
    self.resumeArguments = resumeArguments
    self.hookEnabled = hookEnabled
    self.icon = icon
}
```

Update built-in profiles — add `resumeArguments` to each:

**Claude** (after `lineStartIdlePatterns`):
```swift
resumeArguments: ["--continue"],
```

**Shell** — no change needed (default `[]` is correct).

**Gemini** (after `lineStartIdlePatterns`):
```swift
resumeArguments: ["--resume"],
```

**Codex** (after `idlePatterns`):
```swift
resumeArguments: ["--continue"],
```

**`defaultProfile(for:)`** — the custom case already uses the default `[]`, so no change needed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AgentProfileTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/AgentProfile.swift Tests/ModelsTests/AgentProfileTests.swift
git commit -m "feat: add resumeArguments to AgentProfile for session resume support"
```

---

### Task 2: Add `baseBranch` to NewSessionRequest

**Files:**
- Modify: `Sources/Models/NewSessionRequest.swift:4-42`

- [ ] **Step 1: Add `baseBranch` field to NewSessionRequest**

In `Sources/Models/NewSessionRequest.swift`, add the field after `issueNumber`:

```swift
public let baseBranch: String?
```

Add the parameter to `init` with default `nil` (after `issueNumber`):

```swift
public init(
    title: String,
    projectID: String?,
    parentID: String? = nil,
    path: String,
    tool: Tool,
    useWorktree: Bool,
    branchName: String?,
    permissionMode: PermissionMode = .default,
    useHappy: Bool = false,
    initialPrompt: String? = nil,
    issueNumber: Int? = nil,
    baseBranch: String? = nil
) {
    self.title = title
    self.projectID = projectID
    self.parentID = parentID
    self.path = path
    self.tool = tool
    self.useWorktree = useWorktree
    self.branchName = branchName
    self.permissionMode = permissionMode
    self.useHappy = useHappy
    self.initialPrompt = initialPrompt
    self.issueNumber = issueNumber
    self.baseBranch = baseBranch
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds. The default `nil` means all existing call sites remain compatible.

- [ ] **Step 3: Commit**

```bash
git add Sources/Models/NewSessionRequest.swift
git commit -m "feat: add baseBranch to NewSessionRequest for fork worktree creation"
```

---

### Task 3: Extract `buildAgentCommand` and fix restart

**Files:**
- Modify: `Sources/App/RunwayStore.swift:427-475` (startTmuxSession)
- Modify: `Sources/App/RunwayStore.swift:498-548` (restartSession)

- [ ] **Step 1: Add `buildAgentCommand` helper to RunwayStore**

Add this private method in `RunwayStore`, before `startTmuxSession` (around line 426):

```swift
/// Builds the CLI command string for an agent session.
/// Returns nil for shell sessions (tmux uses its default shell).
private func buildAgentCommand(
    session: Session,
    profile: AgentProfile,
    resume: Bool = false
) -> String? {
    guard profile.id != "shell" else { return nil }
    var parts: [String] = []
    if session.useHappy {
        parts.append("happy")
        parts.append(session.tool.command)
    } else {
        parts.append(profile.command)
    }
    parts.append(contentsOf: profile.arguments)
    if resume {
        parts.append(contentsOf: profile.resumeArguments)
    }
    if session.tool.supportsPermissionModes {
        parts.append(contentsOf: session.permissionMode.cliFlags(for: session.tool))
    }
    return parts.joined(separator: " ")
}
```

- [ ] **Step 2: Update `startTmuxSession` to use the helper**

Replace the command construction block in `startTmuxSession` (lines 436-452) with:

```swift
let tmuxName = "runway-\(session.id)"
let profile = profileForSession(session)
let toolCommand = buildAgentCommand(session: session, profile: profile, resume: false)
```

Remove the old `let profile`, `let toolCommand`, `if profile.id == "shell"` block, and the `var parts` block that follows. Keep everything else (the `tmuxManager.createSession` call and below).

- [ ] **Step 3: Update `restartSession` to use the helper with resume**

Replace the command construction block in `restartSession` (lines 517-528) with:

```swift
let profile = profileForSession(session)
let toolCommand = buildAgentCommand(session: session, profile: profile, resume: true)
```

Remove the old `if profile.id == "shell"` / `else` block.

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass. This is a refactor with no behavioral change to testable units — the command construction is verified via integration (tmux launch).

- [ ] **Step 6: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "refactor: extract buildAgentCommand helper, fix restart dropping useHappy"
```

---

### Task 4: Pass `baseBranch` through `handleNewSessionRequest`

**Files:**
- Modify: `Sources/App/RunwayStore.swift:352-424` (handleNewSessionRequest)

- [ ] **Step 1: Update `handleNewSessionRequest` to use `baseBranch`**

In `handleNewSessionRequest`, change the `baseBranch` resolution (line 390) from:

```swift
let baseBranch = project?.defaultBranch ?? "main"
```

to:

```swift
let baseBranch = request.baseBranch ?? project?.defaultBranch ?? "main"
```

This single-line change makes forks use the source session's branch as the base.

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: support custom baseBranch in handleNewSessionRequest for forks"
```

---

### Task 5: Add fork state and `forkSession` to RunwayStore

**Files:**
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift:11-25` (SidebarActions protocol)
- Modify: `Sources/App/RunwayStore.swift:39-59` (state properties)
- Modify: `Sources/App/RunwayStore.swift:1545-1552` (SidebarActions conformance)

- [ ] **Step 1: Add `forkSession` to SidebarActions protocol**

In `Sources/Views/Sidebar/ProjectTreeView.swift`, add to the protocol (after `restartSession`):

```swift
func forkSession(id: String)
```

- [ ] **Step 2: Add fork pre-population state to RunwayStore**

In `Sources/App/RunwayStore.swift`, add after `newSessionParentID` (around line 42):

```swift
var forkSourceSession: Session?
```

- [ ] **Step 3: Implement `forkSession` in RunwayStore's SidebarActions conformance**

In the `SidebarActions` conformance extension (after `newSession`), add:

```swift
public func forkSession(id: String) {
    guard let session = sessions.first(where: { $0.id == id }),
          session.worktreeBranch != nil
    else { return }
    forkSourceSession = session
    newSessionProjectID = session.projectID
    newSessionParentID = session.id
    showNewSessionDialog = true
}
```

- [ ] **Step 4: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/Sidebar/ProjectTreeView.swift Sources/App/RunwayStore.swift
git commit -m "feat: add forkSession to SidebarActions and RunwayStore"
```

---

### Task 6: Pre-populate NewSessionDialog for forks

**Files:**
- Modify: `Sources/Views/Shared/NewSessionDialog.swift:50-67` (init)
- Modify: `Sources/Views/Shared/NewSessionDialog.swift:159-162` (onAppear)
- Modify: `Sources/Views/Shared/NewSessionDialog.swift:436-459` (createNormalSession)
- Modify: `Sources/App/RunwayApp.swift:147-161` (sheet presentation)

- [ ] **Step 1: Add fork parameters to NewSessionDialog init**

In `Sources/Views/Shared/NewSessionDialog.swift`, add a new stored property and init parameter:

Add property after `selectedTemplateID`:
```swift
let forkSource: Session?
```

Update `init` — add parameter with default `nil` (after `templates`):
```swift
public init(
    projects: [Project],
    profiles: [AgentProfile] = AgentProfile.builtIn,
    initialProjectID: String? = nil,
    parentID: String? = nil,
    templates: [SessionTemplate] = [],
    forkSource: Session? = nil,
    onCreate: @escaping (NewSessionRequest) -> Void,
    onCreateReview: ((ReviewSessionRequest) async throws -> Void)? = nil
) {
    self.projects = projects
    self.profiles = profiles
    self.initialProjectID = initialProjectID
    self.parentID = parentID
    self.templates = templates
    self.forkSource = forkSource
    self.onCreate = onCreate
    self.onCreateReview = onCreateReview
    self._selectedProjectID = State(initialValue: initialProjectID)
}
```

- [ ] **Step 2: Pre-populate state from fork source on appear**

Update the `.onAppear` block (line 159-162) to set fields from `forkSource`:

```swift
.onAppear {
    permissionMode = defaultPermissionMode
    if let source = forkSource {
        title = "Fork of \(source.title)"
        switch source.tool {
        case .claude: selectedProfileID = "claude"
        case .gemini: selectedProfileID = "gemini"
        case .codex: selectedProfileID = "codex"
        case .shell: selectedProfileID = "shell"
        case .custom(let name): selectedProfileID = name
        }
        permissionMode = source.permissionMode
        useHappy = source.useHappy
        useWorktree = true
        if let sourceBranch = source.worktreeBranch {
            branchName = "\(sourceBranch)-fork"
            branchManuallyEdited = true
        }
    }
    titleFocused = true
}
```

- [ ] **Step 3: Pass `baseBranch` from fork source in `createNormalSession`**

Update the `NewSessionRequest` construction in `createNormalSession` (line 445-456) to include `baseBranch`:

```swift
let request = NewSessionRequest(
    title: title,
    projectID: selectedProjectID,
    parentID: parentID,
    path: path,
    tool: selectedTool,
    useWorktree: useWorktree,
    branchName: useWorktree ? branchName : nil,
    permissionMode: selectedTool.supportsPermissionModes ? permissionMode : .default,
    useHappy: selectedTool.supportsHappy ? useHappy : false,
    initialPrompt: (selectedTool.supportsInitialPrompt && !initialPrompt.isEmpty) ? initialPrompt : nil,
    baseBranch: forkSource?.worktreeBranch
)
```

- [ ] **Step 4: Pass fork state from RunwayApp to NewSessionDialog**

In `Sources/App/RunwayApp.swift`, update the `NewSessionDialog` instantiation (line 147) to pass `forkSource`:

```swift
NewSessionDialog(
    projects: store.projects,
    profiles: store.agentProfiles.isEmpty ? AgentProfile.builtIn : store.agentProfiles,
    initialProjectID: store.newSessionProjectID,
    parentID: store.newSessionParentID,
    templates: store.availableTemplates(forProjectID: store.newSessionProjectID),
    forkSource: store.forkSourceSession,
    onCreate: { request in
        Task { await store.handleNewSessionRequest(request) }
        store.newSessionProjectID = nil
        store.newSessionParentID = nil
        store.forkSourceSession = nil
    },
    onCreateReview: { request in
        try await store.handleReviewSessionRequest(request)
    }
)
```

- [ ] **Step 5: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/Shared/NewSessionDialog.swift Sources/App/RunwayApp.swift
git commit -m "feat: pre-populate NewSessionDialog for fork sessions"
```

---

### Task 7: Add fork context menu item to sidebar

**Files:**
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift:482-553` (contextMenu)

- [ ] **Step 1: Add "Fork Session" context menu item**

In `Sources/Views/Sidebar/ProjectTreeView.swift`, inside the `.contextMenu` block of `SessionRowView`, add after the "Spawn Sub-session" button (after line 493):

```swift
if session.worktreeBranch != nil {
    Button {
        actions.forkSession(id: session.id)
    } label: {
        Label("Fork Session", systemImage: "arrow.triangle.branch")
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/Sidebar/ProjectTreeView.swift
git commit -m "feat: add Fork Session context menu item for worktree sessions"
```

---

### Task 8: Add Happy and fork indicators to sidebar row

**Files:**
- Modify: `Sources/Views/Sidebar/ProjectTreeView.swift:362-476` (SessionRowView body)

- [ ] **Step 1: Add fork icon next to session title**

In `SessionRowView`, after the title `Text` (line 379), add a fork indicator:

```swift
if session.parentID != nil {
    Image(systemName: "arrow.triangle.branch")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

This goes inside the else branch of the `isRenaming` check, right after the `Text(session.title)` view, within the same `VStack`.

Actually, looking at the layout, the title and fork icon should be in a horizontal grouping. Wrap the title text + fork icon in an `HStack`:

Replace the `Text(session.title)` block (lines 377-379) with:

```swift
HStack(spacing: 4) {
    Text(session.title)
        .font(.system(.body, design: .default))
        .foregroundStyle(.primary)
    if session.parentID != nil {
        Image(systemName: "arrow.triangle.branch")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Add Happy icon next to tool badge**

In the non-hover tool badge area (lines 469-476), add a Happy indicator before the tool badge:

Replace the existing tool badge block:

```swift
if !isHovered && session.tool != .claude {
    Text(session.tool.displayName)
        .font(.caption2)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
}
```

with:

```swift
if !isHovered {
    HStack(spacing: 4) {
        if session.useHappy {
            Image(systemName: "iphone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if session.tool != .claude {
            Text(session.tool.displayName)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(theme.chrome.surface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/Sidebar/ProjectTreeView.swift
git commit -m "feat: add fork and Happy indicators to sidebar session row"
```

---

### Task 9: Add Happy and fork indicators to session header

**Files:**
- Modify: `Sources/Views/SessionDetail/SessionHeaderView.swift:31-147` (body)
- Modify: `Sources/Views/SessionDetail/SessionHeaderView.swift:158-165` (badgeLabel)

- [ ] **Step 1: Add `sessions` and `onSelectSession` parameters to SessionHeaderView**

The header needs access to all sessions to resolve the parent session name for the "Forked from" label. Add parameters:

```swift
public struct SessionHeaderView: View {
    let session: Session
    var linkedPR: PullRequest?
    var prDetail: PRDetail? = nil
    var parentSession: Session? = nil
    var onSelectPR: ((PullRequest) -> Void)?
    var onSelectSession: ((String) -> Void)? = nil
    var changesVisible: Bool = false
    var onToggleChanges: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    public init(
        session: Session,
        linkedPR: PullRequest? = nil,
        prDetail: PRDetail? = nil,
        parentSession: Session? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        onSelectSession: ((String) -> Void)? = nil,
        changesVisible: Bool = false,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.prDetail = prDetail
        self.parentSession = parentSession
        self.onSelectPR = onSelectPR
        self.onSelectSession = onSelectSession
        self.changesVisible = changesVisible
        self.onToggleChanges = onToggleChanges
    }
```

- [ ] **Step 2: Extend the tool badge to include Happy**

Update the `badgeLabel` computed property in the `PermissionMode` extension (line 159):

```swift
fileprivate var badgeLabel: String {
    switch self {
    case .default: "default"
    case .acceptEdits: "accept-edits"
    case .bypassAll: "bypass-all"
    }
}
```

No change needed here — instead, update the badge `Text` in the body (line 51) to insert "happy" when applicable:

Replace:
```swift
Text("\(session.tool.displayName.lowercased()) · \(session.permissionMode.badgeLabel)")
```

with:
```swift
Text(toolBadgeText)
```

And add a computed property:

```swift
private var toolBadgeText: String {
    var parts = [session.tool.displayName.lowercased()]
    if session.useHappy {
        parts.append("happy")
    }
    parts.append(session.permissionMode.badgeLabel)
    return parts.joined(separator: " · ")
}
```

Update the badge foreground/background to use cyan when Happy is active. Replace the badge colors (lines 53-56):

```swift
.foregroundColor(session.useHappy ? theme.chrome.cyan : session.permissionMode.badgeForeground(chrome: theme.chrome))
.padding(.horizontal, 7)
.padding(.vertical, 3)
.background(session.useHappy ? theme.chrome.cyan.opacity(0.15) : session.permissionMode.badgeBackground(chrome: theme.chrome))
```

- [ ] **Step 3: Add "Forked from" line between title row and git row**

In the body, after the Row 1 `HStack` closing brace and before the `if let branch = session.worktreeBranch` block, add:

```swift
// Fork origin label
if let parent = parentSession {
    HStack(spacing: 4) {
        Image(systemName: "arrow.triangle.branch")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("Forked from")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button {
            onSelectSession?(parent.id)
        } label: {
            Text("\"\(parent.title)\"")
                .font(.caption)
                .foregroundStyle(theme.chrome.accent)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Thread parentSession through SessionDetailView**

`SessionDetailView` (`Sources/Views/SessionDetail/SessionDetailView.swift:7-64`) creates `SessionHeaderView` at line 68. Add `parentSession` and `onSelectSession` parameters to `SessionDetailView`:

In the stored properties (after `onSelectPR`):
```swift
var parentSession: Session? = nil
var onSelectSession: ((String) -> Void)? = nil
```

In `init` (after `onSelectPR`):
```swift
parentSession: Session? = nil,
onSelectSession: ((String) -> Void)? = nil,
```

With assignments:
```swift
self.parentSession = parentSession
self.onSelectSession = onSelectSession
```

Update the `SessionHeaderView` call inside `body` (line 68-75):
```swift
SessionHeaderView(
    session: session,
    linkedPR: linkedPR,
    prDetail: prDetail,
    parentSession: parentSession,
    onSelectPR: onSelectPR,
    onSelectSession: onSelectSession,
    changesVisible: changesVisible,
    onToggleChanges: onToggleChanges
)
```

- [ ] **Step 5: Pass parentSession from RunwayApp**

In `Sources/App/RunwayApp.swift:411`, update the `SessionDetailView` instantiation to pass the parent session. Add after the `prDetail` line (line 415):

```swift
parentSession: {
    guard let parentID = session.parentID else { return nil }
    return store.sessions.first(where: { $0.id == parentID })
}(),
onSelectSession: { id in store.selectSession(id) },
```

- [ ] **Step 6: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/Views/SessionDetail/SessionHeaderView.swift Sources/Views/SessionDetail/SessionDetailView.swift Sources/App/RunwayApp.swift
git commit -m "feat: add Happy badge and fork origin label to session header"
```

---

### Task 10: Update existing test for JSON decoding without resumeArguments

**Files:**
- Modify: `Tests/ModelsTests/AgentProfileTests.swift:89-112`

- [ ] **Step 1: Verify existing JSON decoding test still works**

The existing `agentProfileJSONDecoding` test (line 89) uses JSON without `resumeArguments`. Since the init default is `[]`, this should still pass. Verify:

Run: `swift test --filter agentProfileJSONDecoding 2>&1 | tail -10`
Expected: Test passes (the `Codable` synthesis uses the init default for missing keys).

- [ ] **Step 2: Check if Codable handles missing keys**

Swift's `Codable` auto-synthesis does NOT skip missing keys — it requires all keys to be present in JSON. Since `AgentProfile` uses auto-synthesized `Codable`, we need a custom `init(from:)` that defaults missing `resumeArguments` to `[]`.

Add a custom `Decodable` conformance. In `Sources/Models/AgentProfile.swift`, add after the existing `init`:

```swift
enum CodingKeys: String, CodingKey {
    case id, name, command, arguments, runningPatterns, waitingPatterns
    case idlePatterns, lineStartIdlePatterns, spinnerChars, resumeArguments
    case hookEnabled, icon
}

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    command = try container.decode(String.self, forKey: .command)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    runningPatterns = try container.decodeIfPresent([String].self, forKey: .runningPatterns) ?? []
    waitingPatterns = try container.decodeIfPresent([String].self, forKey: .waitingPatterns) ?? []
    idlePatterns = try container.decodeIfPresent([String].self, forKey: .idlePatterns) ?? []
    lineStartIdlePatterns = try container.decodeIfPresent([String].self, forKey: .lineStartIdlePatterns) ?? []
    spinnerChars = try container.decodeIfPresent([String].self, forKey: .spinnerChars) ?? []
    resumeArguments = try container.decodeIfPresent([String].self, forKey: .resumeArguments) ?? []
    hookEnabled = try container.decodeIfPresent(Bool.self, forKey: .hookEnabled) ?? false
    icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "terminal.fill"
}
```

- [ ] **Step 3: Run all AgentProfile tests**

Run: `swift test --filter AgentProfileTests 2>&1 | tail -20`
Expected: All tests pass, including both JSON tests (with and without `resumeArguments`).

- [ ] **Step 4: Commit**

```bash
git add Sources/Models/AgentProfile.swift Tests/ModelsTests/AgentProfileTests.swift
git commit -m "fix: add custom Decodable for AgentProfile to handle missing resumeArguments"
```

---

### Task 11: Final integration test

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All 266+ tests pass.

- [ ] **Step 2: Run full build**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds with no warnings related to our changes.

- [ ] **Step 3: Commit any remaining fixes if needed**

If any tests fail, fix and commit. Otherwise, this task is a verification-only step.
