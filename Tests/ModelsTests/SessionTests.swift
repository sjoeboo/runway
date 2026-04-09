import Foundation
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

@Test func sessionPRNumberDefaultsToNil() {
    let session = Session(title: "test", path: "/tmp")
    #expect(session.prNumber == nil)
}

@Test func sessionPRNumberPreserved() {
    let session = Session(title: "review", path: "/tmp", prNumber: 247)
    #expect(session.prNumber == 247)
}

@Test func sessionIssueNumberDefaults() {
    let session = Session(title: "Test", path: "/tmp")
    #expect(session.issueNumber == nil)
    #expect(session.lastActivityText == nil)
}

@Test func sessionIssueNumberSet() {
    let session = Session(title: "Fix #42", path: "/tmp", issueNumber: 42)
    #expect(session.issueNumber == 42)
}

@Test func geminiToolProperties() {
    #expect(Tool.gemini.displayName == "Gemini CLI")
    #expect(Tool.gemini.command == "gemini")
}

@Test func codexToolProperties() {
    #expect(Tool.codex.displayName == "Codex")
    #expect(Tool.codex.command == "codex")
}

@Test func toolSupportsPermissionModes() {
    #expect(Tool.claude.supportsPermissionModes == true)
    #expect(Tool.gemini.supportsPermissionModes == true)
    #expect(Tool.codex.supportsPermissionModes == true)
    #expect(Tool.shell.supportsPermissionModes == false)
    #expect(Tool.custom("aider").supportsPermissionModes == false)
}

@Test func toolSupportsHappy() {
    #expect(Tool.claude.supportsHappy == true)
    #expect(Tool.gemini.supportsHappy == true)
    #expect(Tool.codex.supportsHappy == true)
    #expect(Tool.shell.supportsHappy == false)
}

@Test func toolSupportsInitialPrompt() {
    #expect(Tool.claude.supportsInitialPrompt == true)
    #expect(Tool.gemini.supportsInitialPrompt == true)
    #expect(Tool.codex.supportsInitialPrompt == true)
    #expect(Tool.shell.supportsInitialPrompt == false)
}

@Test func toolIsAgent() {
    #expect(Tool.claude.isAgent == true)
    #expect(Tool.gemini.isAgent == true)
    #expect(Tool.codex.isAgent == true)
    #expect(Tool.shell.isAgent == false)
    #expect(Tool.custom("aider").isAgent == true)
}

@Test func toolCodableRoundTrip() throws {
    let tools: [Tool] = [.claude, .gemini, .codex, .shell, .custom("aider")]
    for tool in tools {
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(Tool.self, from: data)
        #expect(decoded == tool)
    }
}

@Test func permissionModeCliFlagsForClaude() {
    #expect(PermissionMode.default.cliFlags(for: .claude) == [])
    #expect(PermissionMode.acceptEdits.cliFlags(for: .claude) == ["--accept-edits"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .claude) == ["--dangerously-skip-permissions"])
}

@Test func permissionModeCliFlagsForGemini() {
    #expect(PermissionMode.default.cliFlags(for: .gemini) == [])
    #expect(PermissionMode.acceptEdits.cliFlags(for: .gemini) == ["--yolo"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .gemini) == ["--yolo"])
}

@Test func permissionModeCliFlagsForCodex() {
    #expect(PermissionMode.default.cliFlags(for: .codex) == [])
    #expect(PermissionMode.acceptEdits.cliFlags(for: .codex) == ["--full-auto"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .codex) == ["--yolo"])
}

@Test func permissionModeCliFlagsForShell() {
    #expect(PermissionMode.acceptEdits.cliFlags(for: .shell) == [])
    #expect(PermissionMode.bypassAll.cliFlags(for: .shell) == [])
}

@Test func sessionUseHappyDefaultsFalse() {
    let session = Session(title: "test", path: "/tmp")
    #expect(session.useHappy == false)
}

@Test func sessionUseHappyPreserved() {
    let session = Session(title: "test", path: "/tmp", useHappy: true)
    #expect(session.useHappy == true)
}
