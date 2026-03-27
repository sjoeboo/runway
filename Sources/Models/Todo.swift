import Foundation

/// A work item linked to a project and optionally to a session.
public struct Todo: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var prompt: String?
    public var projectID: String?
    public var sessionID: String?
    public var status: TodoStatus
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = Todo.generateID(),
        title: String,
        description: String = "",
        prompt: String? = nil,
        projectID: String? = nil,
        sessionID: String? = nil,
        status: TodoStatus = .todo,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.prompt = prompt
        self.projectID = projectID
        self.sessionID = sessionID
        self.status = status
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func generateID() -> String {
        let hex = (0..<4).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
        return "todo-\(hex)"
    }
}

// MARK: - Todo Status

public enum TodoStatus: String, Codable, Sendable, CaseIterable {
    case todo = "todo"
    case inProgress = "in_progress"
    case inReview = "in_review"
    case done = "done"

    public var displayName: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .inReview: "In Review"
        case .done: "Done"
        }
    }
}
