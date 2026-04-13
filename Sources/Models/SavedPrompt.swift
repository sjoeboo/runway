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

    /// Tool-specific built-in prompts (not persisted).
    /// Returns slash commands appropriate for the given tool.
    public static func builtIn(for tool: Tool) -> [SavedPrompt] {
        switch tool {
        case .claude:
            return claudeBuiltIn
        case .gemini:
            return geminiBuiltIn
        case .codex:
            return codexBuiltIn
        default:
            return genericBuiltIn
        }
    }

    /// Claude Code slash commands
    private static let claudeBuiltIn: [SavedPrompt] = [
        // Core workflow
        SavedPrompt(id: "cc-compact", name: "/compact", text: "/compact", sortOrder: 0),
        SavedPrompt(id: "cc-clear", name: "/clear", text: "/clear", sortOrder: 1),
        SavedPrompt(id: "cc-help", name: "/help", text: "/help", sortOrder: 2),
        // Code operations
        SavedPrompt(id: "cc-review", name: "/review", text: "/review", sortOrder: 10),
        SavedPrompt(id: "cc-pr-comments", name: "/pr-comments", text: "/pr-comments", sortOrder: 11),
        // Session management
        SavedPrompt(id: "cc-status", name: "/status", text: "/status", sortOrder: 20),
        SavedPrompt(id: "cc-cost", name: "/cost", text: "/cost", sortOrder: 21),
        SavedPrompt(id: "cc-logout", name: "/logout", text: "/logout", sortOrder: 22),
        // Configuration
        SavedPrompt(id: "cc-config", name: "/config", text: "/config", sortOrder: 30),
        SavedPrompt(id: "cc-permissions", name: "/permissions", text: "/permissions", sortOrder: 31),
        SavedPrompt(id: "cc-model", name: "/model", text: "/model", sortOrder: 32),
        // MCP
        SavedPrompt(id: "cc-mcp", name: "/mcp", text: "/mcp", sortOrder: 40),
        // Common tasks
        SavedPrompt(id: "cc-fix-tests", name: "Fix failing tests", text: "Fix the failing tests", sortOrder: 50),
        SavedPrompt(id: "cc-explain", name: "Explain this code", text: "Explain what this code does", sortOrder: 51),
    ]

    /// Gemini CLI commands
    private static let geminiBuiltIn: [SavedPrompt] = [
        SavedPrompt(id: "gem-help", name: "/help", text: "/help", sortOrder: 0),
        SavedPrompt(id: "gem-clear", name: "/clear", text: "/clear", sortOrder: 1),
        SavedPrompt(id: "gem-stats", name: "/stats", text: "/stats", sortOrder: 2),
        SavedPrompt(id: "gem-fix-tests", name: "Fix failing tests", text: "Fix the failing tests", sortOrder: 10),
    ]

    /// Codex commands
    private static let codexBuiltIn: [SavedPrompt] = [
        SavedPrompt(id: "cdx-help", name: "/help", text: "/help", sortOrder: 0),
        SavedPrompt(id: "cdx-fix-tests", name: "Fix failing tests", text: "Fix the failing tests", sortOrder: 10),
    ]

    /// Generic prompts for shell and custom tools
    private static let genericBuiltIn: [SavedPrompt] = [
        SavedPrompt(id: "gen-fix-tests", name: "Fix failing tests", text: "Fix the failing tests", sortOrder: 0),
        SavedPrompt(id: "gen-explain", name: "Explain this code", text: "Explain what this code does", sortOrder: 1),
    ]
}
