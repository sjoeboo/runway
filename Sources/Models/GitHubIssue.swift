import Foundation

public struct GitHubIssue: Identifiable, Codable, Sendable {
    public let id: String  // "owner/repo#123"
    public let number: Int
    public var title: String
    public var state: IssueState
    public var author: String
    public var repo: String
    public var labels: [String]
    public var assignees: [String]
    public var url: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        number: Int, title: String, state: IssueState, author: String, repo: String,
        labels: [String] = [], assignees: [String] = [], url: String = "",
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = "\(repo)#\(number)"
        self.number = number
        self.title = title
        self.state = state
        self.author = author
        self.repo = repo
        self.labels = labels
        self.assignees = assignees
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension GitHubIssue {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.number = try container.decode(Int.self, forKey: .number)
        self.title = try container.decode(String.self, forKey: .title)
        self.state = try container.decode(IssueState.self, forKey: .state)
        self.author = try container.decode(String.self, forKey: .author)
        self.labels = try container.decode([String].self, forKey: .labels)
        self.assignees = try container.decode([String].self, forKey: .assignees)
        self.url = try container.decode(String.self, forKey: .url)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        if let repo = try container.decodeIfPresent(String.self, forKey: .repo) {
            self.repo = repo
        } else if let hashIndex = id.lastIndex(of: "#") {
            self.repo = String(id[id.startIndex..<hashIndex])
        } else {
            self.repo = ""
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, title, state, author, repo, labels, assignees, url, createdAt, updatedAt
    }
}

public enum IssueState: String, Codable, Sendable {
    case open = "OPEN"
    case closed = "CLOSED"
}

// MARK: - IssueDetail

public struct IssueDetail: Codable, Sendable {
    public var body: String
    public var comments: [IssueComment]
    public var timelineEvents: [IssueTimelineEvent]
    public var labels: [IssueDetailLabel]
    public var assignees: [String]
    public var milestone: String?
    public var stateReason: String?

    public init(
        body: String = "",
        comments: [IssueComment] = [],
        timelineEvents: [IssueTimelineEvent] = [],
        labels: [IssueDetailLabel] = [],
        assignees: [String] = [],
        milestone: String? = nil,
        stateReason: String? = nil
    ) {
        self.body = body
        self.comments = comments
        self.timelineEvents = timelineEvents
        self.labels = labels
        self.assignees = assignees
        self.milestone = milestone
        self.stateReason = stateReason
    }
}

// MARK: - IssueComment

public struct IssueComment: Identifiable, Codable, Sendable {
    public let id: String
    public var author: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        author: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - IssueTimelineEvent

public struct IssueTimelineEvent: Identifiable, Codable, Sendable {
    public let id: String
    public var event: String
    public var actor: String
    public var createdAt: Date
    public var label: IssueDetailLabel?
    public var assignee: String?
    public var source: IssueReference?
    public var rename: IssueRename?

    public init(
        id: String,
        event: String,
        actor: String,
        createdAt: Date = Date(),
        label: IssueDetailLabel? = nil,
        assignee: String? = nil,
        source: IssueReference? = nil,
        rename: IssueRename? = nil
    ) {
        self.id = id
        self.event = event
        self.actor = actor
        self.createdAt = createdAt
        self.label = label
        self.assignee = assignee
        self.source = source
        self.rename = rename
    }
}

// MARK: - IssueDetailLabel

public struct IssueDetailLabel: Codable, Sendable, Hashable {
    public var name: String
    public var color: String

    public init(name: String, color: String = "") {
        self.name = name
        self.color = color
    }
}

// MARK: - IssueReference

public struct IssueReference: Codable, Sendable {
    public var type: String
    public var number: Int
    public var title: String
    public var url: String

    public init(type: String, number: Int, title: String, url: String = "") {
        self.type = type
        self.number = number
        self.title = title
        self.url = url
    }
}

// MARK: - IssueRename

public struct IssueRename: Codable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

// MARK: - CloseReason

public enum CloseReason: String, Codable, Sendable, CaseIterable {
    case completed
    case notPlanned = "not planned"

    public var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .notPlanned: return "Not planned"
        }
    }

    /// Value accepted by `gh issue close --reason`.
    public var cliValue: String {
        switch self {
        case .completed: return "completed"
        case .notPlanned: return "not_planned"
        }
    }
}
