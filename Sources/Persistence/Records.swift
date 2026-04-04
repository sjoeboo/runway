import Foundation
import GRDB
import Models

// MARK: - Session Record

struct SessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sessions"

    var id: String
    var title: String
    var projectID: String?
    var path: String
    var tool: String
    var status: String
    var worktreeBranch: String?
    var parentID: String?
    var command: String?
    var permissionMode: String
    var sortOrder: Int
    var createdAt: Date
    var lastAccessedAt: Date

    init(_ session: Session) {
        self.id = session.id
        self.title = session.title
        self.projectID = session.projectID
        self.path = session.path
        self.tool = Self.encodeTool(session.tool)
        self.status = session.status.rawValue
        self.worktreeBranch = session.worktreeBranch
        self.parentID = session.parentID
        self.command = session.command
        self.permissionMode = session.permissionMode.rawValue
        self.sortOrder = session.sortOrder
        self.createdAt = session.createdAt
        self.lastAccessedAt = session.lastAccessedAt
    }

    func toSession() -> Session {
        Session(
            id: id,
            title: title,
            projectID: projectID,
            path: path,
            tool: Self.decodeTool(tool),
            status: SessionStatus(rawValue: status) ?? .stopped,
            worktreeBranch: worktreeBranch,
            parentID: parentID,
            command: command,
            permissionMode: PermissionMode(rawValue: permissionMode) ?? .default,
            sortOrder: sortOrder,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
    }

    private static func encodeTool(_ tool: Tool) -> String {
        switch tool {
        case .claude: "claude"
        case .shell: "shell"
        case .custom(let name): name
        }
    }

    private static func decodeTool(_ raw: String) -> Tool {
        switch raw {
        case "claude": .claude
        case "shell": .shell
        default: .custom(raw)
        }
    }
}

// MARK: - Project Record

struct ProjectRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var path: String
    var defaultBranch: String
    var sortOrder: Int
    var createdAt: Date
    var themeID: String?
    var permissionMode: String?
    var ghRepo: String?
    var ghHost: String?
    var issuesEnabled: Bool
    var branchPrefix: String?

    init(_ project: Project) {
        self.id = project.id
        self.name = project.name
        self.path = project.path
        self.defaultBranch = project.defaultBranch
        self.sortOrder = project.sortOrder
        self.createdAt = project.createdAt
        self.themeID = project.themeID
        self.permissionMode = project.permissionMode?.rawValue
        self.ghRepo = project.ghRepo
        self.ghHost = project.ghHost
        self.issuesEnabled = project.issuesEnabled
        self.branchPrefix = project.branchPrefix
    }

    func toProject() -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            defaultBranch: defaultBranch,
            sortOrder: sortOrder,
            createdAt: createdAt,
            themeID: themeID,
            permissionMode: permissionMode.flatMap { PermissionMode(rawValue: $0) },
            ghRepo: ghRepo,
            ghHost: ghHost,
            issuesEnabled: issuesEnabled,
            branchPrefix: branchPrefix
        )
    }
}
