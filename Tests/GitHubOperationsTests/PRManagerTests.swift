import Foundation
import Models
import Testing

@testable import GitHubOperations

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
    #expect(detail.body.isEmpty)
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

// MARK: - MergeStrategy

@Test func mergeStrategyCliFlags() {
    #expect(MergeStrategy.squash.cliFlag == "--squash")
    #expect(MergeStrategy.merge.cliFlag == "--merge")
    #expect(MergeStrategy.rebase.cliFlag == "--rebase")
}

@Test func mergeStrategyDisplayNames() {
    #expect(MergeStrategy.squash.displayName == "Squash and merge")
    #expect(MergeStrategy.merge.displayName == "Merge commit")
    #expect(MergeStrategy.rebase.displayName == "Rebase and merge")
}

@Test func mergeStrategyCaseIterable() {
    #expect(MergeStrategy.allCases.count == 3)
}

// MARK: - PRResolveError

@Test func prResolveErrorNotFoundDescription() {
    let error = PRResolveError.notFound(number: 247, repo: "owner/repo")
    #expect(error.errorDescription?.contains("247") == true)
    #expect(error.errorDescription?.contains("owner/repo") == true)
}

@Test func prResolveErrorNoProjectDescription() {
    let error = PRResolveError.noProject
    let description = error.errorDescription
    #expect(description != nil)
    #expect(description?.isEmpty == false)
}

// MARK: - PRManager Actor

@Test func prManagerCanBeCreated() async {
    let manager = PRManager()
    // Just verifying the actor initializes without issues
    _ = manager
}

// MARK: - PREnrichResult

@Test func prEnrichResultCommentDefaults() {
    let result = PREnrichResult()
    #expect(result.commentsSinceLastCommit == 0)
    #expect(result.lastCommitDate == nil)
}

// MARK: - PROrigin Integration

@Test func prOriginSetOperations() {
    // Verify Set<PROrigin> works as expected for dedup logic
    var origins: Set<PROrigin> = [.mine]
    origins.insert(.reviewRequested)
    #expect(origins.count == 2)
    #expect(origins.contains(.mine))
    #expect(origins.contains(.reviewRequested))
}
