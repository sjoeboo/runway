import Foundation

/// A managed AI coding session with an associated terminal, worktree, and status.
public struct Session: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var projectID: String?
    public var path: String
    public var tool: Tool
    public var status: SessionStatus
    public var worktreeBranch: String?
    public var prNumber: Int?
    public var issueNumber: Int?
    public var parentID: String?
    public var command: String?
    public var permissionMode: PermissionMode
    public var sortOrder: Int
    public var createdAt: Date
    public var lastAccessedAt: Date

    /// Transient, non-persisted field for UI display of last activity.
    public var lastActivityText: String?

    public init(
        id: String = Session.generateID(),
        title: String,
        projectID: String? = nil,
        path: String,
        tool: Tool = .claude,
        status: SessionStatus = .starting,
        worktreeBranch: String? = nil,
        prNumber: Int? = nil,
        issueNumber: Int? = nil,
        parentID: String? = nil,
        command: String? = nil,
        permissionMode: PermissionMode = .default,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.path = path
        self.tool = tool
        self.status = status
        self.worktreeBranch = worktreeBranch
        self.prNumber = prNumber
        self.issueNumber = issueNumber
        self.parentID = parentID
        self.command = command
        self.permissionMode = permissionMode
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// Generate a unique session ID using UUID for full entropy.
    public static func generateID() -> String {
        "id-\(UUID().uuidString.lowercased())"
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

    public func cliFlags(for tool: Tool) -> [String] {
        switch (self, tool) {
        case (.default, _): []
        case (.acceptEdits, .claude): ["--accept-edits"]
        case (.acceptEdits, .gemini): ["--yolo"]
        case (.acceptEdits, .codex): ["--full-auto"]
        case (.bypassAll, .claude): ["--dangerously-skip-permissions"]
        case (.bypassAll, .gemini): ["--yolo"]
        case (.bypassAll, .codex): ["--yolo"]
        default: []
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

    /// Whether a tmux session is expected to exist for this status.
    /// Used to guard TerminalPane from attempting `tmux attach-session`
    /// when the tmux session hasn't been created yet or is already gone.
    public var tmuxSessionExpected: Bool {
        switch self {
        case .running, .idle, .waiting: true
        case .starting, .error, .stopped: false
        }
    }
}

// MARK: - Tool

public enum Tool: Codable, Sendable, Hashable {
    case claude
    case gemini
    case codex
    case shell
    case custom(String)

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini CLI"
        case .codex: "Codex"
        case .shell: "Shell"
        case .custom(let name): name
        }
    }

    public var command: String {
        switch self {
        case .claude: "claude"
        case .gemini: "gemini"
        case .codex: "codex"
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
        case "gemini": self = .gemini
        case "codex": self = .codex
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
        case .gemini:
            try container.encode("gemini", forKey: .type)
        case .codex:
            try container.encode("codex", forKey: .type)
        case .shell:
            try container.encode("shell", forKey: .type)
        case .custom(let name):
            try container.encode("custom", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

// MARK: - Tool Capabilities

extension Tool {
    public var supportsPermissionModes: Bool {
        switch self {
        case .claude, .gemini, .codex: true
        default: false
        }
    }

    public var supportsInitialPrompt: Bool {
        switch self {
        case .claude, .gemini, .codex: true
        default: false
        }
    }

    public var supportsHappy: Bool {
        switch self {
        case .claude, .gemini, .codex: true
        default: false
        }
    }

    public var isAgent: Bool {
        switch self {
        case .shell: false
        default: true
        }
    }
}
