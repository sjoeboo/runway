import Foundation

/// A reusable session configuration template.
public struct SessionTemplate: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var projectID: String?
    public var tool: Tool
    public var useWorktree: Bool
    public var branchPrefix: String?
    public var permissionMode: PermissionMode
    public var initialPromptTemplate: String
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        projectID: String? = nil,
        tool: Tool = .claude,
        useWorktree: Bool = true,
        branchPrefix: String? = nil,
        permissionMode: PermissionMode = .default,
        initialPromptTemplate: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectID = projectID
        self.tool = tool
        self.useWorktree = useWorktree
        self.branchPrefix = branchPrefix
        self.permissionMode = permissionMode
        self.initialPromptTemplate = initialPromptTemplate
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Resolves placeholders in the prompt template.
    public func resolvedPrompt(title: String, issueNumber: Int? = nil, issueTitle: String? = nil) -> String {
        var result = initialPromptTemplate
        result = result.replacingOccurrences(of: "{title}", with: title)
        if let num = issueNumber {
            result = result.replacingOccurrences(of: "{issue}", with: "#\(num): \(issueTitle ?? "")")
        } else {
            result = result.replacingOccurrences(of: "{issue}", with: "")
        }
        return result
    }

    /// Built-in templates offered as starting points (not persisted).
    public static let builtIn: [SessionTemplate] = [
        SessionTemplate(
            id: "builtin-quick-fix", name: "Quick Fix",
            tool: .claude, useWorktree: false,
            permissionMode: .acceptEdits,
            initialPromptTemplate: "Fix the following issue:\n\n{title}"
        ),
        SessionTemplate(
            id: "builtin-feature", name: "Feature Branch",
            tool: .claude, useWorktree: true,
            permissionMode: .default,
            initialPromptTemplate: ""
        ),
        SessionTemplate(
            id: "builtin-autonomous", name: "Autonomous Task",
            tool: .claude, useWorktree: true,
            permissionMode: .bypassAll,
            initialPromptTemplate:
                "Complete the following autonomously without asking for confirmation:\n\n{title}"
        ),
    ]
}
