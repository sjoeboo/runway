import Foundation

/// A reusable prompt that can be sent to a session via the SendTextBar.
///
/// Prompts can be global (projectID = nil) or project-scoped.
/// Built-in prompts provide common Claude Code slash commands.
public struct SavedPrompt: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var text: String
    public var projectID: String?
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        text: String,
        projectID: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.projectID = projectID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Built-in prompts for common commands (not persisted).
    public static let builtIn: [SavedPrompt] = [
        SavedPrompt(id: "builtin-commit", name: "Commit", text: "/commit", sortOrder: 0),
        SavedPrompt(id: "builtin-pr", name: "Create PR", text: "/pr", sortOrder: 1),
        SavedPrompt(id: "builtin-fix-tests", name: "Fix Tests", text: "Fix the failing tests", sortOrder: 2),
        SavedPrompt(
            id: "builtin-review", name: "Review Changes", text: "Review the changes you've made and suggest improvements", sortOrder: 3),
        SavedPrompt(id: "builtin-explain", name: "Explain", text: "Explain what this code does", sortOrder: 4),
    ]
}
