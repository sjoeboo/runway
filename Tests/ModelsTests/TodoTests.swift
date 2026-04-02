import Foundation
import Testing

@testable import Models

// MARK: - Todo

@Test func todoIDGeneration() {
    let todo = Todo(title: "Fix bug")
    #expect(todo.id.hasPrefix("todo-"))

    let id2 = Todo.generateID()
    #expect(todo.id != id2)
}

@Test func todoDefaults() {
    let todo = Todo(title: "Write tests")
    #expect(todo.description.isEmpty)
    #expect(todo.prompt == nil)
    #expect(todo.projectID == nil)
    #expect(todo.sessionID == nil)
    #expect(todo.status == .todo)
    #expect(todo.sortOrder == 0)
}

@Test func todoWithAllFields() {
    let todo = Todo(
        title: "Implement feature",
        description: "Add login flow",
        prompt: "Create a login form with email/password",
        projectID: "proj-1",
        sessionID: "id-1234-567",
        status: .inProgress,
        sortOrder: 3
    )
    #expect(todo.prompt != nil)
    #expect(todo.status == .inProgress)
    #expect(todo.sortOrder == 3)
}

// MARK: - TodoStatus

@Test func todoStatusRawValues() {
    #expect(TodoStatus.todo.rawValue == "todo")
    #expect(TodoStatus.inProgress.rawValue == "in_progress")
    #expect(TodoStatus.inReview.rawValue == "in_review")
    #expect(TodoStatus.done.rawValue == "done")
}

@Test func todoStatusDisplayNames() {
    #expect(TodoStatus.todo.displayName == "To Do")
    #expect(TodoStatus.inProgress.displayName == "In Progress")
    #expect(TodoStatus.inReview.displayName == "In Review")
    #expect(TodoStatus.done.displayName == "Done")
}

@Test func todoStatusCaseIterable() {
    #expect(TodoStatus.allCases.count == 4)
}
