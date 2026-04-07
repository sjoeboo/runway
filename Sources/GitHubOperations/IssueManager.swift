import Foundation
import Models

/// Manages GitHub issue operations by shelling out to the `gh` CLI.
public actor IssueManager {
    public init() {}

    // MARK: - Detail Cache

    private var detailCache: [String: (detail: IssueDetail, fetchedAt: Date)] = [:]
    private let detailTTL: TimeInterval = 300

    public func evictDetail(repo: String, number: Int) {
        detailCache.removeValue(forKey: "\(repo)#\(number)")
    }

    // MARK: - fetchDetail

    /// Fetch detailed issue information including body, comments, timeline events, labels, and assignees.
    /// Results are cached for 5 minutes.
    public func fetchDetail(repo: String, number: Int, host: String? = nil) async throws -> IssueDetail {
        let cacheKey = "\(repo)#\(number)"
        if let cached = detailCache[cacheKey],
            Date().timeIntervalSince(cached.fetchedAt) < detailTTL
        {
            return cached.detail
        }

        // Call 1: gh issue view (rich metadata + comments)
        let viewOutput = try await runGH(
            args: [
                "issue", "view", "\(number)",
                "--repo", repo,
                "--json", "body,comments,labels,assignees,milestone,stateReason",
            ], host: host)

        // Call 2: timeline events via REST API
        let timelineOutput = try await runGH(
            args: ["api", "repos/\(repo)/issues/\(number)/timeline", "--paginate"],
            host: host)

        let detail = try parseIssueDetail(viewOutput: viewOutput, timelineOutput: timelineOutput)
        detailCache[cacheKey] = (detail: detail, fetchedAt: Date())
        return detail
    }

    // MARK: - Mutations

    /// Edit an issue's title and/or body.
    public func editIssue(
        repo: String, number: Int, host: String? = nil,
        title: String? = nil, body: String? = nil
    ) async throws {
        var args = ["issue", "edit", "\(number)", "--repo", repo]
        if let title { args += ["--title", title] }
        if let body { args += ["--body", body] }
        try await runGH(args: args, host: host)
        evictDetail(repo: repo, number: number)
    }

    /// Add a comment to an issue.
    public func addComment(repo: String, number: Int, host: String? = nil, body: String) async throws {
        try await runGH(
            args: ["issue", "comment", "\(number)", "--repo", repo, "--body", body],
            host: host)
        evictDetail(repo: repo, number: number)
    }

    /// Close an issue with an optional reason.
    public func closeIssue(
        repo: String, number: Int, host: String? = nil, reason: CloseReason = .completed
    ) async throws {
        try await runGH(
            args: ["issue", "close", "\(number)", "--repo", repo, "--reason", reason.rawValue],
            host: host)
        evictDetail(repo: repo, number: number)
    }

    /// Reopen a closed issue.
    public func reopenIssue(repo: String, number: Int, host: String? = nil) async throws {
        try await runGH(args: ["issue", "reopen", "\(number)", "--repo", repo], host: host)
        evictDetail(repo: repo, number: number)
    }

    /// Add and/or remove labels on an issue.
    public func updateLabels(
        repo: String, number: Int, host: String? = nil,
        add: [String] = [], remove: [String] = []
    ) async throws {
        var args = ["issue", "edit", "\(number)", "--repo", repo]
        for label in add { args += ["--add-label", label] }
        for label in remove { args += ["--remove-label", label] }
        try await runGH(args: args, host: host)
        evictDetail(repo: repo, number: number)
    }

    /// Add and/or remove assignees on an issue.
    public func updateAssignees(
        repo: String, number: Int, host: String? = nil,
        add: [String] = [], remove: [String] = []
    ) async throws {
        var args = ["issue", "edit", "\(number)", "--repo", repo]
        for user in add { args += ["--add-assignee", user] }
        for user in remove { args += ["--remove-assignee", user] }
        try await runGH(args: args, host: host)
        evictDetail(repo: repo, number: number)
    }

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

    private func parseIssueDetail(viewOutput: String, timelineOutput: String) throws -> IssueDetail {
        // Decode gh issue view response
        guard let viewData = viewOutput.data(using: .utf8) else {
            return IssueDetail()
        }
        let viewItem = try JSONDecoder.issueGH.decode(GHIssueViewItem.self, from: viewData)

        // Map comments
        let comments: [IssueComment] = viewItem.comments.map { comment in
            IssueComment(
                id: comment.id,
                author: comment.author?.login ?? "",
                body: comment.body ?? "",
                createdAt: comment.createdAt ?? Date(),
                updatedAt: comment.updatedAt ?? Date()
            )
        }

        // Map labels
        let labels: [IssueDetailLabel] = viewItem.labels.map { label in
            IssueDetailLabel(name: label.name, color: label.color ?? "")
        }

        // Map assignees
        let assignees: [String] = viewItem.assignees.map { $0.login }

        // Decode timeline events (filter out "commented" — use comments from view instead)
        var timelineEvents: [IssueTimelineEvent] = []
        if let timelineData = timelineOutput.data(using: .utf8),
            let rawEvents = try? JSONDecoder.issueGH.decode([GHTimelineEvent].self, from: timelineData)
        {
            timelineEvents =
                rawEvents
                .filter { $0.event != "commented" }
                .enumerated()
                .map { (index, ev) in
                    let actor = ev.actor?.login ?? ""
                    let id = "\(ev.event)-\(actor)-\(index)"
                    let eventDate = ev.createdAt ?? Date()

                    // Map label
                    let label: IssueDetailLabel? = ev.label.map {
                        IssueDetailLabel(name: $0.name, color: $0.color ?? "")
                    }

                    // Map assignee
                    let assignee: String? = ev.assignee?.login

                    // Map cross-reference source
                    var source: IssueReference?
                    if ev.event == "cross-referenced", let src = ev.source?.issue {
                        let refType = src.pullRequest != nil ? "PullRequest" : "Issue"
                        source = IssueReference(
                            type: refType,
                            number: src.number ?? 0,
                            title: src.title ?? "",
                            url: src.htmlURL ?? ""
                        )
                    }

                    // Map rename
                    let rename: IssueRename? = ev.rename.map {
                        IssueRename(from: $0.from, to: $0.to)
                    }

                    return IssueTimelineEvent(
                        id: id,
                        event: ev.event,
                        actor: actor,
                        createdAt: eventDate,
                        label: label,
                        assignee: assignee,
                        source: source,
                        rename: rename
                    )
                }
        }

        return IssueDetail(
            body: viewItem.body ?? "",
            comments: comments,
            timelineEvents: timelineEvents,
            labels: labels,
            assignees: assignees,
            milestone: viewItem.milestone?.title,
            stateReason: viewItem.stateReason
        )
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

// MARK: - GH Detail JSON Models

private struct GHIssueViewItem: Decodable {
    let body: String?
    let comments: [GHIssueCommentItem]
    let labels: [GHIssueViewLabel]
    let assignees: [GHIssueAssignee]
    let milestone: GHMilestone?
    let stateReason: String?
}

private struct GHIssueCommentItem: Decodable {
    let id: String
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

private struct GHTimelineEvent: Decodable {
    let event: String
    let actor: GHIssueAuthor?
    let createdAt: Date?
    let label: GHTimelineLabel?
    let assignee: GHIssueAuthor?
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
        case number, title
        case htmlURL = "html_url"
        case pullRequest = "pull_request"
    }
}

private struct GHTimelinePullRequestMarker: Decodable {}

private struct GHTimelineRename: Decodable {
    let from: String
    let to: String
}
