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

// MARK: - PRFilter.assigned

@Test func prFilterAssignedCase() {
    let filters: [PRFilter] = [.mine, .reviewRequested, .assigned, .all]
    #expect(filters.count == 4)
}

@Test func buildSearchArgsForAssigned() {
    let args = PRManager.buildSearchArgs(filter: .assigned)
    #expect(args.contains("--assignee"))
    #expect(args.contains("@me"))
}

@Test func buildSearchArgsForMine() {
    let args = PRManager.buildSearchArgs(filter: .mine)
    #expect(args.contains("--author"))
    #expect(args.contains("@me"))
    #expect(!args.contains("--assignee"))
}

@Test func buildListArgsForAssigned() {
    let args = PRManager.buildListArgs(repo: "owner/repo", filter: .assigned)
    #expect(args.contains("owner/repo"))
    #expect(args.contains("--assignee"))
    #expect(args.contains("@me"))
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

// MARK: - Collaborator

@Test func collaboratorIdEqualsLogin() {
    let collab = Collaborator(login: "alice", name: "Alice B")
    #expect(collab.id == "alice")
}

@Test func collaboratorEqualityUsesAllFields() {
    // Same login + same name — equal and same hash
    let a1 = Collaborator(login: "alice", name: "Alice")
    let a2 = Collaborator(login: "alice", name: "Alice")
    #expect(a1 == a2)
    #expect(a1.hashValue == a2.hashValue)
    // Same login, different name — not equal (synthesized Hashable uses all fields)
    let a3 = Collaborator(login: "alice", name: nil)
    #expect(a1 != a3)
}

@Test func collaboratorDecodable() throws {
    let json = Data(#"{"login":"alice","name":"Alice Bailey"}"#.utf8)
    let collab = try JSONDecoder().decode(Collaborator.self, from: json)
    #expect(collab.login == "alice")
    #expect(collab.name == "Alice Bailey")
}

@Test func collaboratorDecodableWithNullName() throws {
    let json = Data(#"{"login":"bob","name":null}"#.utf8)
    let collab = try JSONDecoder().decode(Collaborator.self, from: json)
    #expect(collab.login == "bob")
    #expect(collab.name == nil)
}

// MARK: - whoami

@Test func whoamiReturnsSeededValue() async {
    let manager = PRManager()
    await manager.seedWhoamiForTest(host: "github.com", login: "alice")
    let result = await manager.cachedWhoami(host: "github.com")
    #expect(result == "alice")
}

@Test func whoamiReturnsNilForUnseededHost() async {
    let manager = PRManager()
    let result = await manager.cachedWhoami(host: "github.com")
    #expect(result == nil)
}

@Test func whoamiDistinctAcrossHosts() async {
    let manager = PRManager()
    await manager.seedWhoamiForTest(host: "github.com", login: "alice")
    await manager.seedWhoamiForTest(host: "ghe.spotify.net", login: "alice-s")
    #expect(await manager.cachedWhoami(host: "github.com") == "alice")
    #expect(await manager.cachedWhoami(host: "ghe.spotify.net") == "alice-s")
}

// MARK: - collaborators parsing

@Test func parseCollaboratorsPages() throws {
    // --paginate --slurp returns [[...], [...]]
    let json = """
        [
          [{"login":"alice","name":"Alice Bailey"}, {"login":"bob","name":null}],
          [{"login":"carol","name":"Carol"}, {"login":"alice","name":"Alice Bailey"}]
        ]
        """
    let collabs = try PRManager.parseCollaborators(json)
    // Dedup by login; preserve first-occurrence order
    #expect(collabs.map(\.login) == ["alice", "bob", "carol"])
    #expect(collabs[0].name == "Alice Bailey")
    #expect(collabs[1].name == nil)
}

@Test func parseCollaboratorsEmpty() throws {
    let collabs = try PRManager.parseCollaborators("[]")
    #expect(collabs.isEmpty)
}

@Test func collaboratorsCacheSeeded() async {
    let manager = PRManager()
    let seed = [Collaborator(login: "alice", name: "Alice")]
    await manager.seedCollaboratorsForTest(repo: "owner/repo", collabs: seed)
    let cached = await manager.cachedCollaborators(for: "owner/repo")
    #expect(cached?.map(\.login) == ["alice"])
}

// MARK: - Assignee decoding

@Test func enrichResultHasAssignees() {
    let result = PREnrichResult()
    #expect(result.assignees.isEmpty)
}

@Test func enrichResponseDecodesAssignees() throws {
    let json = """
        {
          "statusCheckRollup": [],
          "assignees": [{"login":"alice","name":"Alice"}, {"login":"bob","name":null}]
        }
        """
    let data = Data(json.utf8)
    let result = try PRManager.parseEnrichResponseForTest(data: data, excludeAuthor: nil)
    #expect(result.assignees == ["alice", "bob"])
}

@Test func enrichResponseWithNoAssignees() throws {
    let json = #"{"statusCheckRollup":[]}"#
    let data = Data(json.utf8)
    let result = try PRManager.parseEnrichResponseForTest(data: data, excludeAuthor: nil)
    #expect(result.assignees.isEmpty)
}

// MARK: - assign / unassign args

@Test func buildAssignArgsAdd() {
    let args = PRManager.buildAssignArgs(
        repo: "owner/repo", number: 42, logins: ["alice", "bob"], add: true
    )
    #expect(args == ["pr", "edit", "42", "--repo", "owner/repo", "--add-assignee", "alice,bob"])
}

@Test func buildAssignArgsRemove() {
    let args = PRManager.buildAssignArgs(
        repo: "owner/repo", number: 42, logins: ["alice"], add: false
    )
    #expect(args == ["pr", "edit", "42", "--repo", "owner/repo", "--remove-assignee", "alice"])
}

@Test func buildAssignArgsSingle() {
    let args = PRManager.buildAssignArgs(
        repo: "o/r", number: 1, logins: ["me"], add: true
    )
    #expect(args.last == "me")
    #expect(args.contains("--add-assignee"))
}
