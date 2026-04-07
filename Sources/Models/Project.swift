import Foundation

/// A registered project (git repository) that contains sessions and worktrees.
public struct Project: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var path: String
    public var defaultBranch: String
    public var sortOrder: Int
    public var createdAt: Date

    // Per-project overrides (nil = use global default)
    public var themeID: String?
    public var permissionMode: PermissionMode?

    // GitHub integration
    public var ghRepo: String?
    public var ghHost: String?
    public var issuesEnabled: Bool

    /// Branch name prefix template (e.g. "feature/", "fix/", "matt/"). Nil = no prefix.
    public var branchPrefix: String?

    public init(
        id: String = Project.generateID(),
        name: String,
        path: String,
        defaultBranch: String = "main",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        themeID: String? = nil,
        permissionMode: PermissionMode? = nil,
        ghRepo: String? = nil,
        ghHost: String? = nil,
        issuesEnabled: Bool = false,
        branchPrefix: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.themeID = themeID
        self.permissionMode = permissionMode
        self.ghRepo = ghRepo
        self.ghHost = ghHost
        self.issuesEnabled = issuesEnabled
        self.branchPrefix = branchPrefix
    }

    public static func generateID() -> String {
        "proj-\(UUID().uuidString.lowercased())"
    }
}
