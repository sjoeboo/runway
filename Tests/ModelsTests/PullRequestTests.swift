import Foundation
import Testing

@testable import Models

// MARK: - PullRequest

@Test func pullRequestIDFormat() {
    let pr = PullRequest(
        number: 42, title: "Fix bug", state: .open, headBranch: "fix/bug", baseBranch: "main", author: "alice", repo: "owner/repo")
    #expect(pr.id == "owner/repo#42")
}

@Test func pullRequestDefaults() {
    let pr = PullRequest(number: 1, title: "Test", state: .open, headBranch: "feature", baseBranch: "main", author: "me", repo: "r")
    #expect(pr.isDraft == false)
    #expect(pr.additions == 0)
    #expect(pr.deletions == 0)
    #expect(pr.changedFiles == 0)
    #expect(pr.url.isEmpty)
    #expect(pr.reviewDecision == .pending)
}

// MARK: - PRState

@Test func prStateRawValues() {
    #expect(PRState.open.rawValue == "OPEN")
    #expect(PRState.draft.rawValue == "DRAFT")
    #expect(PRState.merged.rawValue == "MERGED")
    #expect(PRState.closed.rawValue == "CLOSED")
}

// MARK: - ReviewDecision

@Test func reviewDecisionRawValues() {
    #expect(ReviewDecision.approved.rawValue == "APPROVED")
    #expect(ReviewDecision.changesRequested.rawValue == "CHANGES_REQUESTED")
    #expect(ReviewDecision.pending.rawValue == "REVIEW_REQUIRED")
    #expect(ReviewDecision.none.rawValue.isEmpty)
}

// MARK: - CheckSummary

@Test func checkSummaryTotal() {
    let summary = CheckSummary(passed: 5, failed: 2, pending: 1)
    #expect(summary.total == 8)
}

@Test func checkSummaryAllPassed() {
    let allGood = CheckSummary(passed: 3, failed: 0, pending: 0)
    #expect(allGood.allPassed == true)

    let withFailure = CheckSummary(passed: 2, failed: 1, pending: 0)
    #expect(withFailure.allPassed == false)

    let withPending = CheckSummary(passed: 2, failed: 0, pending: 1)
    #expect(withPending.allPassed == false)

    let empty = CheckSummary()
    #expect(empty.allPassed == false)
}

@Test func checkSummaryHasFailed() {
    let failing = CheckSummary(passed: 1, failed: 1, pending: 0)
    #expect(failing.hasFailed == true)

    let passing = CheckSummary(passed: 3, failed: 0, pending: 0)
    #expect(passing.hasFailed == false)
}

// MARK: - PRReview

@Test func prReviewProperties() {
    let review = PRReview(id: "r1", author: "alice", state: "APPROVED", body: "LGTM")
    #expect(review.id == "r1")
    #expect(review.author == "alice")
    #expect(review.state == "APPROVED")
    #expect(review.body == "LGTM")
    #expect(review.submittedAt == nil)
}

// MARK: - PRComment

@Test func prCommentProperties() {
    let comment = PRComment(id: "c1", author: "bob", body: "Needs fix", path: "main.swift", line: 42)
    #expect(comment.id == "c1")
    #expect(comment.path == "main.swift")
    #expect(comment.line == 42)
}

@Test func prCommentDefaults() {
    let comment = PRComment(id: "c2", author: "x", body: "Hi")
    #expect(comment.path == nil)
    #expect(comment.line == nil)
}

// MARK: - PRFileChange

@Test func prFileChangeID() {
    let file = PRFileChange(path: "src/main.swift", additions: 10, deletions: 5, patch: "@@ -1,5 +1,10 @@")
    #expect(file.id == "src/main.swift")
    #expect(file.patch != nil)
}
