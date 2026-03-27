import Foundation

/// A lifecycle event received from Claude Code via HTTP hooks.
public struct HookEvent: Codable, Sendable {
    public var sessionID: String
    public var event: HookEventType
    public var timestamp: Date
    public var payload: HookPayload?

    public init(sessionID: String, event: HookEventType, timestamp: Date = Date(), payload: HookPayload? = nil) {
        self.sessionID = sessionID
        self.event = event
        self.timestamp = timestamp
        self.payload = payload
    }
}

public enum HookEventType: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case stop = "Stop"
    case userPromptSubmit = "UserPromptSubmit"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
}

public struct HookPayload: Codable, Sendable {
    public var toolName: String?
    public var message: String?
    public var status: String?

    public init(toolName: String? = nil, message: String? = nil, status: String? = nil) {
        self.toolName = toolName
        self.message = message
        self.status = status
    }
}
