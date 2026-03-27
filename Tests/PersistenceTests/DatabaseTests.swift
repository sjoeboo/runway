import Testing
@testable import Persistence
import Models

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

@Test func todoCRUD() throws {
    let db = try Database(inMemory: true)

    let project = Project(name: "test", path: "/tmp")
    try db.saveProject(project)

    let todo = Todo(title: "Fix bug", projectID: project.id)
    try db.saveTodo(todo)

    let todos = try db.todos(forProject: project.id)
    #expect(todos.count == 1)
    #expect(todos.first?.title == "Fix bug")

    try db.deleteTodo(id: todo.id)
    let after = try db.todos(forProject: project.id)
    #expect(after.isEmpty)
}
