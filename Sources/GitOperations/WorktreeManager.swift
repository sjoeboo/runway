import Foundation
import Models

/// Manages git worktree operations by shelling out to the git CLI.
public actor WorktreeManager {

    public init() {}

    /// Create a new worktree with a new branch from the default branch.
    ///
    /// - Parameters:
    ///   - repoPath: Path to the main repository
    ///   - branchName: Name for the new branch (will be sanitized)
    ///   - baseBranch: Branch to base the worktree on (default: "main")
    /// - Returns: Path to the created worktree directory
    public func createWorktree(
        repoPath: String,
        branchName: String,
        baseBranch: String = "main"
    ) async throws -> String {
        let sanitized = sanitizeBranchName(branchName)
        let worktreePath = "\(repoPath)/.worktrees/\(sanitized)"

        // Try to update base branch from remote (non-fatal if no remote)
        let hasRemote =
            (try? await runGit(in: repoPath, args: ["remote"])).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false

        if hasRemote {
            try? await runGit(in: repoPath, args: ["fetch", "origin", baseBranch])
            try await runGit(in: repoPath, args: ["worktree", "add", "-b", sanitized, worktreePath, "origin/\(baseBranch)"])
        } else {
            // No remote — branch from local base branch
            try await runGit(in: repoPath, args: ["worktree", "add", "-b", sanitized, worktreePath, baseBranch])
        }

        return worktreePath
    }

    /// List all worktrees for a repository.
    public func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        let output = try await runGit(in: repoPath, args: ["worktree", "list", "--porcelain"])
        return parseWorktreeList(output)
    }

    /// Remove a worktree and optionally delete its branch.
    public func removeWorktree(
        repoPath: String,
        worktreePath: String,
        deleteBranch: Bool = false
    ) async throws {
        try await runGit(in: repoPath, args: ["worktree", "remove", worktreePath, "--force"])

        if deleteBranch {
            // Extract branch name from worktree path
            let branchName = URL(fileURLWithPath: worktreePath).lastPathComponent
            try? await runGit(in: repoPath, args: ["branch", "-D", branchName])
        }
    }

    /// Get the current branch name for a directory.
    public func currentBranch(path: String) async -> String? {
        try? await runGit(in: path, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get a summary of changes in the working directory.
    public func diffSummary(path: String) async -> DiffSummary? {
        guard let output = try? await runGit(in: path, args: ["diff", "--stat", "HEAD"]) else {
            return nil
        }
        return parseDiffStat(output)
    }

    /// Detect the default branch for a repository.
    ///
    /// Uses `git symbolic-ref refs/remotes/origin/HEAD` (local, no network).
    /// Falls back to checking if common branch names exist locally, then "main".
    public func detectDefaultBranch(repoPath: String) async -> String {
        // Try symbolic-ref first (instant, local-only)
        if let ref = try? await runGit(in: repoPath, args: ["symbolic-ref", "refs/remotes/origin/HEAD"]) {
            let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            // refs/remotes/origin/main → main
            if let last = trimmed.split(separator: "/").last {
                return String(last)
            }
        }

        // Fallback: check if common default branch names exist locally
        for candidate in ["main", "master"]
        where (try? await runGit(in: repoPath, args: ["rev-parse", "--verify", candidate])) != nil {
            return candidate
        }

        return "main"
    }

    // MARK: - Private

    @discardableResult
    private func runGit(in directory: String, args: [String]) async throws -> String {
        try await ShellRunner.runGit(in: directory, args: args)
    }

    private func sanitizeBranchName(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
    }

    private func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var current: (path: String?, branch: String?, isBare: Bool) = (nil, nil, false)

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                if let path = current.path {
                    worktrees.append(
                        WorktreeInfo(
                            path: path,
                            branch: current.branch ?? "",
                            isBare: current.isBare
                        ))
                }
                current = (String(line.dropFirst("worktree ".count)), nil, false)
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                current.branch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "bare" {
                current.isBare = true
            }
        }

        if let path = current.path {
            worktrees.append(
                WorktreeInfo(
                    path: path,
                    branch: current.branch ?? "",
                    isBare: current.isBare
                ))
        }

        return worktrees
    }

    private func parseDiffStat(_ output: String) -> DiffSummary {
        var files = 0
        var additions = 0
        var deletions = 0

        let lines = output.components(separatedBy: "\n")
        if let summary = lines.last(where: { $0.contains("changed") }) {
            let parts = summary.components(separatedBy: ",")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("file") {
                    files = Int(trimmed.components(separatedBy: " ").first ?? "") ?? 0
                } else if trimmed.contains("insertion") {
                    additions = Int(trimmed.components(separatedBy: " ").first ?? "") ?? 0
                } else if trimmed.contains("deletion") {
                    deletions = Int(trimmed.components(separatedBy: " ").first ?? "") ?? 0
                }
            }
        }

        return DiffSummary(files: files, additions: additions, deletions: deletions)
    }
}

// MARK: - Types

public struct WorktreeInfo: Sendable {
    public let path: String
    public let branch: String
    public let isBare: Bool
}

public struct DiffSummary: Sendable {
    public let files: Int
    public let additions: Int
    public let deletions: Int
}

public enum GitError: Error, LocalizedError {
    case commandFailed(args: [String], exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let args, let exitCode, let stderr):
            "git \(args.joined(separator: " ")) failed (exit \(exitCode)): \(stderr)"
        }
    }
}
