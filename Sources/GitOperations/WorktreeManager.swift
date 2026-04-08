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
            _ = try? await runGit(in: repoPath, args: ["fetch", "origin", baseBranch])
            try await runGit(in: repoPath, args: ["worktree", "add", "-b", sanitized, worktreePath, "origin/\(baseBranch)"])
        } else {
            // No remote — branch from local base branch
            try await runGit(in: repoPath, args: ["worktree", "add", "-b", sanitized, worktreePath, baseBranch])
        }

        return worktreePath
    }

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
        _ = try? await runGit(in: repoPath, args: ["fetch", "origin", branch])

        // Try creating worktree tracking the remote branch
        do {
            try await runGit(
                in: repoPath,
                args: [
                    "worktree", "add", "--track", "-b", sanitized, worktreePath, "origin/\(branch)",
                ])
        } catch {
            // Clean up partial directory from failed attempt before retry
            if FileManager.default.fileExists(atPath: worktreePath) {
                try? FileManager.default.removeItem(atPath: worktreePath)
                // Prune stale worktree references
                _ = try? await runGit(in: repoPath, args: ["worktree", "prune"])
            }
            // Fallback: local branch already exists — reuse it
            try await runGit(
                in: repoPath,
                args: [
                    "worktree", "add", worktreePath, sanitized,
                ])
        }

        return worktreePath
    }

    /// List all worktrees for a repository.
    public func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        let output = try await runGit(in: repoPath, args: ["worktree", "list", "--porcelain"])
        return parseWorktreeList(output)
    }

    /// Prune stale worktree references (e.g., directories that were manually deleted).
    public func pruneWorktrees(repoPath: String) async throws {
        try await runGit(in: repoPath, args: ["worktree", "prune"])
    }

    /// Check whether a branch has been fully merged into a target branch.
    public func isBranchMerged(repoPath: String, branch: String, into target: String) async throws -> Bool {
        let output = try await runGit(in: repoPath, args: ["branch", "--merged", target])
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
            .contains(branch)
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
            _ = try? await runGit(in: repoPath, args: ["branch", "-D", branchName])
        }
    }

    /// Get the current branch name for a directory.
    /// Returns nil for detached HEAD (git returns literal "HEAD").
    public func currentBranch(path: String) async -> String? {
        guard
            let result = try? await runGit(in: path, args: ["rev-parse", "--abbrev-ref", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        // Detached HEAD returns the literal string "HEAD"
        return result == "HEAD" ? nil : result
    }

    /// Get a summary of changes in the working directory.
    public func diffSummary(path: String) async -> DiffSummary? {
        guard let output = try? await runGit(in: path, args: ["diff", "--stat", "HEAD"]) else {
            return nil
        }
        return parseDiffStat(output)
    }

    /// Get per-file changes for a given mode.
    ///
    /// - Parameters:
    ///   - path: Path to the git repository (or worktree)
    ///   - mode: `.working` diffs against HEAD; `.branch` diffs against the merge-base with the default branch
    /// - Returns: Array of `FileChange` values, one per changed file
    public func changedFiles(path: String, mode: ChangesMode) async -> [FileChange] {
        do {
            let base: String
            switch mode {
            case .working:
                base = "HEAD"
            case .branch:
                let defaultBranch = await detectDefaultBranch(repoPath: path)
                base =
                    (try? await runGit(in: path, args: ["merge-base", defaultBranch, "HEAD"]))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "HEAD"
            }

            let numstat = (try? await runGit(in: path, args: ["diff", "--numstat", base])) ?? ""
            let nameStatus = (try? await runGit(in: path, args: ["diff", "--name-status", base])) ?? ""
            return parseChangedFiles(numstat: numstat, nameStatus: nameStatus)
        }
    }

    /// Get the unified diff for a single file.
    ///
    /// - Parameters:
    ///   - path: Path to the git repository (or worktree)
    ///   - file: Relative path to the file within the repository
    ///   - mode: `.working` diffs against HEAD; `.branch` diffs against the merge-base with the default branch
    /// - Returns: Unified diff string, or `nil` if unavailable
    public func fileDiff(path: String, file: String, mode: ChangesMode) async -> String? {
        let base: String
        switch mode {
        case .working:
            base = "HEAD"
        case .branch:
            let defaultBranch = await detectDefaultBranch(repoPath: path)
            base =
                (try? await runGit(in: path, args: ["merge-base", defaultBranch, "HEAD"]))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "HEAD"
        }

        return try? await runGit(in: path, args: ["diff", base, "--", file])
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
        var result =
            name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        // Remove git-invalid characters: ~ ^ : ? * [ ] \ @ { }
        let invalidChars = CharacterSet(charactersIn: "~^:?*[]\\@{}")
        result = result.components(separatedBy: invalidChars).joined()
        // Collapse consecutive dots (.. is invalid) and hyphens
        while result.contains("..") { result = result.replacingOccurrences(of: "..", with: ".") }
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        // Remove leading dots/hyphens and trailing .lock
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        if result.hasSuffix(".lock") { result = String(result.dropLast(5)) }
        return result.isEmpty ? "session" : result
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

// MARK: - Parsing

/// Parse `git diff --numstat` and `git diff --name-status` output into an array of `FileChange` values.
///
/// - Parameters:
///   - numstat: Output of `git diff --numstat <base>`
///   - nameStatus: Output of `git diff --name-status <base>`
/// - Returns: Array of `FileChange`, one per changed file
public func parseChangedFiles(numstat: String, nameStatus: String) -> [FileChange] {
    // Parse name-status first: maps path → (status, canonical path)
    // Rename lines have three fields: R<N>\told\tnew
    var statusMap: [String: (status: FileChangeStatus, canonicalPath: String)] = [:]

    for line in nameStatus.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.components(separatedBy: "\t")
        guard parts.count >= 2 else { continue }
        let code = parts[0]
        let status = FileChangeStatus(gitCode: code)
        if status == .renamed, parts.count >= 3 {
            let oldPath = parts[1]
            let newPath = parts[2]
            // Key by old path so numstat can look it up; canonical is newPath
            statusMap[oldPath] = (status: .renamed, canonicalPath: newPath)
        } else {
            let filePath = parts[1]
            statusMap[filePath] = (status: status, canonicalPath: filePath)
        }
    }

    // Parse numstat: additions\tdeletions\tpath
    // Renamed files appear as: adds\tdels\t{old => new}/rest  or  old => new
    var changes: [FileChange] = []

    for line in numstat.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.components(separatedBy: "\t")
        guard parts.count >= 3 else { continue }

        let addStr = parts[0]
        let delStr = parts[1]
        let rawPath = parts[2]

        let additions = Int(addStr) ?? 0
        let deletions = Int(delStr) ?? 0

        // Resolve canonical path from status map if this is a rename
        // First try direct lookup, then resolve rename paths from `{old => new}` notation
        if let entry = statusMap[rawPath] {
            changes.append(
                FileChange(
                    path: entry.canonicalPath,
                    status: entry.status,
                    additions: additions,
                    deletions: deletions
                ))
        } else if rawPath.contains("=>") {
            // Rename path like "src/{Old => New}/File.swift" or "Old.swift => New.swift"
            let resolvedPath = resolveRenamePath(rawPath)
            // Find the matching entry in statusMap by canonical path
            if let entry = statusMap.values.first(where: { $0.canonicalPath == resolvedPath }) {
                changes.append(
                    FileChange(
                        path: entry.canonicalPath,
                        status: entry.status,
                        additions: additions,
                        deletions: deletions
                    ))
            } else {
                // Fallback: use resolved path with renamed status
                changes.append(
                    FileChange(
                        path: resolvedPath,
                        status: .renamed,
                        additions: additions,
                        deletions: deletions
                    ))
            }
        } else {
            // Path not in statusMap — use as-is with modified status (shouldn't happen normally)
            changes.append(
                FileChange(
                    path: rawPath,
                    status: .modified,
                    additions: additions,
                    deletions: deletions
                ))
        }
    }

    return changes
}

/// Resolve a git rename path like `src/{Old => New}/File.swift` to `src/New/File.swift`.
private func resolveRenamePath(_ path: String) -> String {
    // Pattern: prefix/{old => new}/suffix  →  prefix/new/suffix
    // Pattern: old => new                  →  new
    if let braceOpen = path.firstIndex(of: "{"), let braceClose = path.firstIndex(of: "}") {
        let prefix = String(path[path.startIndex..<braceOpen])
        let suffix = String(path[path.index(after: braceClose)...])
        let inner = String(path[path.index(after: braceOpen)..<braceClose])
        let innerParts = inner.components(separatedBy: " => ")
        let newPart = innerParts.count >= 2 ? innerParts[1] : inner
        return prefix + newPart + suffix
    } else if path.contains(" => ") {
        let parts = path.components(separatedBy: " => ")
        return parts.count >= 2 ? parts[1] : path
    }
    return path
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
