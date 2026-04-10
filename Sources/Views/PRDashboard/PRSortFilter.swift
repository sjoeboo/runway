import Foundation
import Models

// MARK: - Sort Types

public enum PRSortField: String, CaseIterable, Sendable {
    case title
    case repo
    case author
    case age
    case checks
    case review
    case mergeStatus

    public var label: String {
        switch self {
        case .title: "Title"
        case .repo: "Repo"
        case .author: "Author"
        case .age: "Age"
        case .checks: "Checks"
        case .review: "Review"
        case .mergeStatus: "Merge"
        }
    }
}

public enum PRSortOrder: String, Sendable {
    case ascending
    case descending
}

// MARK: - Age Bucket

public enum PRAgeBucket: String, CaseIterable, Sendable {
    case any = "Any"
    case last24h = "Last 24h"
    case last7d = "Last 7 days"
    case last30d = "Last 30 days"
    case olderThan30d = "Older than 30 days"

    func matches(createdAt: Date) -> Bool {
        let age = Date().timeIntervalSince(createdAt)
        switch self {
        case .any: return true
        case .last24h: return age <= 86400
        case .last7d: return age <= 86400 * 7
        case .last30d: return age <= 86400 * 30
        case .olderThan30d: return age > 86400 * 30
        }
    }
}

// MARK: - Merge Filter

public enum PRMergeFilter: String, CaseIterable, Sendable {
    case clean = "Clean"
    case conflicts = "Conflicts"
    case behind = "Behind"
    case blocked = "Blocked"

    public func matches(mergeable: MergeableState?, mergeStateStatus: MergeStateStatus?) -> Bool {
        switch self {
        case .clean:
            return mergeStateStatus == .clean || mergeStateStatus == .hasHooks
        case .conflicts:
            return mergeable == .conflicting || mergeStateStatus == .dirty
        case .behind:
            return mergeStateStatus == .behind
        case .blocked:
            return mergeStateStatus == .blocked
        }
    }
}

// MARK: - Filter State

public struct PRFilterState: Sendable {
    public var repo: String?
    public var author: String?
    public var ageBucket: PRAgeBucket = .any
    public var checks: CheckStatus?
    public var review: ReviewDecision?
    public var mergeFilter: PRMergeFilter?

    public init() {}

    public var isActive: Bool {
        repo != nil || author != nil || ageBucket != .any
            || checks != nil || review != nil || mergeFilter != nil
    }

    public func matches(_ pr: PullRequest) -> Bool {
        if let repo, pr.repo != repo { return false }
        if let author, pr.author != author { return false }
        if !ageBucket.matches(createdAt: pr.createdAt) { return false }
        if let checks {
            switch checks {
            case .passed: if !pr.checks.allPassed { return false }
            case .failed: if !pr.checks.hasFailed { return false }
            case .pending:
                if pr.checks.pending == 0 || pr.checks.hasFailed { return false }
            }
        }
        if let review, pr.reviewDecision != review { return false }
        if let mergeFilter {
            if !mergeFilter.matches(mergeable: pr.mergeable, mergeStateStatus: pr.mergeStateStatus) {
                return false
            }
        }
        return true
    }

    public mutating func clear() {
        repo = nil
        author = nil
        ageBucket = .any
        checks = nil
        review = nil
        mergeFilter = nil
    }
}

// MARK: - Sorting

/// Sort an array of PRs by the given field and order.
public func sortPRs(_ prs: [PullRequest], by field: PRSortField, order: PRSortOrder) -> [PullRequest] {
    let sorted = prs.sorted { lhs, rhs in
        switch field {
        case .title:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .repo:
            return lhs.repo.localizedCaseInsensitiveCompare(rhs.repo) == .orderedAscending
        case .author:
            return lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
        case .age:
            return lhs.createdAt < rhs.createdAt
        case .checks:
            let lhsRatio = lhs.checks.total > 0 ? Double(lhs.checks.passed) / Double(lhs.checks.total) : 0
            let rhsRatio = rhs.checks.total > 0 ? Double(rhs.checks.passed) / Double(rhs.checks.total) : 0
            if lhsRatio != rhsRatio { return lhsRatio < rhsRatio }
            return lhs.checks.total < rhs.checks.total
        case .review:
            return reviewSortOrder(lhs.reviewDecision) < reviewSortOrder(rhs.reviewDecision)
        case .mergeStatus:
            return mergeSortOrder(lhs.mergeStateStatus) < mergeSortOrder(rhs.mergeStateStatus)
        }
    }
    return order == .ascending ? sorted : sorted.reversed()
}

private func reviewSortOrder(_ decision: ReviewDecision) -> Int {
    switch decision {
    case .approved: 0
    case .pending: 1
    case .none: 2
    case .changesRequested: 3
    }
}

private func mergeSortOrder(_ status: MergeStateStatus?) -> Int {
    switch status {
    case .clean, .hasHooks: 0
    case .behind: 1
    case .unstable: 2
    case .dirty: 3
    case .blocked: 4
    case .unknown, .none: 5
    }
}
