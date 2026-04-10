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

// MARK: - Comparable Sort Properties

extension PullRequest {
    /// Checks pass ratio for column sorting. -1 when no checks configured.
    public var checksPassRatio: Double {
        checks.total > 0 ? Double(checks.passed) / Double(checks.total) : -1
    }

    /// Numeric rank for review decision sorting (lower = better).
    public var reviewSortRank: Int {
        switch reviewDecision {
        case .approved: 0
        case .pending: 1
        case .none: 2
        case .changesRequested: 3
        }
    }

    /// Numeric rank for merge status sorting (lower = more ready).
    public var mergeSortRank: Int {
        if mergeable == .conflicting { return 4 }
        switch mergeStateStatus {
        case .clean, .hasHooks: return 0
        case .behind: return 1
        case .unstable: return 2
        case .dirty: return 3
        case .blocked: return 5
        default: return 6
        }
    }
}

// MARK: - Column Widths

/// Resizable column widths for the PR list grid.
/// Title is always flexible (fills remaining space), so it's not stored here.
public struct PRColumnWidths: Sendable {
    public var repo: CGFloat
    public var author: CGFloat
    public var age: CGFloat
    public var checks: CGFloat
    public var review: CGFloat
    public var merge: CGFloat

    public static let defaults = PRColumnWidths(
        repo: 140, author: 100, age: 60, checks: 60, review: 80, merge: 85
    )

    public static let minimums = PRColumnWidths(
        repo: 70, author: 60, age: 45, checks: 45, review: 60, merge: 60
    )

    public static let maximums = PRColumnWidths(
        repo: 250, author: 200, age: 100, checks: 120, review: 130, merge: 140
    )

    public init(
        repo: CGFloat = 100, author: CGFloat = 70, age: CGFloat = 50,
        checks: CGFloat = 55, review: CGFloat = 55, merge: CGFloat = 65
    ) {
        self.repo = repo
        self.author = author
        self.age = age
        self.checks = checks
        self.review = review
        self.merge = merge
    }

    /// Width for a given sort field (title excluded — it's flexible).
    public func width(for field: PRSortField) -> CGFloat {
        switch field {
        case .title: 0  // not used — title is flexible
        case .repo: repo
        case .author: author
        case .age: age
        case .checks: checks
        case .review: review
        case .mergeStatus: merge
        }
    }

    /// Minimum width for a given sort field.
    public static func min(for field: PRSortField) -> CGFloat {
        Self.minimums.width(for: field)
    }

    /// Maximum width for a given sort field.
    public static func max(for field: PRSortField) -> CGFloat {
        Self.maximums.width(for: field)
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
