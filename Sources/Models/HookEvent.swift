import Foundation

/// A lifecycle event received from Claude Code via HTTP hooks.
///
/// Claude Code sends JSON with snake_case fields:
/// `session_id`, `hook_event_name`, `cwd`, `transcript_path`, etc.
public struct HookEvent: Codable, Sendable {
    public var sessionID: String
    public var event: HookEventType
    public var cwd: String?
    public var transcriptPath: String?

    // Event-specific fields
    public var toolName: String?
    public var message: String?
    public var prompt: String?
    public var source: String?
    public var notificationType: String?

    // Cost/token fields (populated in Stop events by Claude Code)
    public var totalCostUSD: Double?
    public var totalInputTokens: Int?
    public var totalOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case event = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case message
        case prompt
        case source
        case notificationType = "notification_type"
        case totalCostUSD = "total_cost_usd"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
    }

    public init(
        sessionID: String, event: HookEventType,
        cwd: String? = nil, transcriptPath: String? = nil,
        toolName: String? = nil, message: String? = nil,
        prompt: String? = nil, source: String? = nil,
        notificationType: String? = nil,
        totalCostUSD: Double? = nil,
        totalInputTokens: Int? = nil,
        totalOutputTokens: Int? = nil
    ) {
        self.sessionID = sessionID
        self.event = event
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.toolName = toolName
        self.message = message
        self.prompt = prompt
        self.source = source
        self.notificationType = notificationType
        self.totalCostUSD = totalCostUSD
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}

public enum HookEventType: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case stop = "Stop"
    case userPromptSubmit = "UserPromptSubmit"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    // Gemini CLI events
    case beforeAgent = "BeforeAgent"
    case afterAgent = "AfterAgent"
}
