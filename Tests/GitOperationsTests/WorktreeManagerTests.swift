import Foundation
import Testing

@testable import GitOperations

// MARK: - WorktreeInfo

@Test func worktreeInfoProperties() {
    let info = WorktreeInfo(path: "/code/project/.worktrees/feature", branch: "feature", isBare: false)
    #expect(info.path == "/code/project/.worktrees/feature")
    #expect(info.branch == "feature")
    #expect(info.isBare == false)
}

// MARK: - DiffSummary

@Test func diffSummaryProperties() {
    let summary = DiffSummary(files: 3, additions: 42, deletions: 10)
    #expect(summary.files == 3)
    #expect(summary.additions == 42)
    #expect(summary.deletions == 10)
}

// MARK: - GitError

@Test func gitErrorDescription() {
    let error = GitError.commandFailed(args: ["worktree", "add"], exitCode: 128, stderr: "branch already exists")
    #expect(error.errorDescription?.contains("worktree add") == true)
    #expect(error.errorDescription?.contains("exit 128") == true)
    #expect(error.errorDescription?.contains("branch already exists") == true)
}

// MARK: - Integration Tests (temp git repo)

/// Creates a temporary git repository for testing.
/// Resolves symlinks to avoid /var vs /private/var mismatches on macOS.
private func withTempGitRepo(_ body: (String) async throws -> Void) async throws {
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("runway-git-test-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
    let tmpDir = tmpURL.path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

    // Initialize a git repo with an initial commit
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

@Test func listWorktreesOnFreshRepo() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let worktrees = try await manager.listWorktrees(repoPath: repoPath)
        // Fresh repo should have exactly 1 worktree (the main one)
        #expect(worktrees.count == 1)
        // Resolve symlinks on both sides for macOS /var → /private/var
        let expected = URL(fileURLWithPath: repoPath).resolvingSymlinksInPath().path
        let actual = URL(fileURLWithPath: worktrees.first?.path ?? "").resolvingSymlinksInPath().path
        #expect(actual == expected)
    }
}

@Test func currentBranchDetection() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let branch = await manager.currentBranch(path: repoPath)
        // Default branch in `git init` (depends on git config, usually main or master)
        let branchName = try #require(branch)
        #expect(!branchName.isEmpty)
    }
}

@Test func detectDefaultBranch() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let defaultBranch = await manager.detectDefaultBranch(repoPath: repoPath)
        // No remote, so it falls back to checking local branches
        #expect(!defaultBranch.isEmpty)
    }
}

@Test func createAndListWorktree() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()

        // Detect actual branch name
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        // Create worktree directory
        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let (worktreePath, _) = try await manager.createWorktree(
            repoPath: repoPath,
            branchName: "test-feature",
            baseBranch: currentBranch
        )

        #expect(FileManager.default.fileExists(atPath: worktreePath))

        let worktrees = try await manager.listWorktrees(repoPath: repoPath)
        #expect(worktrees.count == 2)

        // Verify the new worktree has the right branch (resolve symlinks for comparison)
        let resolvedWorktreePath = URL(fileURLWithPath: worktreePath).resolvingSymlinksInPath().path
        let newWorktree = worktrees.first { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == resolvedWorktreePath }
        #expect(newWorktree?.branch == "test-feature")
    }
}

@Test func removeWorktree() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let (worktreePath, _) = try await manager.createWorktree(
            repoPath: repoPath,
            branchName: "to-remove",
            baseBranch: currentBranch
        )

        try await manager.removeWorktree(
            repoPath: repoPath,
            worktreePath: worktreePath,
            deleteBranch: true
        )

        #expect(!FileManager.default.fileExists(atPath: worktreePath))

        let worktrees = try await manager.listWorktrees(repoPath: repoPath)
        #expect(worktrees.count == 1)  // Back to just the main worktree
    }
}

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

@Test func diffSummaryOnCleanRepo() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let summary = await manager.diffSummary(path: repoPath)
        // Clean repo should have zero changes or nil
        if let summary {
            #expect(summary.files == 0)
        }
    }
}

@Test func pruneWorktreesOnCleanRepo() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        // Should not throw on a clean repo with nothing to prune
        try await manager.pruneWorktrees(repoPath: repoPath)
        let worktrees = try await manager.listWorktrees(repoPath: repoPath)
        #expect(worktrees.count == 1)
    }
}

@Test func pruneWorktreesRemovesStaleReference() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let (worktreePath, _) = try await manager.createWorktree(
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

// MARK: - Branch Name Sanitization

@Test func sanitizeForDirectoryReplacesSlashes() async {
    let manager = WorktreeManager()
    let result = await manager.sanitizeForDirectory("feature/auth-login")
    #expect(result == "feature-auth-login")
    #expect(!result.contains("/"))
}

@Test func sanitizeForDirectoryHandlesSpecialChars() async {
    let manager = WorktreeManager()
    // # is not a git-invalid character, so it passes through
    #expect(await manager.sanitizeForDirectory("Fix Bug #42") == "fix-bug-#42")
    #expect(await manager.sanitizeForDirectory("a..b") == "a.b")
    #expect(await manager.sanitizeForDirectory("--leading") == "leading")
}

@Test func createWorktreePreservesSlashInBranchName() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let (worktreePath, actualBranch) = try await manager.createWorktree(
            repoPath: repoPath,
            branchName: "feature/my-work",
            baseBranch: currentBranch
        )

        // The directory should use sanitized name (no slashes)
        #expect(worktreePath.hasSuffix("feature-my-work"))

        // The actual git branch should preserve the slash
        #expect(actualBranch == "feature/my-work")

        // Verify the worktree is on the branch with the slash
        let branch = await manager.currentBranch(path: worktreePath)
        #expect(branch == "feature/my-work")
    }
}

@Test func removeWorktreeWithExplicitBranchName() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"

        try FileManager.default.createDirectory(
            atPath: "\(repoPath)/.worktrees",
            withIntermediateDirectories: true
        )

        let (worktreePath, actualBranch) = try await manager.createWorktree(
            repoPath: repoPath,
            branchName: "feature/to-delete",
            baseBranch: currentBranch
        )

        try await manager.removeWorktree(
            repoPath: repoPath,
            worktreePath: worktreePath,
            deleteBranch: true,
            branchName: actualBranch
        )

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
    }
}

@Test func commitLogReturnsEmptyForNoNewCommits() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let currentBranch = await manager.currentBranch(path: repoPath) ?? "main"
        let log = await manager.commitLog(path: repoPath, baseBranch: currentBranch)
        #expect(log.isEmpty)
    }
}
