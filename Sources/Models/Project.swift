import Foundation

/// A registered project (git repository) that contains sessions and worktrees.
public struct Project: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public var defaultBranch: String
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: String = Project.generateID(),
        name: String,
        path: String,
        defaultBranch: String = "main",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    public static func generateID() -> String {
        let hex = (0..<4).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
        return "proj-\(hex)"
    }
}
