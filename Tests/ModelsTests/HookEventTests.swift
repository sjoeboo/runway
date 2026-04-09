import Foundation
import Testing

@testable import Models

// MARK: - HookEvent

@Test func hookEventCreation() {
    let event = HookEvent(sessionID: "session-1", event: .sessionStart)
    #expect(event.sessionID == "session-1")
    #expect(event.event == .sessionStart)
    #expect(event.toolName == nil)
}

@Test func hookEventWithFields() {
    let event = HookEvent(
        sessionID: "s1", event: .permissionRequest,
        toolName: "Read", message: "Reading file"
    )
    #expect(event.toolName == "Read")
    #expect(event.message == "Reading file")
}

@Test func hookEventDecodesClaudeCodeJSON() throws {
    let json = """
        {
            "session_id": "abc123",
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/Users/test/code",
            "transcript_path": "/Users/test/.claude/transcript.jsonl",
            "prompt": "fix the bug"
        }
        """
    let event = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    #expect(event.sessionID == "abc123")
    #expect(event.event == .userPromptSubmit)
    #expect(event.cwd == "/Users/test/code")
    #expect(event.prompt == "fix the bug")
}

@Test func hookEventDecodesPermissionRequest() throws {
    let json = """
        {
            "session_id": "abc123",
            "hook_event_name": "PermissionRequest",
            "cwd": "/Users/test/code",
            "tool_name": "Bash"
        }
        """
    let event = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    #expect(event.event == .permissionRequest)
    #expect(event.toolName == "Bash")
}

@Test func hookEventDecodesNotification() throws {
    let json = """
        {
            "session_id": "abc123",
            "hook_event_name": "Notification",
            "message": "Permission needed",
            "notification_type": "permission_prompt"
        }
        """
    let event = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    #expect(event.event == .notification)
    #expect(event.message == "Permission needed")
    #expect(event.notificationType == "permission_prompt")
}

@Test func geminiBeforeAgentEventDecodes() throws {
    let json = """
        {"session_id": "s1", "hook_event_name": "BeforeAgent"}
        """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)
    #expect(event.event == .beforeAgent)
}

@Test func geminiAfterAgentEventDecodes() throws {
    let json = """
        {"session_id": "s1", "hook_event_name": "AfterAgent"}
        """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)
    #expect(event.event == .afterAgent)
}

// MARK: - HookEventType

@Test func hookEventTypeRawValues() {
    #expect(HookEventType.sessionStart.rawValue == "SessionStart")
    #expect(HookEventType.sessionEnd.rawValue == "SessionEnd")
    #expect(HookEventType.stop.rawValue == "Stop")
    #expect(HookEventType.userPromptSubmit.rawValue == "UserPromptSubmit")
    #expect(HookEventType.permissionRequest.rawValue == "PermissionRequest")
    #expect(HookEventType.notification.rawValue == "Notification")
    #expect(HookEventType.beforeAgent.rawValue == "BeforeAgent")
    #expect(HookEventType.afterAgent.rawValue == "AfterAgent")
}

// MARK: - PermissionMode

@Test func permissionModeRawValues() {
    #expect(PermissionMode.default.rawValue == "default")
    #expect(PermissionMode.acceptEdits.rawValue == "accept_edits")
    #expect(PermissionMode.bypassAll.rawValue == "bypass_all")
}

@Test func permissionModeDisplayNames() {
    #expect(PermissionMode.default.displayName == "Default")
    #expect(PermissionMode.acceptEdits.displayName == "Accept Edits")
    #expect(PermissionMode.bypassAll.displayName == "Bypass All")
}

@Test func permissionModeCLIFlags() {
    #expect(PermissionMode.default.cliFlags(for: .claude).isEmpty)
    #expect(PermissionMode.acceptEdits.cliFlags(for: .claude) == ["--accept-edits"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .claude) == ["--dangerously-skip-permissions"])
}

@Test func permissionModeCaseIterable() {
    #expect(PermissionMode.allCases.count == 3)
}

// MARK: - Tool Codable Roundtrip

@Test func toolCodableRoundtrip() throws {
    let tools: [Tool] = [.claude, .shell, .custom("aider")]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for tool in tools {
        let data = try encoder.encode(tool)
        let decoded = try decoder.decode(Tool.self, from: data)
        #expect(decoded == tool, "Tool \(tool.displayName) should survive encode/decode")
    }
}

@Test func toolDecodesUnknownAsCustom() throws {
    let json = #"{"type":"copilot"}"#
    let decoded = try JSONDecoder().decode(Tool.self, from: Data(json.utf8))
    if case .custom(let name) = decoded {
        #expect(name == "copilot")
    } else {
        #expect(Bool(false), "Expected .custom for unknown tool type")
    }
}

// MARK: - NewSessionRequest

@Test func newSessionRequestProperties() {
    let request = NewSessionRequest(
        title: "Debug auth",
        projectID: "proj-1",
        path: "/code/myapp",
        tool: .claude,
        useWorktree: true,
        branchName: "fix/auth-bug"
    )
    #expect(request.title == "Debug auth")
    #expect(request.useWorktree == true)
    #expect(request.branchName == "fix/auth-bug")
    #expect(request.permissionMode == .default)
}

@Test func newSessionRequestCustomPermission() {
    let request = NewSessionRequest(
        title: "Fast work",
        projectID: nil,
        path: "/tmp",
        tool: .shell,
        useWorktree: false,
        branchName: nil,
        permissionMode: .bypassAll
    )
    #expect(request.permissionMode == .bypassAll)
    #expect(request.projectID == nil)
    #expect(request.branchName == nil)
}
