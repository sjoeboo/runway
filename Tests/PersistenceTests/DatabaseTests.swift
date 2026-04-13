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

@Test func saveAndFetchTemplates() throws {
    let db = try Database(inMemory: true)
    let template = SessionTemplate(name: "Quick Fix", projectID: "p1", permissionMode: .acceptEdits)
    try db.saveTemplate(template)

    let all = try db.allTemplates()
    #expect(all.count == 1)
    #expect(all.first?.name == "Quick Fix")
    #expect(all.first?.permissionMode == .acceptEdits)
}

@Test func deleteTemplate() throws {
    let db = try Database(inMemory: true)
    let template = SessionTemplate(name: "Test")
    try db.saveTemplate(template)
    try db.deleteTemplate(id: template.id)

    let all = try db.allTemplates()
    #expect(all.isEmpty)
}

@Test func templatesFilteredByProject() throws {
    let db = try Database(inMemory: true)
    let t1 = SessionTemplate(name: "Global")
    let t2 = SessionTemplate(name: "Project-specific", projectID: "p1")
    try db.saveTemplate(t1)
    try db.saveTemplate(t2)

    let forP1 = try db.templates(forProjectID: "p1")
    #expect(forP1.count == 1)
    #expect(forP1.first?.name == "Project-specific")
}

@Test func sessionUseHappyPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "happy-test", path: "/tmp", useHappy: true)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.useHappy == true)
}

@Test func sessionUseHappyDefaultsFalse() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "normal", path: "/tmp")
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.useHappy == false)
}

@Test func sessionToolGeminiPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "gemini-test", path: "/tmp", tool: .gemini)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.tool == .gemini)
}

@Test func sessionToolCodexPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "codex-test", path: "/tmp", tool: .codex)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.tool == .codex)
}

// MARK: - Cost Tracking

@Test func sessionCostTrackingPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(
        title: "cost-test", path: "/tmp",
        totalCostUSD: 1.23, totalInputTokens: 50000, totalOutputTokens: 10000,
        transcriptPath: "/tmp/transcript.jsonl"
    )
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.totalCostUSD == 1.23)
    #expect(fetched?.totalInputTokens == 50000)
    #expect(fetched?.totalOutputTokens == 10000)
    #expect(fetched?.transcriptPath == "/tmp/transcript.jsonl")
}

@Test func sessionCostFieldsDefaultNil() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "no-cost", path: "/tmp")
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.totalCostUSD == nil)
    #expect(fetched?.totalInputTokens == nil)
    #expect(fetched?.totalOutputTokens == nil)
    #expect(fetched?.transcriptPath == nil)
}

// MARK: - Housekeeping

@Test func cleanStoppedSessionsRemovesOldStopped() throws {
    let db = try Database(inMemory: true)

    let old = Session(
        title: "old-stopped", path: "/tmp", status: .stopped,
        createdAt: Date(timeIntervalSinceNow: -86400 * 30),
        lastAccessedAt: Date(timeIntervalSinceNow: -86400 * 30)
    )
    let recent = Session(
        title: "recent-stopped", path: "/tmp", status: .stopped,
        createdAt: Date(), lastAccessedAt: Date()
    )
    let running = Session(
        title: "running", path: "/tmp", status: .running,
        createdAt: Date(timeIntervalSinceNow: -86400 * 30),
        lastAccessedAt: Date(timeIntervalSinceNow: -86400 * 30)
    )
    try db.saveSession(old)
    try db.saveSession(recent)
    try db.saveSession(running)

    let deleted = try db.cleanStoppedSessions(maxAge: 7 * 86400)
    #expect(deleted == 1)

    let remaining = try db.allSessions()
    #expect(remaining.count == 2)
    #expect(remaining.contains(where: { $0.title == "recent-stopped" }))
    #expect(remaining.contains(where: { $0.title == "running" }))
}

@Test func cleanOldEventsRemovesExpired() throws {
    let db = try Database(inMemory: true)
    let old = SessionEvent(
        sessionID: "s1", eventType: "SessionStart",
        createdAt: Date(timeIntervalSinceNow: -86400 * 30)
    )
    let recent = SessionEvent(
        sessionID: "s1", eventType: "UserPromptSubmit",
        createdAt: Date()
    )
    try db.saveEvent(old)
    try db.saveEvent(recent)

    let deleted = try db.cleanOldEvents(maxAge: 7 * 86400)
    #expect(deleted == 1)

    let events = try db.events(forSessionID: "s1")
    #expect(events.count == 1)
    #expect(events.first?.eventType == "UserPromptSubmit")
}

// MARK: - Saved Prompts

@Test func savedPromptCRUD() throws {
    let db = try Database(inMemory: true)
    let prompt = SavedPrompt(name: "Fix tests", text: "Fix the failing tests")
    try db.savePrompt(prompt)

    let all = try db.allPrompts()
    #expect(all.count == 1)
    #expect(all.first?.name == "Fix tests")
    #expect(all.first?.text == "Fix the failing tests")
}

@Test func savedPromptFilterByProject() throws {
    let db = try Database(inMemory: true)
    let global = SavedPrompt(name: "Global", text: "/commit")
    let scoped = SavedPrompt(name: "Scoped", text: "/pr", projectID: "p1")
    try db.savePrompt(global)
    try db.savePrompt(scoped)

    let forP1 = try db.prompts(forProjectID: "p1")
    #expect(forP1.count == 1)
    #expect(forP1.first?.name == "Scoped")
}

@Test func savedPromptDelete() throws {
    let db = try Database(inMemory: true)
    let prompt = SavedPrompt(name: "Delete me", text: "test")
    try db.savePrompt(prompt)
    try db.deletePrompt(id: prompt.id)

    let all = try db.allPrompts()
    #expect(all.isEmpty)
}

// MARK: - Migration Safety

@Test func migrationRunsAllVersionsOnFreshDB() throws {
    // This test verifies all 17 migrations apply cleanly to a fresh database.
    // A failure here means a migration has a dependency on prior state that isn't met.
    let db = try Database(inMemory: true)

    // Verify we can write to all tables created by migrations
    let session = Session(title: "migration-test", path: "/tmp", useHappy: true, totalCostUSD: 0.5)
    try db.saveSession(session)

    let project = Project(name: "test", path: "/tmp", issuesEnabled: true, branchPrefix: "fix/")
    try db.saveProject(project)

    let event = SessionEvent(sessionID: session.id, eventType: "SessionStart")
    try db.saveEvent(event)

    let template = SessionTemplate(name: "test-template", projectID: project.id)
    try db.saveTemplate(template)

    let prompt = SavedPrompt(name: "test-prompt", text: "/commit")
    try db.savePrompt(prompt)

    // Verify all reads work
    #expect(try db.allSessions().count == 1)
    #expect(try db.allProjects().count == 1)
    #expect(try db.events(forSessionID: session.id).count == 1)
    #expect(try db.allTemplates().count == 1)
    #expect(try db.allPrompts().count == 1)

    // Verify cost fields survived the migration
    let loaded = try db.session(id: session.id)
    #expect(loaded?.totalCostUSD == 0.5)
    #expect(loaded?.useHappy == true)
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
