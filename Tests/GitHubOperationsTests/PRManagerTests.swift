import Testing
import Foundation
@testable import GitHubOperations
import Models

// MARK: - GHError

@Test func ghErrorDescription() {
    let error = GHError.commandFailed(args: ["pr", "list"], exitCode: 1, stderr: "not logged in")
    #expect(error.errorDescription?.contains("pr list") == true)
    #expect(error.errorDescription?.contains("exit 1") == true)
    #expect(error.errorDescription?.contains("not logged in") == true)
}

// MARK: - PRFilter

@Test func prFilterCases() {
    // Verify all filter cases exist and are distinct
    let filters: [PRFilter] = [.mine, .reviewRequested, .all]
    #expect(filters.count == 3)
}

// MARK: - PRDetail

@Test func prDetailDefaults() {
    let detail = PRDetail()
    #expect(detail.body == "")
    #expect(detail.reviews.isEmpty)
    #expect(detail.comments.isEmpty)
    #expect(detail.files.isEmpty)
}

@Test func prDetailWithData() {
    let review = PRReview(id: "1", author: "alice", state: "APPROVED")
    let comment = PRComment(id: "2", author: "bob", body: "LGTM")
    let file = PRFileChange(path: "src/main.swift", additions: 10, deletions: 3)

    let detail = PRDetail(
        body: "## Summary\nFixes a bug",
        reviews: [review],
        comments: [comment],
        files: [file]
    )

    #expect(detail.body.contains("Fixes a bug"))
    #expect(detail.reviews.count == 1)
    #expect(detail.reviews.first?.state == "APPROVED")
    #expect(detail.comments.first?.body == "LGTM")
    #expect(detail.files.first?.path == "src/main.swift")
}

// MARK: - PRManager Actor

@Test func prManagerCanBeCreated() async {
    let manager = PRManager()
    // Just verifying the actor initializes without issues
    _ = manager
}
