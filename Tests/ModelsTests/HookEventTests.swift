import Testing
import Foundation
@testable import Models

// MARK: - HookEvent

@Test func hookEventCreation() {
    let event = HookEvent(sessionID: "session-1", event: .sessionStart)
    #expect(event.sessionID == "session-1")
    #expect(event.event == .sessionStart)
    #expect(event.payload == nil)
}

@Test func hookEventWithPayload() {
    let payload = HookPayload(toolName: "Read", message: "Reading file", status: "running")
    let event = HookEvent(sessionID: "s1", event: .permissionRequest, payload: payload)
    #expect(event.payload?.toolName == "Read")
    #expect(event.payload?.message == "Reading file")
    #expect(event.payload?.status == "running")
}

// MARK: - HookEventType

@Test func hookEventTypeRawValues() {
    #expect(HookEventType.sessionStart.rawValue == "SessionStart")
    #expect(HookEventType.sessionEnd.rawValue == "SessionEnd")
    #expect(HookEventType.stop.rawValue == "Stop")
    #expect(HookEventType.userPromptSubmit.rawValue == "UserPromptSubmit")
    #expect(HookEventType.permissionRequest.rawValue == "PermissionRequest")
    #expect(HookEventType.notification.rawValue == "Notification")
}

// MARK: - HookPayload

@Test func hookPayloadDefaults() {
    let payload = HookPayload()
    #expect(payload.toolName == nil)
    #expect(payload.message == nil)
    #expect(payload.status == nil)
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
    #expect(PermissionMode.default.cliFlags.isEmpty)
    #expect(PermissionMode.acceptEdits.cliFlags == ["--accept-edits"])
    #expect(PermissionMode.bypassAll.cliFlags == ["--dangerously-skip-permissions"])
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
