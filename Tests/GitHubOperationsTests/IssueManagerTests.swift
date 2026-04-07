import Foundation
import Models
import Testing

@testable import GitHubOperations

// MARK: - IssueDetail

@Test func issueDetailDefaults() {
    let detail = IssueDetail()
    #expect(detail.body.isEmpty)
    #expect(detail.comments.isEmpty)
    #expect(detail.timelineEvents.isEmpty)
    #expect(detail.labels.isEmpty)
    #expect(detail.assignees.isEmpty)
    #expect(detail.milestone == nil)
    #expect(detail.stateReason == nil)
}

@Test func issueDetailWithData() {
    let comment = IssueComment(id: "c1", author: "alice", body: "Great work!")
    let label = IssueDetailLabel(name: "bug", color: "d73a4a")
    let event = IssueTimelineEvent(id: "e1", event: "labeled", actor: "bot")

    let detail = IssueDetail(
        body: "## Description\nFixes the issue",
        comments: [comment],
        timelineEvents: [event],
        labels: [label],
        assignees: ["alice"],
        milestone: "v1.0",
        stateReason: "completed"
    )

    #expect(detail.body.contains("Fixes the issue"))
    #expect(detail.comments.count == 1)
    #expect(detail.comments.first?.author == "alice")
    #expect(detail.timelineEvents.count == 1)
    #expect(detail.labels.count == 1)
    #expect(detail.labels.first?.name == "bug")
    #expect(detail.assignees.first == "alice")
    #expect(detail.milestone == "v1.0")
    #expect(detail.stateReason == "completed")
}

// MARK: - IssueComment

@Test func issueCommentIdentifiable() {
    let date = Date(timeIntervalSince1970: 1_000_000)
    let comment = IssueComment(id: "comment-42", author: "bob", body: "LGTM", createdAt: date, updatedAt: date)
    #expect(comment.id == "comment-42")
    #expect(comment.author == "bob")
    #expect(comment.body == "LGTM")
    #expect(comment.createdAt == date)
}

// MARK: - IssueTimelineEvent

@Test func issueTimelineEventCrossReference() {
    let ref = IssueReference(type: "PullRequest", number: 101, title: "Fix the bug", url: "https://github.com/owner/repo/pull/101")
    let event = IssueTimelineEvent(
        id: "evt-1",
        event: "cross-referenced",
        actor: "alice",
        source: ref
    )

    #expect(event.event == "cross-referenced")
    #expect(event.source?.type == "PullRequest")
    #expect(event.source?.number == 101)
    #expect(event.source?.title == "Fix the bug")
    #expect(event.rename == nil)
    #expect(event.label == nil)
}

@Test func issueTimelineEventRenameVariant() {
    let rename = IssueRename(from: "Old title", to: "New title")
    let event = IssueTimelineEvent(
        id: "evt-2",
        event: "renamed",
        actor: "bob",
        rename: rename
    )

    #expect(event.event == "renamed")
    #expect(event.rename?.from == "Old title")
    #expect(event.rename?.to == "New title")
    #expect(event.source == nil)
}

@Test func issueTimelineEventLabelVariant() {
    let label = IssueDetailLabel(name: "bug", color: "d73a4a")
    let event = IssueTimelineEvent(
        id: "evt-3",
        event: "labeled",
        actor: "github-bot",
        label: label
    )

    #expect(event.event == "labeled")
    #expect(event.label?.name == "bug")
    #expect(event.label?.color == "d73a4a")
    #expect(event.assignee == nil)
}

// MARK: - IssueDetailLabel

@Test func issueDetailLabelHashable() {
    let label1 = IssueDetailLabel(name: "enhancement", color: "a2eeef")
    let label2 = IssueDetailLabel(name: "enhancement", color: "a2eeef")
    let label3 = IssueDetailLabel(name: "bug", color: "d73a4a")

    var labelSet: Set<IssueDetailLabel> = [label1, label2, label3]
    #expect(labelSet.count == 2)
    #expect(labelSet.contains(label1))
    labelSet.insert(label3)
    #expect(labelSet.count == 2)
}

// MARK: - CloseReason

@Test func closeReasonDisplayNames() {
    #expect(CloseReason.completed.displayName == "Completed")
    #expect(CloseReason.notPlanned.displayName == "Not planned")
}

@Test func closeReasonCaseIterable() {
    #expect(CloseReason.allCases.count == 2)
    #expect(CloseReason.allCases.contains(.completed))
    #expect(CloseReason.allCases.contains(.notPlanned))
}

@Test func closeReasonRawValues() {
    #expect(CloseReason.completed.rawValue == "completed")
    #expect(CloseReason.notPlanned.rawValue == "not planned")
}

// MARK: - GitHubIssue repo field

@Test func gitHubIssueHasRepoField() {
    let issue = GitHubIssue(
        number: 42,
        title: "Test issue",
        state: .open,
        author: "alice",
        repo: "owner/repo"
    )

    #expect(issue.repo == "owner/repo")
    #expect(issue.id == "owner/repo#42")
}

@Test func gitHubIssueRepoDecodingWithField() throws {
    let json = """
        {
            "id": "owner/repo#7",
            "number": 7,
            "title": "Test",
            "state": "OPEN",
            "author": "alice",
            "repo": "owner/repo",
            "labels": [],
            "assignees": [],
            "url": "https://github.com/owner/repo/issues/7",
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
        }
        """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let issue = try decoder.decode(GitHubIssue.self, from: Data(json.utf8))
    #expect(issue.repo == "owner/repo")
    #expect(issue.number == 7)
}

@Test func gitHubIssueRepoDecodingBackwardsCompat() throws {
    // Cached JSON without `repo` field — must infer from `id`
    let json = """
        {
            "id": "owner/legacy-repo#99",
            "number": 99,
            "title": "Legacy issue",
            "state": "CLOSED",
            "author": "bob",
            "labels": ["bug"],
            "assignees": [],
            "url": "https://github.com/owner/legacy-repo/issues/99",
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-02T00:00:00Z"
        }
        """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let issue = try decoder.decode(GitHubIssue.self, from: Data(json.utf8))
    #expect(issue.repo == "owner/legacy-repo")
    #expect(issue.number == 99)
    #expect(issue.state == .closed)
}

// MARK: - IssueManager Actor

@Test func issueManagerCanBeCreated() async {
    let manager = IssueManager()
    _ = manager
}
