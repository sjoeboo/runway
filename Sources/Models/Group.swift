import Foundation

/// A hierarchical group for organizing sessions within a project.
public struct Group: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var projectID: String
    public var parentGroupID: String?
    public var sortOrder: Int
    public var isExpanded: Bool
    public var createdAt: Date

    public init(
        id: String = Group.generateID(),
        name: String,
        projectID: String,
        parentGroupID: String? = nil,
        sortOrder: Int = 0,
        isExpanded: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectID = projectID
        self.parentGroupID = parentGroupID
        self.sortOrder = sortOrder
        self.isExpanded = isExpanded
        self.createdAt = createdAt
    }

    public static func generateID() -> String {
        let hex = (0..<4).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
        return "grp-\(hex)"
    }
}
