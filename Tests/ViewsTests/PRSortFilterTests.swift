import Foundation
import Testing

@testable import Models
@testable import Views

// MARK: - PRAgeBucket Tests

@Test func ageBucketAnyMatchesEverything() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "backend-api",
        createdAt: Date().addingTimeInterval(-86400 * 60)
    )
    var filter = PRFilterState()
    filter.ageBucket = .any
    #expect(filter.matches(pr))
}

@Test func ageBucketLast24hFiltersOldPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 2)
    )
    let newPR = PullRequest(
        number: 2, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-3600)
    )
    var filter = PRFilterState()
    filter.ageBucket = .last24h
    #expect(!filter.matches(oldPR))
    #expect(filter.matches(newPR))
}

@Test func ageBucketLast7dFiltersOlderPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 10)
    )
    let recentPR = PullRequest(
        number: 2, title: "Recent", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 3)
    )
    var filter = PRFilterState()
    filter.ageBucket = .last7d
    #expect(!filter.matches(oldPR))
    #expect(filter.matches(recentPR))
}

@Test func ageBucketLast30dFiltersOlderPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 45)
    )
    let recentPR = PullRequest(
        number: 2, title: "Recent", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 15)
    )
    var filter = PRFilterState()
    filter.ageBucket = .last30d
    #expect(!filter.matches(oldPR))
    #expect(filter.matches(recentPR))
}

@Test func ageBucketOlderThan30dFiltersRecentPRs() {
    let oldPR = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 45)
    )
    let recentPR = PullRequest(
        number: 2, title: "Recent", state: .open, headBranch: "f", baseBranch: "main",
        author: "bob", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 5)
    )
    var filter = PRFilterState()
    filter.ageBucket = .olderThan30d
    #expect(filter.matches(oldPR))
    #expect(!filter.matches(recentPR))
}

// MARK: - Repo & Author Filter Tests

@Test func repoFilterMatchesExactRepo() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "owner/backend-api"
    )
    var filter = PRFilterState()
    filter.repo = "owner/backend-api"
    #expect(filter.matches(pr))
    filter.repo = "owner/web-app"
    #expect(!filter.matches(pr))
}

@Test func authorFilterMatchesExactAuthor() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r"
    )
    var filter = PRFilterState()
    filter.author = "alice"
    #expect(filter.matches(pr))
    filter.author = "bob"
    #expect(!filter.matches(pr))
}

@Test func nilRepoAndAuthorMatchAll() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r"
    )
    let filter = PRFilterState()
    #expect(filter.repo == nil)
    #expect(filter.author == nil)
    #expect(filter.matches(pr))
}

// MARK: - Checks Filter Tests

@Test func checksFilterMatchesByStatus() {
    let passingPR = PullRequest(
        number: 1, title: "Pass", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0)
    )
    let failingPR = PullRequest(
        number: 2, title: "Fail", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        checks: CheckSummary(passed: 3, failed: 2, pending: 0)
    )
    let pendingPR = PullRequest(
        number: 3, title: "Pending", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        checks: CheckSummary(passed: 0, failed: 0, pending: 3)
    )
    var filter = PRFilterState()

    filter.checks = .passed
    #expect(filter.matches(passingPR))
    #expect(!filter.matches(failingPR))
    #expect(!filter.matches(pendingPR))

    filter.checks = .failed
    #expect(!filter.matches(passingPR))
    #expect(filter.matches(failingPR))
    #expect(!filter.matches(pendingPR))

    filter.checks = .pending
    #expect(!filter.matches(passingPR))
    #expect(!filter.matches(failingPR))
    #expect(filter.matches(pendingPR))
}

// MARK: - Review & Merge Filter Tests

@Test func reviewFilterMatchesByDecision() {
    let approvedPR = PullRequest(
        number: 1, title: "Approved", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .approved
    )
    var filter = PRFilterState()
    filter.review = .approved
    #expect(filter.matches(approvedPR))
    filter.review = .changesRequested
    #expect(!filter.matches(approvedPR))
}

@Test func mergeFilterMatchesClean() {
    let cleanPR = PullRequest(
        number: 1, title: "Clean", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", mergeStateStatus: .clean
    )
    var filter = PRFilterState()
    filter.mergeFilter = .clean
    #expect(filter.matches(cleanPR))
    filter.mergeFilter = .blocked
    #expect(!filter.matches(cleanPR))
}

@Test func mergeFilterConflictsMatchesBothMergeableAndStatus() {
    let conflictingPR = PullRequest(
        number: 1, title: "Conflicts", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", mergeable: .conflicting
    )
    let dirtyPR = PullRequest(
        number: 2, title: "Dirty", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", mergeStateStatus: .dirty
    )
    var filter = PRFilterState()
    filter.mergeFilter = .conflicts
    #expect(filter.matches(conflictingPR))
    #expect(filter.matches(dirtyPR))
}

// MARK: - Combined (AND) Filter Tests

@Test func multipleFiltersApplyAsAND() {
    let pr = PullRequest(
        number: 1, title: "Test", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "owner/backend-api",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .approved
    )
    var filter = PRFilterState()
    filter.repo = "owner/backend-api"
    filter.author = "alice"
    #expect(filter.matches(pr))

    filter.author = "bob"
    #expect(!filter.matches(pr))
}

// MARK: - isActive Tests

@Test func isActiveReturnsFalseForDefaultFilter() {
    let filter = PRFilterState()
    #expect(!filter.isActive)
}

@Test func isActiveReturnsTrueWhenAnyFilterSet() {
    var filter = PRFilterState()
    filter.repo = "r"
    #expect(filter.isActive)
}

// MARK: - Sorting Tests

@Test func sortByAgeAscendingReturnsOldestFirst() {
    let old = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 10)
    )
    let new = PullRequest(
        number: 2, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-3600)
    )
    let sorted = sortPRs([new, old], by: .age, order: .ascending)
    #expect(sorted[0].number == 1)
    #expect(sorted[1].number == 2)
}

@Test func sortByAgeDescendingReturnsNewestFirst() {
    let old = PullRequest(
        number: 1, title: "Old", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-86400 * 10)
    )
    let new = PullRequest(
        number: 2, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r",
        createdAt: Date().addingTimeInterval(-3600)
    )
    let sorted = sortPRs([old, new], by: .age, order: .descending)
    #expect(sorted[0].number == 2)
    #expect(sorted[1].number == 1)
}

@Test func sortByRepoAlphabetical() {
    let prA = PullRequest(
        number: 1, title: "A", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "z-repo"
    )
    let prB = PullRequest(
        number: 2, title: "B", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "a-repo"
    )
    let sorted = sortPRs([prA, prB], by: .repo, order: .ascending)
    #expect(sorted[0].number == 2)
    #expect(sorted[1].number == 1)
}

@Test func sortByAuthorAlphabetical() {
    let prA = PullRequest(
        number: 1, title: "A", state: .open, headBranch: "f", baseBranch: "main",
        author: "zara", repo: "r"
    )
    let prB = PullRequest(
        number: 2, title: "B", state: .open, headBranch: "f", baseBranch: "main",
        author: "alice", repo: "r"
    )
    let sorted = sortPRs([prA, prB], by: .author, order: .ascending)
    #expect(sorted[0].number == 2)
    #expect(sorted[1].number == 1)
}

@Test func sortByReviewPutsApprovedFirst() {
    let approved = PullRequest(
        number: 1, title: "A", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .approved
    )
    let changes = PullRequest(
        number: 2, title: "B", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .changesRequested
    )
    let pending = PullRequest(
        number: 3, title: "C", state: .open, headBranch: "f", baseBranch: "main",
        author: "a", repo: "r", reviewDecision: .pending
    )
    let sorted = sortPRs([changes, pending, approved], by: .review, order: .ascending)
    #expect(sorted[0].number == 1)  // approved
    #expect(sorted[1].number == 3)  // pending
    #expect(sorted[2].number == 2)  // changes
}

// MARK: - assigneeSortKey

@Test func assigneeSortKeyEmpty() {
    let pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    #expect(pr.assigneeSortKey == 0)
}

@Test func assigneeSortKeyCount() {
    var pr = PullRequest(
        number: 1, title: "t", state: .open,
        headBranch: "h", baseBranch: "m", author: "a", repo: "r"
    )
    pr.assignees = ["alice", "bob", "carol"]
    #expect(pr.assigneeSortKey == 3)
}
