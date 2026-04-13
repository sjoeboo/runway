import Foundation

/// A GitHub pull request with metadata, checks, and review status.
public struct PullRequest: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let number: Int
    public var title: String
    public var state: PRState
    public var headBranch: String
    public var baseBranch: String
    public var author: String
    public var repo: String
    public var url: String
    public var isDraft: Bool
    public var checks: CheckSummary
    public var reviewDecision: ReviewDecision
    public var additions: Int
    public var deletions: Int
    public var changedFiles: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var enrichedAt: Date?
    public var origin: Set<PROrigin>
    public var mergeable: MergeableState?
    public var mergeStateStatus: MergeStateStatus?
    public var autoMergeEnabled: Bool

    public init(
        number: Int,
        title: String,
        state: PRState,
        headBranch: String,
        baseBranch: String,
        author: String,
        repo: String,
        url: String = "",
        isDraft: Bool = false,
        checks: CheckSummary = CheckSummary(),
        reviewDecision: ReviewDecision = .pending,
        additions: Int = 0,
        deletions: Int = 0,
        changedFiles: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        enrichedAt: Date? = nil,
        origin: Set<PROrigin> = [],
        mergeable: MergeableState? = nil,
        mergeStateStatus: MergeStateStatus? = nil,
        autoMergeEnabled: Bool = false
    ) {
        self.id = "\(repo)#\(number)"
        self.number = number
        self.title = title
        self.state = state
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.author = author
        self.repo = repo
        self.url = url
        self.isDraft = isDraft
        self.checks = checks
        self.reviewDecision = reviewDecision
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.enrichedAt = enrichedAt
        self.origin = origin
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
        self.autoMergeEnabled = autoMergeEnabled
    }

    public var needsEnrichment: Bool {
        guard let enrichedAt else { return true }
        return Date().timeIntervalSince(enrichedAt) > 300
    }
}

// MARK: - PR Origin

public enum PROrigin: String, Codable, Sendable, Hashable {
    case mine
    case reviewRequested
}

// MARK: - PR State

public enum PRState: String, Codable, Sendable {
    case open = "OPEN"
    case draft = "DRAFT"
    case merged = "MERGED"
    case closed = "CLOSED"
}

// MARK: - Mergeable State

public enum MergeableState: String, Codable, Sendable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

public enum MergeStateStatus: String, Codable, Sendable {
    case clean = "CLEAN"
    case dirty = "DIRTY"
    case blocked = "BLOCKED"
    case behind = "BEHIND"
    case unstable = "UNSTABLE"
    case hasHooks = "HAS_HOOKS"
    case unknown = "UNKNOWN"
}

// MARK: - Merge Strategy

public enum MergeStrategy: String, Codable, Sendable, CaseIterable {
    case squash
    case merge
    case rebase

    public var displayName: String {
        switch self {
        case .squash: "Squash and merge"
        case .merge: "Merge commit"
        case .rebase: "Rebase and merge"
        }
    }

    public var cliFlag: String {
        switch self {
        case .squash: "--squash"
        case .merge: "--merge"
        case .rebase: "--rebase"
        }
    }
}

// MARK: - Review Decision

public enum ReviewDecision: String, Codable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case pending = "REVIEW_REQUIRED"
    case none = ""
}

// MARK: - Check Summary

public struct CheckSummary: Codable, Sendable, Equatable {
    public var passed: Int
    public var failed: Int
    public var pending: Int

    public init(passed: Int = 0, failed: Int = 0, pending: Int = 0) {
        self.passed = passed
        self.failed = failed
        self.pending = pending
    }

    public var total: Int { passed + failed + pending }
    public var allPassed: Bool { failed == 0 && pending == 0 && passed > 0 }
    public var hasFailed: Bool { failed > 0 }
}

// MARK: - Check Run (individual check detail)

public struct CheckRun: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var status: CheckStatus
    public var detailsURL: String?

    public init(name: String, status: CheckStatus, detailsURL: String? = nil) {
        // Use name + status for uniqueness — CI matrix builds produce multiple
        // runs with the same name but different statuses
        self.id = "\(name)-\(status.rawValue)"
        self.name = name
        self.status = status
        self.detailsURL = detailsURL
    }
}

public enum CheckStatus: String, Codable, Sendable {
    case passed
    case failed
    case pending

    public var label: String {
        switch self {
        case .passed: "Passed"
        case .failed: "Failed"
        case .pending: "Pending"
        }
    }
}

// MARK: - PR Detail (lazy-loaded)

public struct PRDetail: Codable, Sendable {
    public var body: String
    public var reviews: [PRReview]
    public var comments: [PRComment]
    public var files: [PRFileChange]
    public var checks: CheckSummary
    public var checkRuns: [CheckRun]
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
        body: String = "",
        reviews: [PRReview] = [],
        comments: [PRComment] = [],
        files: [PRFileChange] = [],
        checks: CheckSummary = CheckSummary(),
        checkRuns: [CheckRun] = [],
        reviewDecision: ReviewDecision = .none,
        headBranch: String = "",
        baseBranch: String = "",
        additions: Int = 0,
        deletions: Int = 0,
        changedFiles: Int = 0,
        mergeable: MergeableState? = nil,
        mergeStateStatus: MergeStateStatus? = nil,
        autoMergeEnabled: Bool = false
    ) {
        self.body = body
        self.reviews = reviews
        self.comments = comments
        self.files = files
        self.checks = checks
        self.checkRuns = checkRuns
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

public struct PRReview: Identifiable, Codable, Sendable {
    public let id: String
    public var author: String
    public var state: String
    public var body: String
    public var submittedAt: Date?

    public init(id: String, author: String, state: String, body: String = "", submittedAt: Date? = nil) {
        self.id = id
        self.author = author
        self.state = state
        self.body = body
        self.submittedAt = submittedAt
    }
}

public struct PRComment: Identifiable, Codable, Sendable {
    public let id: String
    public var author: String
    public var body: String
    public var path: String?
    public var line: Int?
    public var createdAt: Date

    public init(id: String, author: String, body: String, path: String? = nil, line: Int? = nil, createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.body = body
        self.path = path
        self.line = line
        self.createdAt = createdAt
    }
}

public struct PRFileChange: Identifiable, Codable, Sendable {
    public var id: String { path }
    public var path: String
    public var additions: Int
    public var deletions: Int
    public var patch: String?

    public init(path: String, additions: Int = 0, deletions: Int = 0, patch: String? = nil) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }
}
