import Testing

@testable import Models

@Test func sessionIDGeneration() {
    let session = Session(title: "test", path: "/tmp")
    #expect(session.id.hasPrefix("id-"))
    #expect(session.id.count > 10)

    let id2 = Session.generateID()
    #expect(session.id != id2)
}

@Test func sessionDefaults() {
    let session = Session(title: "my-session", path: "/tmp/project")
    #expect(session.tool == .claude)
    #expect(session.status == .starting)
    #expect(session.worktreeBranch == nil)
    #expect(session.parentID == nil)
}

@Test func sessionSortOrderDefaultsToZero() {
    let session = Session(title: "test", path: "/tmp")
    #expect(session.sortOrder == 0)
}

@Test func sessionSortOrderPreserved() {
    let session = Session(title: "test", path: "/tmp", sortOrder: 42)
    #expect(session.sortOrder == 42)
}

@Test func toolDisplayNames() {
    #expect(Tool.claude.displayName == "Claude")
    #expect(Tool.shell.displayName == "Shell")
    #expect(Tool.custom("aider").displayName == "aider")
}

@Test func toolCommand() {
    #expect(Tool.claude.command == "claude")
    #expect(Tool.custom("aider").command == "aider")
}

@Test func sessionStatusRawValues() {
    #expect(SessionStatus.running.rawValue == "running")
    #expect(SessionStatus.waiting.rawValue == "waiting")
    #expect(SessionStatus.idle.rawValue == "idle")
    #expect(SessionStatus.error.rawValue == "error")
}
