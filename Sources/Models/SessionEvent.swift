import Foundation

/// A persisted hook event for the session activity log.
public struct SessionEvent: Identifiable, Codable, Sendable {
    public let id: String
    public let sessionID: String
    public let eventType: String
    public var prompt: String?
    public var toolName: String?
    public var message: String?
    public var notificationType: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        sessionID: String,
        eventType: String,
        prompt: String? = nil,
        toolName: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.eventType = eventType
        self.prompt = prompt.map { String($0.prefix(2000)) }
        self.toolName = toolName
        self.message = message
        self.notificationType = notificationType
        self.createdAt = createdAt
    }
}
