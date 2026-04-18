import Foundation
import Testing

@testable import Models
@testable import Views

// MARK: - PR Grouping Logic Tests

@Test func draftPRAlwaysGroupedAsDraft() {
    let pr = PullRequest(
        number: 1, title: "WIP", state: .draft, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r", isDraft: true,
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .approved
    )
    #expect(prGroup(for: pr) == .drafts)
}

@Test func failedChecksGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 2, title: "Broken", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 8, failed: 2, pending: 0),
        reviewDecision: .approved
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func changesRequestedGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 3, title: "Fix", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .changesRequested
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func conflictingPRGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 4, title: "Conflict", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .approved,
        mergeable: .conflicting
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func blockedPRGroupedAsNeedsAttention() {
    let pr = PullRequest(
        number: 5, title: "Blocked", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .approved,
        mergeStateStatus: .blocked
    )
    #expect(prGroup(for: pr) == .needsAttention)
}

@Test func pendingChecksGroupedAsInProgress() {
    let pr = PullRequest(
        number: 6, title: "Running", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 3, failed: 0, pending: 5),
        reviewDecision: .pending
    )
    #expect(prGroup(for: pr) == .inProgress)
}

@Test func unenrichedPRGroupedAsInProgress() {
    let pr = PullRequest(
        number: 7, title: "New", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(),
        reviewDecision: .pending,
        enrichedAt: nil
    )
    #expect(prGroup(for: pr) == .inProgress)
}

@Test func allPassedPendingReviewGroupedAsWaitingForReview() {
    let pr = PullRequest(
        number: 8, title: "Ready for eyes", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .pending
    )
    #expect(prGroup(for: pr) == .waitingForReview)
}

@Test func noChecksAndPendingReviewGroupedAsWaitingForReview() {
    var pr = PullRequest(
        number: 9, title: "No CI", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(),
        reviewDecision: .pending
    )
    pr.enrichedAt = Date()  // enriched but no checks configured
    #expect(prGroup(for: pr) == .waitingForReview)
}

@Test func reviewNoneGroupedAsWaitingForReview() {
    let pr = PullRequest(
        number: 10, title: "No reviewers", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 5, failed: 0, pending: 0),
        reviewDecision: .none
    )
    #expect(prGroup(for: pr) == .waitingForReview)
}

@Test func approvedAndPassingGroupedAsReady() {
    let pr = PullRequest(
        number: 11, title: "Ship it", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .approved
    )
    #expect(prGroup(for: pr) == .ready)
}

@Test func approvedAndBehindStillGroupedAsReady() {
    let pr = PullRequest(
        number: 12, title: "Behind but ok", state: .open, headBranch: "f", baseBranch: "main",
        author: "me", repo: "r",
        checks: CheckSummary(passed: 10, failed: 0, pending: 0),
        reviewDecision: .approved,
        mergeStateStatus: .behind
    )
    #expect(prGroup(for: pr) == .ready)
}

// MARK: - PRTab.assigned

@Test func prTabAssignedCaseExists() {
    let tabs = PRTab.allCases
    #expect(tabs.contains(.assigned))
    #expect(tabs.count == 4)
}

@Test func prTabAssignedRawValue() {
    #expect(PRTab.assigned.rawValue == "Assigned")
}
