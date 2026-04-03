import Foundation
import Testing

@testable import Terminal

@Test func tmuxIsAvailable() async {
    let manager = TmuxSessionManager()
    let available = await manager.isAvailable()
    if !available {
        print("⚠️ tmux not installed — skipping TmuxSessionManager tests")
        return
    }
    #expect(available == true)
}

@Test func createAndListSession() async throws {
    let manager = TmuxSessionManager()
    guard await manager.isAvailable() else { return }

    let name = "runway-test-\(UUID().uuidString.prefix(8))"
    defer { Task { try? await manager.killSession(name: name) } }

    try await manager.createSession(
        name: name,
        workDir: "/tmp",
        command: nil,
        env: [:]
    )

    let exists = await manager.sessionExists(name: name)
    #expect(exists == true)

    let sessions = await manager.listSessions(prefix: "runway-test-")
    #expect(sessions.contains(where: { $0.name == name }))
}

@Test func killSession() async throws {
    let manager = TmuxSessionManager()
    guard await manager.isAvailable() else { return }

    let name = "runway-test-\(UUID().uuidString.prefix(8))"

    try await manager.createSession(
        name: name,
        workDir: "/tmp",
        command: nil,
        env: [:]
    )

    #expect(await manager.sessionExists(name: name) == true)

    try await manager.killSession(name: name)

    #expect(await manager.sessionExists(name: name) == false)
}

@Test func createSessionWithCommand() async throws {
    let manager = TmuxSessionManager()
    guard await manager.isAvailable() else { return }

    let name = "runway-test-\(UUID().uuidString.prefix(8))"
    defer { Task { try? await manager.killSession(name: name) } }

    try await manager.createSession(
        name: name,
        workDir: "/tmp",
        command: "echo hello",
        env: ["RUNWAY_SESSION_ID": "test-123"]
    )

    let exists = await manager.sessionExists(name: name)
    #expect(exists == true)
}

@Test func attachCommand() async {
    let manager = TmuxSessionManager()
    let (executable, args) = await manager.attachCommand(name: "runway-abc123")
    #expect(executable == "/usr/bin/env")
    #expect(args == ["tmux", "attach-session", "-t", "runway-abc123"])
}

@Test func sessionExistsReturnsFalseForMissing() async {
    let manager = TmuxSessionManager()
    guard await manager.isAvailable() else { return }

    let exists = await manager.sessionExists(name: "runway-definitely-not-real-\(UUID().uuidString)")
    #expect(exists == false)
}
