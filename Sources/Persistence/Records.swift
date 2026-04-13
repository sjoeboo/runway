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
    var prNumber: Int?
    var issueNumber: Int?
    var parentID: String?
    var command: String?
    var permissionMode: String
    var useHappy: Bool
    var sortOrder: Int
    var createdAt: Date
    var lastAccessedAt: Date
    var totalCostUSD: Double?
    var totalInputTokens: Int?
    var totalOutputTokens: Int?
    var transcriptPath: String?

    init(_ session: Session) {
        self.id = session.id
        self.title = session.title
        self.projectID = session.projectID
        self.path = session.path
        self.tool = Self.encodeTool(session.tool)
        self.status = session.status.rawValue
        self.worktreeBranch = session.worktreeBranch
        self.prNumber = session.prNumber
        self.issueNumber = session.issueNumber
        self.parentID = session.parentID
        self.command = session.command
        self.permissionMode = session.permissionMode.rawValue
        self.useHappy = session.useHappy
        self.sortOrder = session.sortOrder
        self.createdAt = session.createdAt
        self.lastAccessedAt = session.lastAccessedAt
        self.totalCostUSD = session.totalCostUSD
        self.totalInputTokens = session.totalInputTokens
        self.totalOutputTokens = session.totalOutputTokens
        self.transcriptPath = session.transcriptPath
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
            prNumber: prNumber,
            issueNumber: issueNumber,
            parentID: parentID,
            command: command,
            permissionMode: PermissionMode(rawValue: permissionMode) ?? .default,
            useHappy: useHappy,
            sortOrder: sortOrder,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            totalCostUSD: totalCostUSD,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            transcriptPath: transcriptPath
        )
    }

    static func encodeTool(_ tool: Tool) -> String {
        switch tool {
        case .claude: "claude"
        case .gemini: "gemini"
        case .codex: "codex"
        case .shell: "shell"
        case .custom(let name): name
        }
    }

    static func decodeTool(_ raw: String) -> Tool {
        switch raw {
        case "claude": .claude
        case "gemini": .gemini
        case "codex": .codex
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

// MARK: - Session Event Record

struct SessionEventRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "session_events"

    var id: String
    var sessionID: String
    var eventType: String
    var prompt: String?
    var toolName: String?
    var message: String?
    var notificationType: String?
    var createdAt: Date

    init(_ event: SessionEvent) {
        self.id = event.id
        self.sessionID = event.sessionID
        self.eventType = event.eventType
        self.prompt = event.prompt
        self.toolName = event.toolName
        self.message = event.message
        self.notificationType = event.notificationType
        self.createdAt = event.createdAt
    }

    func toEvent() -> SessionEvent {
        SessionEvent(
            id: id,
            sessionID: sessionID,
            eventType: eventType,
            prompt: prompt,
            toolName: toolName,
            message: message,
            notificationType: notificationType,
            createdAt: createdAt
        )
    }
}

// MARK: - Saved Prompt Record

struct SavedPromptRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "saved_prompts"

    var id: String
    var name: String
    var text: String
    var projectID: String?
    var sortOrder: Int
    var createdAt: Date

    init(_ prompt: SavedPrompt) {
        self.id = prompt.id
        self.name = prompt.name
        self.text = prompt.text
        self.projectID = prompt.projectID
        self.sortOrder = prompt.sortOrder
        self.createdAt = prompt.createdAt
    }

    func toPrompt() -> SavedPrompt {
        SavedPrompt(
            id: id,
            name: name,
            text: text,
            projectID: projectID,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}

// MARK: - Session Template Record

struct SessionTemplateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "session_templates"

    var id: String
    var name: String
    var projectID: String?
    var tool: String
    var useWorktree: Bool
    var branchPrefix: String?
    var permissionMode: String
    var initialPromptTemplate: String
    var sortOrder: Int
    var createdAt: Date

    init(_ template: SessionTemplate) {
        self.id = template.id
        self.name = template.name
        self.projectID = template.projectID
        self.tool = SessionRecord.encodeTool(template.tool)
        self.useWorktree = template.useWorktree
        self.branchPrefix = template.branchPrefix
        self.permissionMode = template.permissionMode.rawValue
        self.initialPromptTemplate = template.initialPromptTemplate
        self.sortOrder = template.sortOrder
        self.createdAt = template.createdAt
    }

    func toTemplate() -> SessionTemplate {
        SessionTemplate(
            id: id,
            name: name,
            projectID: projectID,
            tool: SessionRecord.decodeTool(tool),
            useWorktree: useWorktree,
            branchPrefix: branchPrefix,
            permissionMode: PermissionMode(rawValue: permissionMode) ?? .default,
            initialPromptTemplate: initialPromptTemplate,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}
