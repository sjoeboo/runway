import Foundation

/// A managed AI coding session with an associated terminal, worktree, and status.
public struct Session: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var groupID: String?
    public var path: String
    public var tool: Tool
    public var status: SessionStatus
    public var worktreeBranch: String?
    public var parentID: String?
    public var command: String?
    public var permissionMode: PermissionMode
    public var createdAt: Date
    public var lastAccessedAt: Date

    public init(
        id: String = Session.generateID(),
        title: String,
        groupID: String? = nil,
        path: String,
        tool: Tool = .claude,
        status: SessionStatus = .starting,
        worktreeBranch: String? = nil,
        parentID: String? = nil,
        command: String? = nil,
        permissionMode: PermissionMode = .default,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.groupID = groupID
        self.path = path
        self.tool = tool
        self.status = status
        self.worktreeBranch = worktreeBranch
        self.parentID = parentID
        self.command = command
        self.permissionMode = permissionMode
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// Generate a unique session ID in the format "id-{8hex}-{timestamp}".
    public static func generateID() -> String {
        let hex = (0..<4).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
        let ts = Int(Date().timeIntervalSince1970)
        return "id-\(hex)-\(ts)"
    }
}

// MARK: - Permission Mode

public enum PermissionMode: String, Codable, Sendable, CaseIterable {
    case `default` = "default"
    case acceptEdits = "accept_edits"
    case bypassAll = "bypass_all"

    public var displayName: String {
        switch self {
        case .default: "Default"
        case .acceptEdits: "Accept Edits"
        case .bypassAll: "Bypass All"
        }
    }

    public var cliFlags: [String] {
        switch self {
        case .default: []
        case .acceptEdits: ["--accept-edits"]
        case .bypassAll: ["--dangerously-skip-permissions"]
        }
    }
}

// MARK: - Session Status

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case starting
    case running
    case waiting
    case idle
    case error
    case stopped
}

// MARK: - Tool

public enum Tool: Codable, Sendable, Hashable {
    case claude
    case shell
    case custom(String)

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .shell: "Shell"
        case .custom(let name): name
        }
    }

    public var command: String {
        switch self {
        case .claude: "claude"
        case .shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        case .custom(let name): name
        }
    }
}

// MARK: - Tool Codable conformance

extension Tool {
    enum CodingKeys: String, CodingKey {
        case type, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "claude": self = .claude
        case "shell": self = .shell
        default:
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? type
            self = .custom(name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .claude:
            try container.encode("claude", forKey: .type)
        case .shell:
            try container.encode("shell", forKey: .type)
        case .custom(let name):
            try container.encode("custom", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}
