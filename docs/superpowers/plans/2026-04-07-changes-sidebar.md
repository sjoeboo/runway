# Changes Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible right sidebar to the session detail view showing changed files in a tree with +/- stats, with click-to-view-diff capability.

**Architecture:** New `FileChange` model and tree builder in Models, new git operations in WorktreeManager, two new SwiftUI views (ChangesSidebarView, FileTreeView) in Views, state management in RunwayStore, and a keyboard shortcut in RunwayApp. The sidebar sits inside the detail column using HStack + ResizableDivider.

**Tech Stack:** SwiftUI, Swift Testing, git CLI via ShellRunner

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/Models/FileChange.swift` | FileChange, FileChangeStatus, ChangesMode, FileTreeNode, buildFileTree() |
| Create | `Sources/Views/SessionDetail/ChangesSidebarView.swift` | Sidebar container: header, mode toggle, summary, scrollable FileTreeView |
| Create | `Sources/Views/SessionDetail/FileTreeView.swift` | Recursive tree rendering with disclosure, status badges, +/- counts |
| Create | `Tests/ModelsTests/FileChangeTests.swift` | Unit tests for model, tree builder |
| Create | `Tests/GitOperationsTests/ChangedFilesTests.swift` | Unit + integration tests for parsing and git operations |
| Modify | `Sources/GitOperations/WorktreeManager.swift:106-134` | Add changedFiles(), fileDiff() methods |
| Modify | `Sources/Views/Shared/ResizableDivider.swift` | Add `inverted` parameter for right-side panels |
| Modify | `Sources/Views/SessionDetail/SessionDetailView.swift:24-34` | Wrap body in HStack with ResizableDivider + sidebar; handle DiffView swap |
| Modify | `Sources/Views/SessionDetail/SessionHeaderView.swift:36-43` | Add toggle button before tool badge |
| Modify | `Sources/App/RunwayStore.swift:16-51` | Add changesVisible, changesMode, sessionChanges, viewingDiffFile state |
| Modify | `Sources/App/RunwayApp.swift:49-76` | Add Cmd+3 keyboard shortcut |

---

### Task 1: FileChange Model and Tree Builder

**Files:**
- Create: `Sources/Models/FileChange.swift`
- Create: `Tests/ModelsTests/FileChangeTests.swift`

- [ ] **Step 1: Write failing tests for FileChange model**

In `Tests/ModelsTests/FileChangeTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

// MARK: - FileChange

@Test func fileChangeProperties() {
    let change = FileChange(path: "src/auth/middleware.ts", status: .modified, additions: 45, deletions: 12)
    #expect(change.id == "src/auth/middleware.ts")
    #expect(change.path == "src/auth/middleware.ts")
    #expect(change.status == .modified)
    #expect(change.additions == 45)
    #expect(change.deletions == 12)
}

@Test func fileChangeStatusCases() {
    #expect(FileChangeStatus.added != FileChangeStatus.deleted)
    #expect(FileChangeStatus.modified != FileChangeStatus.renamed)
    let all: [FileChangeStatus] = [.added, .modified, .deleted, .renamed]
    #expect(all.count == 4)
}

// MARK: - ChangesMode

@Test func changesModeHasExpectedCases() {
    let branch = ChangesMode.branch
    let working = ChangesMode.working
    #expect(branch != working)
}

// MARK: - FileTreeNode

@Test func fileTreeNodeFileID() {
    let change = FileChange(path: "README.md", status: .modified, additions: 1, deletions: 0)
    let node = FileTreeNode.file(change)
    #expect(node.id == "README.md")
    #expect(node.name == "README.md")
    #expect(node.additions == 1)
    #expect(node.deletions == 0)
}

@Test func fileTreeNodeDirectoryAggregates() {
    let child1 = FileChange(path: "src/a.ts", status: .modified, additions: 10, deletions: 5)
    let child2 = FileChange(path: "src/b.ts", status: .added, additions: 20, deletions: 0)
    let dir = FileTreeNode.directory(
        name: "src/",
        children: [.file(child1), .file(child2)],
        additions: 30,
        deletions: 5
    )
    #expect(dir.id == "dir:src/")
    #expect(dir.name == "src/")
    #expect(dir.additions == 30)
    #expect(dir.deletions == 5)
}

// MARK: - buildFileTree

@Test func buildFileTreeSingleRootFile() {
    let changes = [FileChange(path: "README.md", status: .modified, additions: 1, deletions: 0)]
    let tree = buildFileTree(changes)
    #expect(tree.count == 1)
    if case .file(let fc) = tree[0] {
        #expect(fc.path == "README.md")
    } else {
        Issue.record("Expected file node")
    }
}

@Test func buildFileTreeGroupsByDirectory() {
    let changes = [
        FileChange(path: "src/auth/middleware.ts", status: .modified, additions: 45, deletions: 12),
        FileChange(path: "src/auth/jwt.ts", status: .added, additions: 38, deletions: 0),
        FileChange(path: "package.json", status: .modified, additions: 2, deletions: 1),
    ]
    let tree = buildFileTree(changes)
    // Should have: dir "src/auth/" with 2 files, and file "package.json"
    #expect(tree.count == 2)

    // Find the directory node
    let dirNode = tree.first { $0.name == "src/auth/" }
    #expect(dirNode != nil)
    if case .directory(_, let children, let adds, let dels) = dirNode {
        #expect(children.count == 2)
        #expect(adds == 83)
        #expect(dels == 12)
    }
}

@Test func buildFileTreeCollapsesSingleChildDirs() {
    // src/deep/nested/file.ts should collapse src/deep/nested/ into one dir
    let changes = [
        FileChange(path: "src/deep/nested/file.ts", status: .added, additions: 10, deletions: 0),
    ]
    let tree = buildFileTree(changes)
    #expect(tree.count == 1)
    if case .directory(let name, let children, _, _) = tree[0] {
        #expect(name == "src/deep/nested/")
        #expect(children.count == 1)
    } else {
        Issue.record("Expected collapsed directory node")
    }
}

@Test func buildFileTreeSortsDirectoriesBeforeFiles() {
    let changes = [
        FileChange(path: "zz-root-file.txt", status: .modified, additions: 1, deletions: 0),
        FileChange(path: "src/file.ts", status: .added, additions: 5, deletions: 0),
    ]
    let tree = buildFileTree(changes)
    #expect(tree.count == 2)
    // Directory should come first
    if case .directory = tree[0] {
        // good
    } else {
        Issue.record("Expected directory first")
    }
}

@Test func buildFileTreeEmpty() {
    let tree = buildFileTree([])
    #expect(tree.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModelsTests.fileChange 2>&1 | head -30`
Expected: Compilation failure — `FileChange`, `FileTreeNode`, `buildFileTree` not defined.

- [ ] **Step 3: Implement FileChange model and tree builder**

Create `Sources/Models/FileChange.swift`:

```swift
import Foundation

// MARK: - FileChange

public struct FileChange: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let status: FileChangeStatus
    public let additions: Int
    public let deletions: Int

    public init(path: String, status: FileChangeStatus, additions: Int, deletions: Int) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
    }
}

public enum FileChangeStatus: String, Sendable, Equatable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"

    public init(gitCode: String) {
        switch gitCode.prefix(1) {
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        default: self = .modified
        }
    }
}

public enum ChangesMode: String, Sendable, Equatable {
    case branch
    case working
}

// MARK: - FileTreeNode

public enum FileTreeNode: Identifiable {
    case directory(name: String, children: [FileTreeNode], additions: Int, deletions: Int)
    case file(FileChange)

    public var id: String {
        switch self {
        case .directory(let name, _, _, _): "dir:\(name)"
        case .file(let fc): fc.path
        }
    }

    public var name: String {
        switch self {
        case .directory(let name, _, _, _): name
        case .file(let fc):
            // Just the filename portion
            if let lastSlash = fc.path.lastIndex(of: "/") {
                return String(fc.path[fc.path.index(after: lastSlash)...])
            }
            return fc.path
        }
    }

    public var additions: Int {
        switch self {
        case .directory(_, _, let a, _): a
        case .file(let fc): fc.additions
        }
    }

    public var deletions: Int {
        switch self {
        case .directory(_, _, _, let d): d
        case .file(let fc): fc.deletions
        }
    }
}

// MARK: - Tree Builder

/// Builds a tree of FileTreeNode from a flat list of FileChange.
/// Groups files by directory, collapses single-child directory chains,
/// and sorts directories before files.
public func buildFileTree(_ changes: [FileChange]) -> [FileTreeNode] {
    guard !changes.isEmpty else { return [] }

    // Group by top-level directory component
    var rootFiles: [FileChange] = []
    var dirGroups: [String: [FileChange]] = [:]

    for change in changes {
        let parts = change.path.split(separator: "/", maxSplits: 1)
        if parts.count == 1 {
            rootFiles.append(change)
        } else {
            let dir = String(parts[0])
            dirGroups[dir, default: []].append(change)
        }
    }

    var nodes: [FileTreeNode] = []

    // Build directory nodes (sorted by name)
    for dir in dirGroups.keys.sorted() {
        let children = dirGroups[dir]!
        // Strip the top-level dir prefix from child paths for recursion
        let stripped = children.map { fc in
            let rest = String(fc.path.drop(while: { $0 != "/" }).dropFirst())
            return FileChange(path: rest, status: fc.status, additions: fc.additions, deletions: fc.deletions)
        }
        let subtree = buildFileTree(stripped)
        let adds = children.reduce(0) { $0 + $1.additions }
        let dels = children.reduce(0) { $0 + $1.deletions }

        // Collapse single-child directory chains
        if subtree.count == 1, case .directory(let childName, let grandchildren, _, _) = subtree[0] {
            nodes.append(.directory(name: "\(dir)/\(childName)", children: grandchildren, additions: adds, deletions: dels))
        } else {
            nodes.append(.directory(name: "\(dir)/", children: subtree, additions: adds, deletions: dels))
        }
    }

    // Add root-level files (sorted by name)
    for file in rootFiles.sorted(by: { $0.path < $1.path }) {
        nodes.append(.file(file))
    }

    return nodes
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelsTests 2>&1 | tail -20`
Expected: All FileChange tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/FileChange.swift Tests/ModelsTests/FileChangeTests.swift
git commit -m "feat: add FileChange model and tree builder"
```

---

### Task 2: WorktreeManager Git Operations

**Files:**
- Modify: `Sources/GitOperations/WorktreeManager.swift:106-134`
- Create: `Tests/GitOperationsTests/ChangedFilesTests.swift`

- [ ] **Step 1: Write failing tests for changedFiles parsing and fileDiff**

Create `Tests/GitOperationsTests/ChangedFilesTests.swift`:

```swift
import Foundation
import Testing

@testable import GitOperations
@testable import Models

// MARK: - parseChangedFiles (unit tests on the parser)

@Test func parseChangedFilesTypicalOutput() {
    // git diff --numstat output
    let numstat = """
    45\t12\tsrc/auth/middleware.ts
    38\t0\tsrc/auth/jwt.ts
    0\t22\tsrc/auth/legacy-auth.ts
    2\t1\tpackage.json
    """
    // git diff --name-status output
    let nameStatus = """
    M\tsrc/auth/middleware.ts
    A\tsrc/auth/jwt.ts
    D\tsrc/auth/legacy-auth.ts
    M\tpackage.json
    """
    let changes = parseChangedFiles(numstat: numstat, nameStatus: nameStatus)
    #expect(changes.count == 4)

    let middleware = changes.first { $0.path == "src/auth/middleware.ts" }
    #expect(middleware?.status == .modified)
    #expect(middleware?.additions == 45)
    #expect(middleware?.deletions == 12)

    let jwt = changes.first { $0.path == "src/auth/jwt.ts" }
    #expect(jwt?.status == .added)
    #expect(jwt?.additions == 38)

    let legacy = changes.first { $0.path == "src/auth/legacy-auth.ts" }
    #expect(legacy?.status == .deleted)
    #expect(legacy?.deletions == 22)
}

@Test func parseChangedFilesEmptyOutput() {
    let changes = parseChangedFiles(numstat: "", nameStatus: "")
    #expect(changes.isEmpty)
}

@Test func parseChangedFilesRenamedFile() {
    let numstat = "10\t5\told-name.ts => new-name.ts"
    let nameStatus = "R100\told-name.ts\tnew-name.ts"
    let changes = parseChangedFiles(numstat: numstat, nameStatus: nameStatus)
    #expect(changes.count == 1)
    // Renamed files use the new path
    #expect(changes[0].status == .renamed)
}

// MARK: - Integration test with temp git repo

private func withTempGitRepo(_ body: (String) async throws -> Void) async throws {
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("runway-git-test-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
    let tmpDir = tmpURL.path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

    let commands = [
        "git init",
        "git config user.email 'test@test.com'",
        "git config user.name 'Test'",
        "echo 'hello' > README.md",
        "git add README.md",
        "git commit -m 'Initial commit'",
    ]
    for cmd in commands {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = URL(fileURLWithPath: tmpDir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    try await body(tmpDir)
}

@Test func changedFilesOnCleanRepo() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let changes = await manager.changedFiles(path: repoPath, mode: .working)
        #expect(changes.isEmpty)
    }
}

@Test func changedFilesDetectsNewFile() async throws {
    try await withTempGitRepo { repoPath in
        // Create a new uncommitted file
        let filePath = "\(repoPath)/new-file.txt"
        try "new content".write(toFile: filePath, atomically: true, encoding: .utf8)

        // Stage it so git diff HEAD picks it up
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "git add new-file.txt"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let manager = WorktreeManager()
        let changes = await manager.changedFiles(path: repoPath, mode: .working)
        #expect(changes.count == 1)
        #expect(changes[0].path == "new-file.txt")
        #expect(changes[0].status == .added)
        #expect(changes[0].additions == 1)
    }
}

@Test func fileDiffReturnsUnifiedDiff() async throws {
    try await withTempGitRepo { repoPath in
        // Modify README.md
        try "updated content\n".write(toFile: "\(repoPath)/README.md", atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "git add README.md"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let manager = WorktreeManager()
        let diff = await manager.fileDiff(path: repoPath, file: "README.md", mode: .working)
        #expect(diff != nil)
        #expect(diff?.contains("updated content") == true)
        #expect(diff?.contains("@@") == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitOperationsTests.parseChangedFiles 2>&1 | head -20`
Expected: Compilation failure — `parseChangedFiles`, `changedFiles`, `fileDiff` not defined.

- [ ] **Step 3: Implement changedFiles and fileDiff in WorktreeManager**

In `Sources/GitOperations/WorktreeManager.swift`, add after the `diffSummary` method (after line 111) and before `detectDefaultBranch`:

```swift
    /// Get per-file changes in the working directory or on the branch.
    ///
    /// - Parameters:
    ///   - path: Worktree directory path
    ///   - mode: `.working` for uncommitted changes, `.branch` for all branch changes
    /// - Returns: Array of FileChange with per-file stats and status
    public func changedFiles(path: String, mode: ChangesMode) async -> [FileChange] {
        let diffArgs: [String]
        switch mode {
        case .working:
            diffArgs = ["diff", "--numstat", "HEAD"]
        case .branch:
            let base = await detectDefaultBranch(repoPath: path)
            // Use merge-base to find the fork point
            let mergeBase = try? await runGit(in: path, args: ["merge-base", base, "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let mergeBase, !mergeBase.isEmpty {
                diffArgs = ["diff", "--numstat", mergeBase]
            } else {
                diffArgs = ["diff", "--numstat", "HEAD"]
            }
        }

        guard let numstat = try? await runGit(in: path, args: diffArgs) else { return [] }

        // Get name-status with same args (swap --numstat for --name-status)
        var statusArgs = diffArgs
        statusArgs[statusArgs.firstIndex(of: "--numstat")!] = "--name-status"
        let nameStatus = (try? await runGit(in: path, args: statusArgs)) ?? ""

        return parseChangedFiles(numstat: numstat, nameStatus: nameStatus)
    }

    /// Get the unified diff for a single file.
    public func fileDiff(path: String, file: String, mode: ChangesMode) async -> String? {
        let diffArgs: [String]
        switch mode {
        case .working:
            diffArgs = ["diff", "HEAD", "--", file]
        case .branch:
            let base = await detectDefaultBranch(repoPath: path)
            let mergeBase = try? await runGit(in: path, args: ["merge-base", base, "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let mergeBase, !mergeBase.isEmpty {
                diffArgs = ["diff", mergeBase, "--", file]
            } else {
                diffArgs = ["diff", "HEAD", "--", file]
            }
        }

        return try? await runGit(in: path, args: diffArgs)
    }
```

Also add the standalone parsing function after the `WorktreeManager` class closing brace (public so tests can access it):

```swift
// MARK: - Parsing

/// Parse git diff --numstat and --name-status output into FileChange array.
public func parseChangedFiles(numstat: String, nameStatus: String) -> [FileChange] {
    // Build status map from --name-status
    var statusMap: [String: FileChangeStatus] = [:]
    var renameMap: [String: String] = [:]  // old -> new for renames
    for line in nameStatus.components(separatedBy: "\n") where !line.isEmpty {
        let parts = line.split(separator: "\t", maxSplits: 2)
        guard parts.count >= 2 else { continue }
        let code = String(parts[0])
        let status = FileChangeStatus(gitCode: code)
        if status == .renamed, parts.count >= 3 {
            let newPath = String(parts[2])
            statusMap[newPath] = status
            renameMap[String(parts[1])] = newPath
        } else {
            statusMap[String(parts[1])] = status
        }
    }

    // Parse --numstat for addition/deletion counts
    var changes: [FileChange] = []
    for line in numstat.components(separatedBy: "\n") where !line.isEmpty {
        let parts = line.split(separator: "\t", maxSplits: 2)
        guard parts.count >= 3 else { continue }
        let adds = Int(parts[0]) ?? 0
        let dels = Int(parts[1]) ?? 0
        var path = String(parts[2])

        // Handle rename format: "old => new" or "{old => new}/rest"
        if path.contains(" => ") {
            if let arrow = path.range(of: " => ") {
                path = String(path[arrow.upperBound...])
            }
        }

        let status = statusMap[path] ?? .modified
        changes.append(FileChange(path: path, status: status, additions: adds, deletions: dels))
    }

    return changes
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitOperationsTests 2>&1 | tail -20`
Expected: All tests PASS including new ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitOperations/WorktreeManager.swift Tests/GitOperationsTests/ChangedFilesTests.swift
git commit -m "feat: add changedFiles and fileDiff to WorktreeManager"
```

---

### Task 3: ChangesSidebarView and FileTreeView

**Files:**
- Create: `Sources/Views/SessionDetail/ChangesSidebarView.swift`
- Create: `Sources/Views/SessionDetail/FileTreeView.swift`

- [ ] **Step 1: Create FileTreeView — recursive tree rendering**

Create `Sources/Views/SessionDetail/FileTreeView.swift`:

```swift
import Models
import SwiftUI
import Theme

/// Renders a tree of FileTreeNode with collapsible directories and file selection.
struct FileTreeView: View {
    let nodes: [FileTreeNode]
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(nodes) { node in
                nodeRow(node)
            }
        }
    }

    @ViewBuilder
    private func nodeRow(_ node: FileTreeNode) -> some View {
        switch node {
        case .directory(let name, let children, _, let dels):
            DirectoryRow(
                name: name,
                children: children,
                additions: node.additions,
                deletions: dels,
                selectedPath: selectedPath,
                onSelectFile: onSelectFile
            )
        case .file(let fc):
            FileRow(
                change: fc,
                isSelected: fc.path == selectedPath,
                onSelect: { onSelectFile(fc) }
            )
        }
    }
}

// MARK: - DirectoryRow

private struct DirectoryRow: View {
    let name: String
    let children: [FileTreeNode]
    let additions: Int
    let deletions: Int
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @State private var isExpanded = true
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(theme.chrome.textDim)
                        .frame(width: 12)
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                        .foregroundColor(theme.chrome.accent)
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(theme.chrome.textDim)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(children) { child in
                    Group {
                        switch child {
                        case .directory(let childName, let grandchildren, let a, let d):
                            DirectoryRow(
                                name: childName,
                                children: grandchildren,
                                additions: a,
                                deletions: d,
                                selectedPath: selectedPath,
                                onSelectFile: onSelectFile
                            )
                        case .file(let fc):
                            FileRow(
                                change: fc,
                                isSelected: fc.path == selectedPath,
                                onSelect: { onSelectFile(fc) }
                            )
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - FileRow

private struct FileRow: View {
    let change: FileChange
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(change.status.rawValue)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(statusColor)
                    .frame(width: 14)

                Text(filename)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(change.status == .deleted ? theme.chrome.textDim : theme.chrome.text)
                    .strikethrough(change.status == .deleted)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 3) {
                    if change.additions > 0 {
                        Text("+\(change.additions)")
                            .foregroundColor(theme.chrome.green)
                    }
                    if change.deletions > 0 {
                        Text("-\(change.deletions)")
                            .foregroundColor(theme.chrome.red)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(isSelected ? theme.chrome.accent.opacity(0.15) : .clear)
            .cornerRadius(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filename: String {
        if let lastSlash = change.path.lastIndex(of: "/") {
            return String(change.path[change.path.index(after: lastSlash)...])
        }
        return change.path
    }

    private var statusColor: Color {
        switch change.status {
        case .added: theme.chrome.green
        case .modified: theme.chrome.orange
        case .deleted: theme.chrome.red
        case .renamed: theme.chrome.cyan
        }
    }
}
```

- [ ] **Step 2: Create ChangesSidebarView — sidebar container**

Create `Sources/Views/SessionDetail/ChangesSidebarView.swift`:

```swift
import Models
import SwiftUI
import Theme

/// Right sidebar showing changed files in the session's worktree.
struct ChangesSidebarView: View {
    let changes: [FileChange]
    @Binding var mode: ChangesMode
    let selectedPath: String?
    let onSelectFile: (FileChange) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            fileTree
        }
        .background(theme.chrome.surface.opacity(0.3))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Changes")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(theme.chrome.text)

            Spacer()

            Picker("", selection: $mode) {
                Text("Branch").tag(ChangesMode.branch)
                Text("Working").tag(ChangesMode.working)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 6) {
            Text("\(changes.count) file\(changes.count == 1 ? "" : "s")")
            Text("+\(totalAdditions)")
                .foregroundColor(theme.chrome.green)
            Text("-\(totalDeletions)")
                .foregroundColor(theme.chrome.red)
        }
        .font(.caption)
        .foregroundColor(theme.chrome.textDim)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - File Tree

    private var fileTree: some View {
        ScrollView {
            FileTreeView(
                nodes: buildFileTree(changes),
                selectedPath: selectedPath,
                onSelectFile: onSelectFile
            )
            .padding(.vertical, 4)
        }
    }

    private var totalAdditions: Int { changes.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { changes.reduce(0) { $0 + $1.deletions } }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED (views compile without runtime tests needed).

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/SessionDetail/ChangesSidebarView.swift Sources/Views/SessionDetail/FileTreeView.swift
git commit -m "feat: add ChangesSidebarView and FileTreeView"
```

---

### Task 4: SessionDetailView Layout Changes

**Files:**
- Modify: `Sources/Views/SessionDetail/SessionDetailView.swift`
- Modify: `Sources/Views/Shared/ResizableDivider.swift`

- [ ] **Step 0: Add `inverted` parameter to ResizableDivider**

The existing `ResizableDivider` uses `dragStart + value.translation.width` which works for left panels. For the right sidebar, dragging left should increase width, so we need to subtract. Add an `inverted` parameter.

In `Sources/Views/Shared/ResizableDivider.swift`, add a property and update the gesture:

```swift
struct ResizableDivider: View {
    @Binding var width: Double
    var minWidth: Double = 200
    var maxWidth: Double = 600
    var inverted: Bool = false

    @State private var isDragging = false
    @State private var dragStart: Double = 0
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : theme.chrome.border)
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStart = width
                        }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let new = dragStart + delta
                        width = min(max(new, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}
```

The existing left-sidebar call site passes no `inverted:` and gets `false` by default — no change needed there.

- [ ] **Step 1: Update SessionDetailView to support changes sidebar and diff viewing**

The current body (lines 24-34) is a simple VStack. Replace it with an HStack containing the terminal area + ResizableDivider + ChangesSidebarView, with a conditional DiffView swap.

Replace the entire `body` property in `Sources/Views/SessionDetail/SessionDetailView.swift`:

```swift
public struct SessionDetailView: View {
    let session: Session
    var linkedPR: PullRequest?
    var onSelectPR: ((PullRequest) -> Void)?
    @Binding var showSendBar: Bool
    @Binding var showTerminalSearch: Bool
    @Binding var changesVisible: Bool
    @Binding var changesMode: ChangesMode
    let changes: [FileChange]
    var viewingDiffFile: FileChange?
    var diffPatch: String?
    var onSelectDiffFile: ((FileChange) -> Void)?
    var onDismissDiff: (() -> Void)?
    var onToggleChanges: (() -> Void)?
    @AppStorage("changesSidebarWidth") private var sidebarWidth: Double = 260

    public init(
        session: Session,
        linkedPR: PullRequest? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        showSendBar: Binding<Bool>,
        showTerminalSearch: Binding<Bool>,
        changesVisible: Binding<Bool>,
        changesMode: Binding<ChangesMode>,
        changes: [FileChange] = [],
        viewingDiffFile: FileChange? = nil,
        diffPatch: String? = nil,
        onSelectDiffFile: ((FileChange) -> Void)? = nil,
        onDismissDiff: (() -> Void)? = nil,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.onSelectPR = onSelectPR
        self._showSendBar = showSendBar
        self._showTerminalSearch = showTerminalSearch
        self._changesVisible = changesVisible
        self._changesMode = changesMode
        self.changes = changes
        self.viewingDiffFile = viewingDiffFile
        self.diffPatch = diffPatch
        self.onSelectDiffFile = onSelectDiffFile
        self.onDismissDiff = onDismissDiff
        self.onToggleChanges = onToggleChanges
    }

    public var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(
                session: session,
                linkedPR: linkedPR,
                onSelectPR: onSelectPR,
                changesVisible: changesVisible,
                onToggleChanges: onToggleChanges
            )
            HStack(spacing: 0) {
                // Main content: terminal or diff view
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if changesVisible {
                    ResizableDivider(width: $sidebarWidth, minWidth: 200, maxWidth: 400, inverted: true)
                    ChangesSidebarView(
                        changes: changes,
                        mode: $changesMode,
                        selectedPath: viewingDiffFile?.path,
                        onSelectFile: { file in onSelectDiffFile?(file) }
                    )
                    .frame(width: CGFloat(sidebarWidth))
                }
            }
            SendTextBar(isVisible: $showSendBar) { text in
                if let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) {
                    terminal.send(txt: text + "\r")
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let diffPatch, viewingDiffFile != nil {
            VStack(spacing: 0) {
                // Back button bar
                HStack {
                    Button(action: { onDismissDiff?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back to terminal")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.chrome.surface.opacity(0.3))

                DiffView(patch: diffPatch)
            }
        } else {
            TerminalTabView(session: session, showSearch: $showTerminalSearch)
        }
    }
}
```

Note: The struct must include `@Environment(\.theme) private var theme` as a property so `mainContent` can access it.

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -15`
Expected: Compilation errors in `RunwayApp.swift` where `SessionDetailView` is instantiated (missing new parameters). This is expected — we'll fix the call site in Task 6.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/SessionDetail/SessionDetailView.swift
git commit -m "feat: update SessionDetailView with changes sidebar layout"
```

---

### Task 5: SessionHeaderView Toggle Button

**Files:**
- Modify: `Sources/Views/SessionDetail/SessionHeaderView.swift:6-44`

- [ ] **Step 1: Add toggle button and new parameters to SessionHeaderView**

Add `changesVisible` and `onToggleChanges` parameters to `SessionHeaderView`, and add a toggle button in row 1 before the tool badge.

In `Sources/Views/SessionDetail/SessionHeaderView.swift`, update the struct:

```swift
public struct SessionHeaderView: View {
    let session: Session
    var linkedPR: PullRequest?
    var onSelectPR: ((PullRequest) -> Void)?
    var changesVisible: Bool = false
    var onToggleChanges: (() -> Void)?
    @Environment(\.theme) private var theme

    public init(
        session: Session,
        linkedPR: PullRequest? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        changesVisible: Bool = false,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.onSelectPR = onSelectPR
        self.changesVisible = changesVisible
        self.onToggleChanges = onToggleChanges
    }
```

Then in the body, insert the toggle button in Row 1 between `Spacer()` and the tool badge. Replace the `Spacer()` + tool badge block (lines 34-43):

```swift
                    Spacer()

                    HStack(spacing: 8) {
                        // Changes sidebar toggle
                        if onToggleChanges != nil {
                            Button(action: { onToggleChanges?() }) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.caption)
                                    .foregroundColor(changesVisible ? theme.chrome.accent : theme.chrome.textDim)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle changes sidebar (⌘3)")
                        }

                        // Tool + permission mode badge
                        Text("\(session.tool.displayName.lowercased()) · \(session.permissionMode.badgeLabel)")
                            .font(.caption)
                            .foregroundColor(session.permissionMode.badgeForeground(chrome: theme.chrome))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(session.permissionMode.badgeBackground(chrome: theme.chrome))
                            .clipShape(Capsule())
                    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: May have compilation issues from call sites — expected, will be resolved in Task 6.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/SessionDetail/SessionHeaderView.swift
git commit -m "feat: add changes sidebar toggle button to session header"
```

---

### Task 6: RunwayStore State and Refresh Logic

**Files:**
- Modify: `Sources/App/RunwayStore.swift`

- [ ] **Step 1: Add state properties to RunwayStore**

In `Sources/App/RunwayStore.swift`, add after the existing state properties (around line 51, after `isResolvingPR`):

```swift
    // MARK: - Changes Sidebar
    var changesVisible: Bool = false
    var changesMode: ChangesMode = .branch
    var sessionChanges: [String: [FileChange]] = [:]
    var viewingDiffFile: FileChange? = nil
    var viewingDiffPatch: String? = nil
    private var changesRefreshTask: Task<Void, Never>?
```

- [ ] **Step 2: Add changes sidebar methods to RunwayStore**

Add these methods to the RunwayStore class (in an extension or inline, following the existing pattern):

```swift
    // MARK: - Changes Sidebar Actions

    func toggleChangesSidebar() {
        changesVisible.toggle()
        if changesVisible {
            // Dismiss diff view when re-opening
            viewingDiffFile = nil
            viewingDiffPatch = nil
            startChangesRefresh()
        } else {
            stopChangesRefresh()
            viewingDiffFile = nil
            viewingDiffPatch = nil
        }
    }

    func selectDiffFile(_ file: FileChange) {
        guard let sessionID = selectedSessionID,
              let session = sessions.first(where: { $0.id == sessionID })
        else { return }

        viewingDiffFile = file
        Task {
            let patch = await worktreeManager.fileDiff(
                path: session.path,
                file: file.path,
                mode: changesMode
            )
            viewingDiffPatch = patch
        }
    }

    func dismissDiffView() {
        viewingDiffFile = nil
        viewingDiffPatch = nil
    }

    func fetchChangesForCurrentSession() {
        guard let sessionID = selectedSessionID,
              let session = sessions.first(where: { $0.id == sessionID })
        else { return }

        Task {
            let changes = await worktreeManager.changedFiles(
                path: session.path,
                mode: changesMode
            )
            sessionChanges[sessionID] = changes
        }
    }

    private func startChangesRefresh() {
        stopChangesRefresh()
        fetchChangesForCurrentSession()
        changesRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, changesVisible else { break }
                fetchChangesForCurrentSession()
            }
        }
    }

    private func stopChangesRefresh() {
        changesRefreshTask?.cancel()
        changesRefreshTask = nil
    }
```

- [ ] **Step 3: Update the SessionDetailView call site in ContentView**

In `Sources/App/RunwayApp.swift`, update the `SessionDetailView` instantiation in `detailContent` (around line 371) to pass the new parameters:

```swift
                SessionDetailView(
                    session: session,
                    linkedPR: store.sessionPRs[sessionID],
                    onSelectPR: { pr in Task { await store.selectPR(pr) } },
                    showSendBar: Binding(
                        get: { store.showSendBar },
                        set: { store.showSendBar = $0 }
                    ),
                    showTerminalSearch: Binding(
                        get: { store.showTerminalSearch },
                        set: { store.showTerminalSearch = $0 }
                    ),
                    changesVisible: Binding(
                        get: { store.changesVisible },
                        set: { store.changesVisible = $0 }
                    ),
                    changesMode: Binding(
                        get: { store.changesMode },
                        set: { newMode in
                            store.changesMode = newMode
                            store.fetchChangesForCurrentSession()
                        }
                    ),
                    changes: store.sessionChanges[sessionID] ?? [],
                    viewingDiffFile: store.viewingDiffFile,
                    diffPatch: store.viewingDiffPatch,
                    onSelectDiffFile: { file in store.selectDiffFile(file) },
                    onDismissDiff: { store.dismissDiffView() },
                    onToggleChanges: { store.toggleChangesSidebar() }
                )
```

- [ ] **Step 4: Add changesMode reset when session changes**

In the existing `onChange(of: store.selectedSessionID)` handler in `ContentView.detail` (around line 313), add cleanup:

```swift
            .onChange(of: store.selectedSessionID) { _, newValue in
                if newValue != nil {
                    store.selectedProjectID = nil
                }
                // Reset diff view when switching sessions
                store.viewingDiffFile = nil
                store.viewingDiffPatch = nil
                // Refresh changes if sidebar is open
                if store.changesVisible {
                    store.fetchChangesForCurrentSession()
                }
            }
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build 2>&1 | tail -15`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/RunwayStore.swift Sources/App/RunwayApp.swift
git commit -m "feat: add changes sidebar state management and refresh logic"
```

---

### Task 7: Keyboard Shortcut

**Files:**
- Modify: `Sources/App/RunwayApp.swift:49-54`

- [ ] **Step 1: Add Cmd+3 keyboard shortcut**

In `Sources/App/RunwayApp.swift`, add a new button in the `CommandGroup(after: .sidebar)` block (after line 53):

```swift
            CommandGroup(after: .sidebar) {
                Button("Sessions") { store.currentView = .sessions }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Pull Requests") { store.currentView = .prs }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Toggle Changes") { store.toggleChangesSidebar() }
                    .keyboardShortcut("3", modifiers: .command)
            }
```

- [ ] **Step 2: Build and run quick smoke test**

Run: `swift build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests PASS (existing + new).

- [ ] **Step 4: Commit**

```bash
git add Sources/App/RunwayApp.swift
git commit -m "feat: add Cmd+3 keyboard shortcut for changes sidebar"
```

---

### Task 8: Final Integration Verification

- [ ] **Step 1: Run full build**

Run: `swift build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED with no warnings related to new code.

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS.

- [ ] **Step 3: Review all changes**

Run: `git diff main...HEAD --stat`
Verify the expected files are changed and no unexpected files snuck in.

- [ ] **Step 4: Final commit if any cleanup needed**

Only if adjustments were needed during integration verification.
