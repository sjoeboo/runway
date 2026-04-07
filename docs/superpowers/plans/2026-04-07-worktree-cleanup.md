# Orphaned Worktree Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect and remove orphaned git worktrees on startup, mirroring the existing tmux orphan cleanup pattern.

**Architecture:** Two new methods on `WorktreeManager` (`pruneWorktrees`, `isBranchMerged`) and one new method on `RunwayStore` (`cleanOrphanedWorktrees`) called from `loadState()`. Merged branches are deleted; unmerged branches are preserved. A status message reports results.

**Tech Stack:** Swift, git CLI, Swift Testing framework

---

### Task 1: Add `pruneWorktrees()` to WorktreeManager

**Files:**
- Modify: `Sources/GitOperations/WorktreeManager.swift:84-97` (insert before `removeWorktree`)
- Test: `Tests/GitOperationsTests/WorktreeManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/GitOperationsTests/WorktreeManagerTests.swift` at the end of the file:

```swift
@Test func pruneWorktreesOnCleanRepo() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        // Should not throw on a clean repo with nothing to prune
        try await manager.pruneWorktrees(repoPath: repoPath)
        let worktrees = try await manager.listWorktrees(repoPath: repoPath)
        #expect(worktrees.count == 1)
    }
}

@Test func pruneWorktreesRemovesStaleLockfile() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let worktreePath = try await manager.createWorktree(
            repoPath: repoPath,
            branchName: "stale-wt",
            baseBranch: currentBranch
        )

        // Simulate a manually-deleted worktree (directory gone, git ref remains)
        try FileManager.default.removeItem(atPath: worktreePath)

        // Before prune: git still knows about the worktree
        let before = try await manager.listWorktrees(repoPath: repoPath)
        #expect(before.count == 2)

        // Prune cleans up the stale reference
        try await manager.pruneWorktrees(repoPath: repoPath)

        let after = try await manager.listWorktrees(repoPath: repoPath)
        #expect(after.count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter pruneWorktrees 2>&1 | tail -20`
Expected: Compilation error — `pruneWorktrees` does not exist on `WorktreeManager`.

- [ ] **Step 3: Implement `pruneWorktrees()`**

In `Sources/GitOperations/WorktreeManager.swift`, add after the `listWorktrees` method (after line 82):

```swift
/// Prune stale worktree references (e.g., directories that were manually deleted).
public func pruneWorktrees(repoPath: String) async throws {
    try await runGit(in: repoPath, args: ["worktree", "prune"])
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter pruneWorktrees 2>&1 | tail -20`
Expected: Both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitOperations/WorktreeManager.swift Tests/GitOperationsTests/WorktreeManagerTests.swift
git commit -m "feat: add pruneWorktrees() to WorktreeManager"
```

---

### Task 2: Add `isBranchMerged()` to WorktreeManager

**Files:**
- Modify: `Sources/GitOperations/WorktreeManager.swift` (insert after `pruneWorktrees`)
- Test: `Tests/GitOperationsTests/WorktreeManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/GitOperationsTests/WorktreeManagerTests.swift`:

```swift
@Test func isBranchMergedReturnsTrueForMergedBranch() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        // Create a branch at the same commit (already "merged")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "git branch already-merged"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let merged = try await manager.isBranchMerged(
            repoPath: repoPath, branch: "already-merged", into: currentBranch
        )
        #expect(merged == true)
    }
}

@Test func isBranchMergedReturnsFalseForUnmergedBranch() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        // Create a branch with an extra commit (not merged into current)
        let commands = [
            "git checkout -b unmerged-feature",
            "echo 'new' > feature.txt",
            "git add feature.txt",
            "git commit -m 'feature commit'",
            "git checkout \(currentBranch)",
        ]
        for cmd in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", cmd]
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }

        let merged = try await manager.isBranchMerged(
            repoPath: repoPath, branch: "unmerged-feature", into: currentBranch
        )
        #expect(merged == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter isBranchMerged 2>&1 | tail -20`
Expected: Compilation error — `isBranchMerged` does not exist.

- [ ] **Step 3: Implement `isBranchMerged()`**

In `Sources/GitOperations/WorktreeManager.swift`, add after `pruneWorktrees`:

```swift
/// Check whether a branch has been fully merged into a target branch.
public func isBranchMerged(repoPath: String, branch: String, into target: String) async throws -> Bool {
    let output = try await runGit(in: repoPath, args: ["branch", "--merged", target])
    return output.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }
        .contains(branch)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter isBranchMerged 2>&1 | tail -20`
Expected: Both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitOperations/WorktreeManager.swift Tests/GitOperationsTests/WorktreeManagerTests.swift
git commit -m "feat: add isBranchMerged() to WorktreeManager"
```

---

### Task 3: Add `cleanOrphanedWorktrees()` to RunwayStore

**Files:**
- Modify: `Sources/App/RunwayStore.swift` (add method + call site in `loadState()`)

- [ ] **Step 1: Add the `cleanOrphanedWorktrees()` method**

In `Sources/App/RunwayStore.swift`, add a new method after the `loadState()` method (after line 208):

```swift
/// Remove worktrees that exist on disk but have no matching session in the database.
/// Mirrors the tmux orphan cleanup in `loadState()`. Branches are only deleted
/// if they have been fully merged into the project's default branch.
private func cleanOrphanedWorktrees() async {
    // Collect all worktree paths owned by existing sessions
    let ownedPaths = Set(
        sessions
            .filter { $0.worktreeBranch != nil }
            .map { $0.path }
    )

    var removedCount = 0
    var preservedBranches = 0

    for project in projects {
        // Prune stale git references first (e.g., manually-deleted directories)
        try? await worktreeManager.pruneWorktrees(repoPath: project.path)

        guard let worktrees = try? await worktreeManager.listWorktrees(repoPath: project.path) else {
            continue
        }

        let worktreePrefix = "\(project.path)/.worktrees/"
        let orphans = worktrees.filter { wt in
            let resolvedPath = URL(fileURLWithPath: wt.path).resolvingSymlinksInPath().path
            let isManaged = resolvedPath.hasPrefix(worktreePrefix)
                || wt.path.hasPrefix(worktreePrefix)
            let isOwned = ownedPaths.contains(wt.path)
                || ownedPaths.contains(resolvedPath)
            return isManaged && !isOwned
        }

        for orphan in orphans {
            let branchName = URL(fileURLWithPath: orphan.path).lastPathComponent
            let merged = (try? await worktreeManager.isBranchMerged(
                repoPath: project.path, branch: branchName, into: project.defaultBranch
            )) ?? false

            do {
                try await worktreeManager.removeWorktree(
                    repoPath: project.path,
                    worktreePath: orphan.path,
                    deleteBranch: merged
                )
                removedCount += 1
                if !merged { preservedBranches += 1 }
            } catch {
                print("[Runway] Failed to remove orphaned worktree \(orphan.path): \(error)")
            }
        }
    }

    if removedCount > 0 {
        let message: String
        if preservedBranches > 0 {
            message = "Cleaned up \(removedCount) orphaned worktree\(removedCount == 1 ? "" : "s") (\(preservedBranches) branch\(preservedBranches == 1 ? "" : "es") preserved \u{2014} unmerged)"
        } else {
            message = "Cleaned up \(removedCount) orphaned worktree\(removedCount == 1 ? "" : "s")"
        }
        statusMessage = .info(message)
    }
}
```

- [ ] **Step 2: Call from `loadState()`**

In `Sources/App/RunwayStore.swift`, after line 199 (end of tmux orphan cleanup, inside the `if tmuxAvailable` closure's closing brace), add:

```swift
// Clean up orphaned worktrees (exist on disk but not in DB)
await cleanOrphanedWorktrees()
```

This goes at line 200, just before the `} catch {` block on the existing line 201, but **outside** the `if tmuxAvailable` block — worktree cleanup should run regardless of tmux availability.

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 4: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: clean orphaned worktrees on startup

Detects worktrees under .worktrees/ that have no matching session in
the database and removes them. Branches are only deleted if fully
merged into the project's default branch. Runs git worktree prune
first to clear stale references. Shows an info status message with
the cleanup count."
```
