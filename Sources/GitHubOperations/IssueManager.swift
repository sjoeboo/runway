import Foundation
import Models

/// Manages GitHub issue operations by shelling out to the `gh` CLI.
public actor IssueManager {
    public init() {}

    /// Fetch issues for a given repo.
    public func fetchIssues(repo: String, host: String? = nil) async throws -> [GitHubIssue] {
        let args = [
            "issue", "list",
            "--repo", repo,
            "--state", "all",
            "--json", "number,title,state,author,labels,assignees,url,createdAt,updatedAt",
            "--limit", "50",
        ]
        let output = try await runGH(args: args, host: host)
        return try parseIssues(output, repo: repo)
    }

    /// Create a new issue.
    public func createIssue(
        repo: String,
        host: String? = nil,
        title: String,
        body: String,
        labels: [String] = []
    ) async throws {
        var args = ["issue", "create", "--repo", repo, "--title", title, "--body", body]
        for label in labels {
            args += ["--label", label]
        }
        try await runGH(args: args, host: host)
    }

    /// Fetch labels for a given repo.
    public func fetchLabels(repo: String, host: String? = nil) async throws -> [IssueLabel] {
        let args = [
            "label", "list",
            "--repo", repo,
            "--json", "name,color",
            "--limit", "100",
        ]
        let output = try await runGH(args: args, host: host)
        return try parseLabels(output)
    }

    /// Detect repo and host from a local git working directory.
    public func detectRepo(path: String) async -> (repo: String, host: String?)? {
        guard let output = try? await ShellRunner.runGit(in: path, args: ["remote", "get-url", "origin"]) else {
            return nil
        }
        let remoteURL = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseRemoteURL(remoteURL)
    }

    // MARK: - Private

    @discardableResult
    private func runGH(args: [String], cwd: String? = nil, host: String? = nil) async throws -> String {
        try await ShellRunner.runGH(args: args, cwd: cwd, host: host)
    }

    private func parseIssues(_ json: String, repo: String) throws -> [GitHubIssue] {
        guard let data = json.data(using: .utf8) else { return [] }
        let items = try JSONDecoder.issueGH.decode([GHIssueItem].self, from: data)
        return items.map { $0.toGitHubIssue(repo: repo) }
    }

    private func parseLabels(_ json: String) throws -> [IssueLabel] {
        guard let data = json.data(using: .utf8) else { return [] }
        return try JSONDecoder.issueGH.decode([IssueLabel].self, from: data)
    }

    private func parseRemoteURL(_ url: String) -> (repo: String, host: String?)? {
        // SSH: git@github.com:owner/repo.git
        // SSH GHE: git@ghe.spotify.net:owner/repo.git
        if url.hasPrefix("git@") {
            // git@<host>:<owner/repo>[.git]
            let withoutPrefix = String(url.dropFirst(4))  // drop "git@"
            guard let colonIdx = withoutPrefix.firstIndex(of: ":") else { return nil }
            let hostPart = String(withoutPrefix[..<colonIdx])
            var repoPart = String(withoutPrefix[withoutPrefix.index(after: colonIdx)...])
            if repoPart.hasSuffix(".git") {
                repoPart = String(repoPart.dropLast(4))
            }
            let host: String? = hostPart == "github.com" ? nil : hostPart
            return (repo: repoPart, host: host)
        }

        // HTTPS: https://github.com/owner/repo.git or https://ghe.spotify.net/owner/repo.git
        if let parsed = URL(string: url), let hostPart = parsed.host {
            let pathComponents = parsed.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 {
                var repoName = pathComponents[1]
                if repoName.hasSuffix(".git") {
                    repoName = String(repoName.dropLast(4))
                }
                let repoPart = "\(pathComponents[0])/\(repoName)"
                let host: String? = hostPart == "github.com" ? nil : hostPart
                return (repo: repoPart, host: host)
            }
        }

        return nil
    }
}

// MARK: - Public Supporting Types

public struct IssueLabel: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let color: String
}

public enum IssueError: Error, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

// MARK: - JSONDecoder

extension JSONDecoder {
    fileprivate static let issueGH: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - GH JSON Models

private struct GHIssueItem: Decodable {
    let number: Int
    let title: String
    let state: String
    let author: GHIssueAuthor?
    let labels: [GHIssueLabelItem]?
    let assignees: [GHIssueAssignee]?
    let url: String?
    let createdAt: Date?
    let updatedAt: Date?

    func toGitHubIssue(repo: String) -> GitHubIssue {
        let issueState: IssueState
        switch state.uppercased() {
        case "CLOSED": issueState = .closed
        default: issueState = .open
        }

        return GitHubIssue(
            number: number,
            title: title,
            state: issueState,
            author: author?.login ?? "",
            repo: repo,
            labels: (labels ?? []).map { $0.name },
            assignees: (assignees ?? []).map { $0.login },
            url: url ?? "",
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }
}

private struct GHIssueAuthor: Decodable {
    let login: String
}

private struct GHIssueLabelItem: Decodable {
    let name: String
}

private struct GHIssueAssignee: Decodable {
    let login: String
}
