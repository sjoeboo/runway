import Foundation
import Models
import Testing

@testable import Persistence

@Test func createAndFetchSession() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test-session", path: "/tmp/project")
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched != nil)
    #expect(fetched?.title == "test-session")
    #expect(fetched?.path == "/tmp/project")
    #expect(fetched?.tool == .claude)
}

@Test func updateSessionStatus() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test", path: "/tmp")
    try db.saveSession(session)

    try db.updateSessionStatus(id: session.id, status: .running)
    let updated = try db.session(id: session.id)
    #expect(updated?.status == .running)
}

@Test func deleteSession() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test", path: "/tmp")
    try db.saveSession(session)

    try db.deleteSession(id: session.id)
    let fetched = try db.session(id: session.id)
    #expect(fetched == nil)
}

@Test func projectCRUD() throws {
    let db = try Database(inMemory: true)

    let project = Project(name: "my-project", path: "/code/project")
    try db.saveProject(project)

    let projects = try db.allProjects()
    #expect(projects.count == 1)
    #expect(projects.first?.name == "my-project")
}

@Test func sessionSortOrderPersistence() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test", path: "/tmp", sortOrder: 7)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.sortOrder == 7)
}

@Test func updateSessionSortOrder() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test", path: "/tmp", sortOrder: 0)
    try db.saveSession(session)

    try db.updateSessionSortOrder(id: session.id, sortOrder: 5)
    let updated = try db.session(id: session.id)
    #expect(updated?.sortOrder == 5)
}

@Test func allSessionsOrderedBySortOrder() throws {
    let db = try Database(inMemory: true)

    // Insert sessions with non-sequential sort orders
    let s1 = Session(title: "first", path: "/tmp", sortOrder: 10)
    let s2 = Session(title: "second", path: "/tmp", sortOrder: 5)
    let s3 = Session(title: "third", path: "/tmp", sortOrder: 20)
    try db.saveSession(s1)
    try db.saveSession(s2)
    try db.saveSession(s3)

    let sessions = try db.allSessions()
    #expect(sessions.count == 3)
    #expect(sessions[0].title == "second")  // sortOrder 5
    #expect(sessions[1].title == "first")  // sortOrder 10
    #expect(sessions[2].title == "third")  // sortOrder 20
}

@Test func sessionPRNumberPersistence() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "review", path: "/tmp", prNumber: 42)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.prNumber == 42)
}

@Test func sessionPRNumberNilPersistence() throws {
    let db = try Database(inMemory: true)

    let session = Session(title: "test", path: "/tmp")
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.prNumber == nil)
}

@Test func saveAndFetchSessionEvents() throws {
    let db = try Database(inMemory: true)
    let event = SessionEvent(sessionID: "test-session", eventType: "UserPromptSubmit", prompt: "Fix the bug")
    try db.saveEvent(event)

    let events = try db.events(forSessionID: "test-session")
    #expect(events.count == 1)
    #expect(events.first?.prompt == "Fix the bug")
    #expect(events.first?.eventType == "UserPromptSubmit")
}

@Test func sessionEventsCapAtThousand() throws {
    let db = try Database(inMemory: true)
    for i in 0..<1005 {
        let event = SessionEvent(sessionID: "s1", eventType: "UserPromptSubmit", prompt: "Prompt \(i)")
        try db.saveEvent(event)
    }
    let events = try db.events(forSessionID: "s1", limit: 2000)
    #expect(events.count <= 1000)
}

@Test func sessionIssueNumberPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "Fix issue", path: "/tmp", issueNumber: 42)
    try db.saveSession(session)

    let loaded = try db.allSessions()
    #expect(loaded.first?.issueNumber == 42)
}

@Test func updateSessionIssueNumber() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "Test", path: "/tmp")
    try db.saveSession(session)

    try db.updateSessionIssueNumber(id: session.id, issueNumber: 99)
    let loaded = try db.allSessions()
    #expect(loaded.first?.issueNumber == 99)
}

@Test func sessionEventsOrderedByCreatedAtDesc() throws {
    let db = try Database(inMemory: true)
    let e1 = SessionEvent(sessionID: "s1", eventType: "SessionStart", createdAt: Date(timeIntervalSince1970: 100))
    let e2 = SessionEvent(sessionID: "s1", eventType: "UserPromptSubmit", createdAt: Date(timeIntervalSince1970: 200))
    try db.saveEvent(e1)
    try db.saveEvent(e2)

    let events = try db.events(forSessionID: "s1")
    #expect(events.count == 2)
    #expect(events.first?.eventType == "UserPromptSubmit")  // most recent first
}

@Test func prCacheRoundTripsNewFields() throws {
    let db = try Database(inMemory: true)

    var pr = PullRequest(
        number: 99, title: "Test", state: .open, headBranch: "feature", baseBranch: "main",
        author: "alice", repo: "owner/repo"
    )
    pr.enrichedAt = Date()
    pr.origin = [.mine, .reviewRequested]

    try db.cachePR(pr)

    let cached = try db.cachedPRs(maxAge: 3600)
    #expect(cached.count == 1)
    #expect(cached.first?.enrichedAt != nil)
    #expect(cached.first?.origin == [.mine, .reviewRequested])
}
