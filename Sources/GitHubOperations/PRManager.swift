import Foundation
import Models

/// Manages GitHub PR operations by shelling out to the `gh` CLI.
public actor PRManager {
    private var cache: [String: CachedPR] = [:]
    private let cacheTTL: TimeInterval = 60

    public init() {}

    /// Fetch PRs for a given category.
    ///
    /// When `repo` is nil, uses `gh search prs` across all authenticated hosts.
    /// When `repo` is provided, uses `gh pr list` scoped to that repo.
    public func fetchPRs(repo: String? = nil, filter: PRFilter = .mine) async throws -> [PullRequest] {
        if let repo {
            let args = buildListArgs(repo: repo, filter: filter)
            let output = try await runGH(args: args)
            return try parsePRList(output)
        } else {
            // Search all authenticated GitHub hosts
            let hosts = await discoverHosts()
            var allPRs: [PullRequest] = []

            for host in hosts {
                let args = buildSearchArgs(filter: filter)
                if let output = try? await runGH(args: args, host: host) {
                    let prs = (try? parseSearchResults(output)) ?? []
                    allPRs.append(contentsOf: prs)
                }
            }

            return allPRs
        }
    }

    /// Discover all hosts the user is authenticated with via `gh auth status`.
    private func discoverHosts() async -> [String] {
        // gh auth status prints to stderr; capture it directly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "status"]

        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ["github.com"]
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errOutput = String(data: errData, encoding: .utf8) ?? ""
        return parseHosts(from: errOutput)
    }

    /// Fetch detailed PR information.
    public func fetchDetail(repo: String, number: Int) async throws -> PRDetail {
        let output = try await runGH(args: [
            "pr", "view", "\(number)",
            "--repo", repo,
            "--json", "body,reviews,comments,files",
        ])
        return try parsePRDetail(output)
    }

    /// Fetch PR for a specific worktree directory (by current branch).
    public func fetchPRForWorktree(path: String) async throws -> PullRequest? {
        let output = try? await runGH(
            args: [
                "pr", "view",
                "--json",
                "number,title,state,headRefName,baseRefName,author,url,isDraft,additions,deletions,changedFiles,createdAt,updatedAt,reviewDecision,statusCheckRollup",
            ], cwd: path)

        guard let output, !output.isEmpty else { return nil }
        return try parseSinglePR(output)
    }

    /// Approve a PR.
    public func approve(repo: String, number: Int, body: String? = nil) async throws {
        var args = ["pr", "review", "\(number)", "--repo", repo, "--approve"]
        if let body {
            args += ["--body", body]
        }
        try await runGH(args: args)
    }

    /// Add a comment to a PR.
    public func comment(repo: String, number: Int, body: String) async throws {
        try await runGH(args: ["pr", "comment", "\(number)", "--repo", repo, "--body", body])
    }

    /// Open PR in browser.
    public func openInBrowser(repo: String, number: Int) async throws {
        try await runGH(args: ["pr", "view", "\(number)", "--repo", repo, "--web"])
    }

    // MARK: - Private

    @discardableResult
    private func runGH(args: [String], cwd: String? = nil, host: String? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var env = ProcessInfo.processInfo.environment
        if let host {
            env["GH_HOST"] = host
        } else {
            env.removeValue(forKey: "GH_HOST")
        }
        process.environment = env
        process.arguments = ["gh"] + args
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            throw GHError.commandFailed(args: args, exitCode: process.terminationStatus, stderr: errOutput)
        }

        return output
    }

    private func parseHosts(from output: String) -> [String] {
        // Parse "Logged in to <host>" lines from gh auth status output
        var hosts: [String] = []
        for line in output.components(separatedBy: "\n") {
            if let range = line.range(of: "Logged in to ") {
                let rest = line[range.upperBound...]
                if let spaceIdx = rest.firstIndex(of: " ") {
                    hosts.append(String(rest[..<spaceIdx]))
                }
            }
        }
        return hosts.isEmpty ? ["github.com"] : hosts
    }

    private func buildSearchArgs(filter: PRFilter) -> [String] {
        var args = [
            "search", "prs",
            "--state", "open",
            "--json", "number,title,state,repository,url,isDraft,createdAt,updatedAt,author",
            "--limit", "50",
        ]

        switch filter {
        case .mine:
            args += ["--author", "@me"]
        case .reviewRequested:
            args += ["--review-requested", "@me"]
        case .all:
            args += ["--author", "@me"]
        }

        return args
    }

    private func buildListArgs(repo: String, filter: PRFilter) -> [String] {
        var args = [
            "pr", "list", "--json",
            "number,title,state,headRefName,baseRefName,author,url,isDraft,additions,deletions,changedFiles,createdAt,updatedAt,reviewDecision",
            "--repo", repo,
        ]

        switch filter {
        case .mine:
            args += ["--author", "@me"]
        case .reviewRequested:
            args += ["--search", "review-requested:@me"]
        case .all:
            break
        }

        args += ["--limit", "50"]
        return args
    }

    private func parseSearchResults(_ json: String) throws -> [PullRequest] {
        guard let data = json.data(using: .utf8) else { return [] }
        let items = try JSONDecoder.gh.decode([GHSearchPRItem].self, from: data)
        return items.map { $0.toPullRequest() }
    }

    private func parsePRList(_ json: String) throws -> [PullRequest] {
        guard let data = json.data(using: .utf8) else { return [] }
        let items = try JSONDecoder.gh.decode([GHPRItem].self, from: data)
        return items.map { $0.toPullRequest() }
    }

    private func parseSinglePR(_ json: String) throws -> PullRequest? {
        guard let data = json.data(using: .utf8) else { return nil }
        let item = try JSONDecoder.gh.decode(GHPRItem.self, from: data)
        return item.toPullRequest()
    }

    private func parsePRDetail(_ json: String) throws -> PRDetail {
        guard let data = json.data(using: .utf8) else { return PRDetail() }
        let detail = try JSONDecoder.gh.decode(GHPRDetailResponse.self, from: data)
        return detail.toPRDetail()
    }
}

// MARK: - Types

public enum PRFilter: Sendable {
    case mine
    case reviewRequested
    case all
}

public enum GHError: Error, LocalizedError {
    case commandFailed(args: [String], exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let args, let exitCode, let stderr):
            "gh \(args.joined(separator: " ")) failed (exit \(exitCode)): \(stderr)"
        }
    }
}

// MARK: - Cache

private struct CachedPR {
    let pr: PullRequest
    let fetchedAt: Date
}

// MARK: - GH JSON Models

private struct GHPRItem: Decodable {
    let number: Int
    let title: String
    let state: String
    let headRefName: String?
    let baseRefName: String?
    let author: GHAuthor?
    let url: String?
    let isDraft: Bool?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let createdAt: String?
    let updatedAt: String?
    let reviewDecision: String?

    func toPullRequest() -> PullRequest {
        let prState: PRState
        if isDraft == true {
            prState = .draft
        } else {
            switch state.uppercased() {
            case "MERGED": prState = .merged
            case "CLOSED": prState = .closed
            default: prState = .open
            }
        }

        let review: ReviewDecision
        switch reviewDecision?.uppercased() {
        case "APPROVED": review = .approved
        case "CHANGES_REQUESTED": review = .changesRequested
        case "REVIEW_REQUIRED": review = .pending
        default: review = .none
        }

        return PullRequest(
            number: number,
            title: title,
            state: prState,
            headBranch: headRefName ?? "",
            baseBranch: baseRefName ?? "main",
            author: author?.login ?? "",
            repo: extractRepo(from: url ?? ""),
            url: url ?? "",
            isDraft: isDraft ?? false,
            reviewDecision: review,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            changedFiles: changedFiles ?? 0
        )
    }

    private func extractRepo(from url: String) -> String {
        // https://github.com/owner/repo/pull/123 → owner/repo
        let parts = url.components(separatedBy: "/")
        if parts.count >= 5 {
            return "\(parts[3])/\(parts[4])"
        }
        return ""
    }
}

// MARK: - GH Search JSON Models

private struct GHSearchPRItem: Decodable {
    let number: Int
    let title: String
    let state: String
    let repository: GHRepository
    let url: String?
    let isDraft: Bool?
    let createdAt: String?
    let updatedAt: String?
    let author: GHSearchAuthor?

    func toPullRequest() -> PullRequest {
        let prState: PRState
        if isDraft == true {
            prState = .draft
        } else {
            switch state.lowercased() {
            case "merged": prState = .merged
            case "closed": prState = .closed
            default: prState = .open
            }
        }

        return PullRequest(
            number: number,
            title: title,
            state: prState,
            headBranch: "",
            baseBranch: "",
            author: author?.login ?? "",
            repo: repository.nameWithOwner,
            url: url ?? "",
            isDraft: isDraft ?? false,
            reviewDecision: .none,
            additions: 0,
            deletions: 0,
            changedFiles: 0
        )
    }
}

private struct GHRepository: Decodable {
    let name: String
    let nameWithOwner: String
}

private struct GHSearchAuthor: Decodable {
    let login: String
}

private struct GHAuthor: Decodable {
    let login: String
}

private struct GHPRDetailResponse: Decodable {
    let body: String?
    let reviews: [GHReview]?
    let comments: [GHComment]?
    let files: [GHFile]?

    func toPRDetail() -> PRDetail {
        PRDetail(
            body: body ?? "",
            reviews: (reviews ?? []).map {
                PRReview(id: $0.id ?? "0", author: $0.author?.login ?? "", state: $0.state ?? "")
            },
            comments: (comments ?? []).map {
                PRComment(id: $0.id ?? "0", author: $0.author?.login ?? "", body: $0.body ?? "")
            },
            files: (files ?? []).map {
                PRFileChange(path: $0.path ?? "", additions: $0.additions ?? 0, deletions: $0.deletions ?? 0, patch: $0.patch)
            }
        )
    }
}

private struct GHReview: Decodable {
    let author: GHAuthor?
    let state: String?
    let body: String?

    // id can be Int (github.com) or String (GHE) — decode flexibly
    let id: String?

    enum CodingKeys: String, CodingKey {
        case id, author, state, body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decodeIfPresent(GHAuthor.self, forKey: .author)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = "\(intID)"
        } else {
            id = try container.decodeIfPresent(String.self, forKey: .id)
        }
    }
}

private struct GHComment: Decodable {
    let author: GHAuthor?
    let body: String?

    let id: String?

    enum CodingKeys: String, CodingKey {
        case id, author, body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decodeIfPresent(GHAuthor.self, forKey: .author)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = "\(intID)"
        } else {
            id = try container.decodeIfPresent(String.self, forKey: .id)
        }
    }
}

private struct GHFile: Decodable {
    let path: String?
    let additions: Int?
    let deletions: Int?
    let patch: String?
}

// MARK: - JSONDecoder for gh output

extension JSONDecoder {
    fileprivate static let gh: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
