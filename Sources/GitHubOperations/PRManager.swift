import Foundation
import Models

/// Lightweight result from enrichChecks — only what's needed for list display.
public struct PREnrichResult: Sendable {
    public var checks: CheckSummary
    public var reviewDecision: ReviewDecision
    public var headBranch: String
    public var baseBranch: String
    public var additions: Int
    public var deletions: Int
    public var changedFiles: Int
    public var mergeable: MergeableState?
    public var mergeStateStatus: MergeStateStatus?
    public var autoMergeEnabled: Bool

    public init(
        checks: CheckSummary = CheckSummary(), reviewDecision: ReviewDecision = .none,
        headBranch: String = "", baseBranch: String = "",
        additions: Int = 0, deletions: Int = 0, changedFiles: Int = 0,
        mergeable: MergeableState? = nil, mergeStateStatus: MergeStateStatus? = nil,
        autoMergeEnabled: Bool = false
    ) {
        self.checks = checks
        self.reviewDecision = reviewDecision
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
        self.autoMergeEnabled = autoMergeEnabled
    }
}

/// Manages GitHub PR operations by shelling out to the `gh` CLI.
public actor PRManager {
    /// Cached hosts from `gh auth status` — rarely changes at runtime
    private var cachedHosts: [String]?
    private var hostsCacheTime: Date?

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

    /// Fetch both "mine" and "review-requested" PRs in parallel, merge and deduplicate.
    /// Each PR gets an `origin` set indicating which queries returned it.
    /// A failure in one filter does not discard results from the other.
    public func fetchAllPRs() async throws -> [PullRequest] {
        // Use separate tasks so a failure in one doesn't discard the other's results
        async let minePRs: [PullRequest] = {
            (try? await fetchPRs(filter: .mine)) ?? []
        }()
        async let reviewPRs: [PullRequest] = {
            (try? await fetchPRs(filter: .reviewRequested)) ?? []
        }()

        let (mine, review) = await (minePRs, reviewPRs)

        // Merge: deduplicate by ID, combine origins
        var merged: [String: PullRequest] = [:]
        for var pr in mine {
            pr.origin = [.mine]
            merged[pr.id] = pr
        }
        for var pr in review {
            pr.origin = [.reviewRequested]
            if var existing = merged[pr.id] {
                existing.origin.insert(.reviewRequested)
                merged[pr.id] = existing
            } else {
                merged[pr.id] = pr
            }
        }

        return Array(merged.values)
    }

    /// Discover all hosts the user is authenticated with via `gh auth status`.
    /// Results are cached for 5 minutes to avoid spawning a subprocess on every fetch.
    private func discoverHosts() async -> [String] {
        if let cached = cachedHosts, let time = hostsCacheTime,
            Date().timeIntervalSince(time) < 300
        {
            return cached
        }
        guard let output = try? await runGH(args: ["auth", "status"]) else {
            return cachedHosts ?? ["github.com"]
        }
        let hosts = parseHosts(from: output)
        cachedHosts = hosts
        hostsCacheTime = Date()
        return hosts
    }

    /// Lightweight enrichment — fetch only checks and review decision for list display.
    /// Single subprocess per PR (vs fetchDetail's 2).
    public func enrichChecks(repo: String, number: Int, host: String? = nil) async throws -> PREnrichResult {
        let output = try await runGH(
            args: [
                "pr", "view", "\(number)",
                "--repo", repo,
                "--json",
                "statusCheckRollup,reviewDecision,headRefName,baseRefName,additions,deletions,changedFiles,mergeable,mergeStateStatus,autoMergeRequest",
            ], host: host)
        guard let data = output.data(using: .utf8) else {
            return PREnrichResult()
        }
        let resp = try JSONDecoder.gh.decode(GHEnrichResponse.self, from: data)
        return resp.toEnrichResult()
    }

    /// Fetch detailed PR information including per-file diffs.
    public func fetchDetail(repo: String, number: Int, host: String? = nil) async throws -> PRDetail {
        let output = try await runGH(
            args: [
                "pr", "view", "\(number)",
                "--repo", repo,
                "--json",
                "body,reviews,comments,files,statusCheckRollup,reviewDecision,headRefName,baseRefName,additions,deletions,changedFiles,mergeable,mergeStateStatus,autoMergeRequest",
            ], host: host)
        var detail = try parsePRDetail(output)

        // gh --json files doesn't include patch data; fetch via REST API
        if let patches = try? await fetchFileDiffs(repo: repo, number: number, host: host) {
            detail.files = detail.files.map { file in
                var updated = file
                updated.patch = patches[file.path]
                return updated
            }
        }

        return detail
    }

    /// Fetch per-file patch content via the REST API.
    private func fetchFileDiffs(repo: String, number: Int, host: String? = nil) async throws -> [String: String] {
        // --slurp wraps each page in an outer array so --paginate output is valid JSON
        let output = try await runGH(
            args: ["api", "repos/\(repo)/pulls/\(number)/files", "--paginate", "--slurp"],
            host: host
        )
        guard let data = output.data(using: .utf8) else { return [:] }
        // --slurp produces [[...], [...]] — one inner array per page
        let pages = try JSONDecoder().decode([[GHRESTFile]].self, from: data)
        var patches: [String: String] = [:]
        for file in pages.flatMap({ $0 }) {
            if let patch = file.patch {
                patches[file.filename] = patch
            }
        }
        return patches
    }

    /// Extract the GitHub host from a PR URL (e.g., "https://ghe.spotify.net/..." → "ghe.spotify.net").
    /// Nonisolated because this is pure URL parsing with no actor state.
    nonisolated public func hostFromURL(_ url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host else { return nil }
        return host == "github.com" ? nil : host  // nil means default (github.com)
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

    /// Approve a PR.
    public func approve(repo: String, number: Int, body: String? = nil, host: String? = nil) async throws {
        var args = ["pr", "review", "\(number)", "--repo", repo, "--approve"]
        if let body {
            args += ["--body", body]
        }
        try await runGH(args: args, host: host)
    }

    /// Add a comment to a PR.
    public func comment(repo: String, number: Int, body: String, host: String? = nil) async throws {
        try await runGH(args: ["pr", "comment", "\(number)", "--repo", repo, "--body", body], host: host)
    }

    /// Request changes on a PR.
    public func requestChanges(repo: String, number: Int, body: String, host: String? = nil) async throws {
        try await runGH(
            args: ["pr", "review", "\(number)", "--repo", repo, "--request-changes", "--body", body],
            host: host
        )
    }

    /// Merge a PR with the specified strategy.
    public func merge(repo: String, number: Int, strategy: MergeStrategy = .squash, host: String? = nil) async throws {
        try await runGH(
            args: ["pr", "merge", "\(number)", "--repo", repo, strategy.cliFlag, "--delete-branch"],
            host: host
        )
    }

    /// Enable auto-merge on a PR with the specified strategy.
    public func enableAutoMerge(repo: String, number: Int, strategy: MergeStrategy = .squash, host: String? = nil) async throws {
        try await runGH(
            args: ["pr", "merge", "\(number)", "--repo", repo, strategy.cliFlag, "--auto"],
            host: host
        )
    }

    /// Disable auto-merge on a PR.
    public func disableAutoMerge(repo: String, number: Int, host: String? = nil) async throws {
        try await runGH(
            args: ["pr", "merge", "\(number)", "--repo", repo, "--disable-auto"],
            host: host
        )
    }

    /// Close a PR without merging.
    public func close(repo: String, number: Int, host: String? = nil) async throws {
        try await runGH(
            args: ["pr", "close", "\(number)", "--repo", repo],
            host: host
        )
    }

    /// Update a PR branch with the latest base branch (merge or rebase).
    public func updateBranch(repo: String, number: Int, rebase: Bool = false, host: String? = nil) async throws {
        var args = ["pr", "update-branch", "\(number)", "--repo", repo]
        if rebase {
            args.append("--rebase")
        }
        try await runGH(args: args, host: host)
    }

    /// Toggle draft state. `gh pr ready` to mark ready; GraphQL mutation to convert to draft.
    public func toggleDraft(repo: String, number: Int, makeDraft: Bool, host: String? = nil) async throws {
        if makeDraft {
            let nodeOutput = try await runGH(
                args: ["pr", "view", "\(number)", "--repo", repo, "--json", "id", "-q", ".id"],
                host: host
            )
            let nodeID = nodeOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validate nodeID to prevent GraphQL injection (should be alphanumeric + _ + =)
            let isValid = !nodeID.isEmpty && nodeID.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "=" }
            guard isValid else {
                throw PRActionError.invalidNodeID(nodeID)
            }
            try await runGH(
                args: [
                    "api", "graphql",
                    "-f", "query=mutation { convertPullRequestToDraft(input: {pullRequestId: \"\(nodeID)\"}) { pullRequest { isDraft } } }",
                ],
                host: host
            )
        } else {
            // Currently draft → mark as ready
            try await runGH(
                args: ["pr", "ready", "\(number)", "--repo", repo],
                host: host
            )
        }
    }

    /// Lightweight probe: returns a fingerprint (count + latest updatedAt) for open PRs.
    /// Costs a single `gh search` subprocess with `--limit 1` — typically ~200ms.
    /// Returns nil if the check fails (offline, auth expired, etc.).
    public func prFingerprint(filter: PRFilter = .mine) async -> PRFingerprint? {
        let hosts = await discoverHosts()
        // Use the first host only — fast probe, not exhaustive
        guard let host = hosts.first else { return nil }
        var args = [
            "search", "prs",
            "--state", "open",
            "--archived=false",
            "--json", "updatedAt",
            "--limit", "1",
        ]
        switch filter {
        case .mine: args += ["--author", "@me"]
        case .reviewRequested: args += ["--review-requested", "@me"]
        case .all: break
        }
        // gh search --json returns an array; also print total via --jq is fragile,
        // so we just check the latest updatedAt as our change signal.
        guard let output = try? await runGH(args: args, host: host),
            let data = output.data(using: .utf8),
            let items = try? JSONDecoder.gh.decode([GHFingerprintItem].self, from: data)
        else { return nil }
        return PRFingerprint(latestUpdate: items.first?.updatedAt)
    }

    // MARK: - Private

    @discardableResult
    private func runGH(args: [String], cwd: String? = nil, host: String? = nil) async throws -> String {
        try await ShellRunner.runGH(args: args, cwd: cwd, host: host)
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
            "--archived=false",
            "--json", "number,title,state,repository,url,isDraft,createdAt,updatedAt,author",
            "--limit", "50",
        ]

        switch filter {
        case .mine:
            args += ["--author", "@me"]
        case .reviewRequested:
            args += ["--review-requested", "@me"]
        case .all:
            break  // No author filter — show all open PRs
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

public enum PRActionError: Error, LocalizedError {
    case invalidNodeID(String)

    public var errorDescription: String? {
        switch self {
        case .invalidNodeID(let id):
            "Invalid PR node ID: \(id)"
        }
    }
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
    let createdAt: Date?
    let updatedAt: Date?
    let reviewDecision: String?
    let statusCheckRollup: [GHCheck]?

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

        let checks = parseChecks(statusCheckRollup ?? [])

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
            checks: checks,
            reviewDecision: review,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            changedFiles: changedFiles ?? 0,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
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
    let createdAt: Date?
    let updatedAt: Date?
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
            changedFiles: 0,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
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
    let statusCheckRollup: [GHCheck]?
    let reviewDecision: String?
    let headRefName: String?
    let baseRefName: String?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let mergeable: String?
    let mergeStateStatus: String?
    let autoMergeRequest: GHAutoMergeRequest?

    func toPRDetail() -> PRDetail {
        let rollup = statusCheckRollup ?? []
        let checks = parseChecks(rollup)
        let runs = parseCheckRuns(rollup)

        let review: ReviewDecision
        switch reviewDecision?.uppercased() {
        case "APPROVED": review = .approved
        case "CHANGES_REQUESTED": review = .changesRequested
        case "REVIEW_REQUIRED": review = .pending
        default: review = .none
        }

        let mappedReviews: [PRReview] = (reviews ?? []).map { r in
            PRReview(id: r.id ?? "0", author: r.author?.login ?? "", state: r.state ?? "", body: r.body ?? "")
        }
        let mappedComments: [PRComment] = (comments ?? []).map { comment in
            PRComment(id: comment.id ?? "0", author: comment.author?.login ?? "", body: comment.body ?? "")
        }
        let mappedFiles: [PRFileChange] = (files ?? []).map { file in
            PRFileChange(path: file.path ?? "", additions: file.additions ?? 0, deletions: file.deletions ?? 0, patch: file.patch)
        }

        return PRDetail(
            body: body ?? "",
            reviews: mappedReviews,
            comments: mappedComments,
            files: mappedFiles,
            checks: checks,
            checkRuns: runs,
            reviewDecision: review,
            headBranch: headRefName ?? "",
            baseBranch: baseRefName ?? "",
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            changedFiles: changedFiles ?? 0,
            mergeable: MergeableState(rawValue: mergeable ?? ""),
            mergeStateStatus: MergeStateStatus(rawValue: mergeStateStatus ?? ""),
            autoMergeEnabled: autoMergeRequest != nil
        )
    }

}

private struct GHCheck: Decodable {
    let name: String?  // CheckRun display name
    let context: String?  // StatusContext display name
    let status: String?
    let conclusion: String?
    let state: String?  // For StatusContext type checks
    let detailsUrl: String?  // CheckRun detail link
    let targetUrl: String?  // StatusContext detail link

    /// Display name — CheckRun uses `name`, StatusContext uses `context`.
    var displayName: String? { name ?? context }

    /// URL to the check's detail page (works for both CheckRun and StatusContext).
    var url: String? { detailsUrl ?? targetUrl }
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

/// Lightweight response for enrichChecks — only the fields needed for list display.
private struct GHEnrichResponse: Decodable {
    let statusCheckRollup: [GHCheck]?
    let reviewDecision: String?
    let headRefName: String?
    let baseRefName: String?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let mergeable: String?
    let mergeStateStatus: String?
    let autoMergeRequest: GHAutoMergeRequest?

    func toEnrichResult() -> PREnrichResult {
        let checks = parseChecks(statusCheckRollup ?? [])
        let review: ReviewDecision
        switch reviewDecision?.uppercased() {
        case "APPROVED": review = .approved
        case "CHANGES_REQUESTED": review = .changesRequested
        case "REVIEW_REQUIRED": review = .pending
        default: review = .none
        }
        return PREnrichResult(
            checks: checks, reviewDecision: review,
            headBranch: headRefName ?? "", baseBranch: baseRefName ?? "",
            additions: additions ?? 0, deletions: deletions ?? 0, changedFiles: changedFiles ?? 0,
            mergeable: MergeableState(rawValue: mergeable ?? ""),
            mergeStateStatus: MergeStateStatus(rawValue: mergeStateStatus ?? ""),
            autoMergeEnabled: autoMergeRequest != nil
        )
    }
}

/// Auto-merge request — presence indicates auto-merge is enabled.
private struct GHAutoMergeRequest: Decodable {
    let enabledAt: String?
    let mergeMethod: String?
}

private struct GHFile: Decodable {
    let path: String?
    let additions: Int?
    let deletions: Int?
    let patch: String?
}

// MARK: - Shared Helpers

private func classifyCheck(_ check: GHCheck) -> CheckStatus {
    let status = check.status?.uppercased() ?? ""
    let conclusion = check.conclusion?.uppercased() ?? ""
    let checkState = check.state?.uppercased() ?? ""

    if status == "COMPLETED" {
        if conclusion == "SUCCESS" || conclusion == "NEUTRAL" || conclusion == "SKIPPED" {
            return .passed
        } else if conclusion == "FAILURE" || conclusion == "TIMED_OUT" || conclusion == "CANCELLED" {
            return .failed
        } else {
            return .pending
        }
    } else if checkState == "SUCCESS" {
        return .passed
    } else if checkState == "FAILURE" || checkState == "ERROR" {
        return .failed
    } else {
        return .pending
    }
}

private func parseChecks(_ checks: [GHCheck]) -> CheckSummary {
    var passed = 0
    var failed = 0
    var pending = 0
    for check in checks {
        switch classifyCheck(check) {
        case .passed: passed += 1
        case .failed: failed += 1
        case .pending: pending += 1
        }
    }
    return CheckSummary(passed: passed, failed: failed, pending: pending)
}

private func parseCheckRuns(_ checks: [GHCheck]) -> [CheckRun] {
    checks.compactMap { check in
        guard let name = check.displayName, !name.isEmpty else { return nil }
        return CheckRun(
            name: name,
            status: classifyCheck(check),
            detailsURL: check.url
        )
    }
    .sorted { lhs, rhs in
        // Failed first, then pending, then passed
        let order: [CheckStatus] = [.failed, .pending, .passed]
        let li = order.firstIndex(of: lhs.status) ?? 2
        let ri = order.firstIndex(of: rhs.status) ?? 2
        if li != ri { return li < ri }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

/// REST API response for /repos/:owner/:repo/pulls/:number/files
private struct GHRESTFile: Decodable {
    let filename: String
    let additions: Int?
    let deletions: Int?
    let patch: String?
}

// MARK: - Fingerprint Types

/// Lightweight snapshot of PR state used to detect changes without a full fetch.
public struct PRFingerprint: Equatable, Sendable {
    public let latestUpdate: String?
}

private struct GHFingerprintItem: Decodable {
    let updatedAt: String?
}

// MARK: - JSONDecoder for gh output

extension JSONDecoder {
    fileprivate static let gh: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
