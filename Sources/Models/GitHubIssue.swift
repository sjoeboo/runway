import Foundation

public struct GitHubIssue: Identifiable, Codable, Sendable {
    public let id: String  // "owner/repo#123"
    public let number: Int
    public var title: String
    public var state: IssueState
    public var author: String
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
        self.labels = labels
        self.assignees = assignees
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum IssueState: String, Codable, Sendable {
    case open = "OPEN"
    case closed = "CLOSED"
}
