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
