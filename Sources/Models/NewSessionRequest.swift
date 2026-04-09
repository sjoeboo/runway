import Foundation

/// Request struct for creating a new session from a dialog.
public struct NewSessionRequest: Sendable {
    public let title: String
    public let projectID: String?
    public let parentID: String?
    public let path: String
    public let tool: Tool
    public let useWorktree: Bool
    public let branchName: String?
    public let permissionMode: PermissionMode
    public let useHappy: Bool
    public let initialPrompt: String?
    public let issueNumber: Int?

    public init(
        title: String,
        projectID: String?,
        parentID: String? = nil,
        path: String,
        tool: Tool,
        useWorktree: Bool,
        branchName: String?,
        permissionMode: PermissionMode = .default,
        useHappy: Bool = false,
        initialPrompt: String? = nil,
        issueNumber: Int? = nil
    ) {
        self.title = title
        self.projectID = projectID
        self.parentID = parentID
        self.path = path
        self.tool = tool
        self.useWorktree = useWorktree
        self.branchName = branchName
        self.permissionMode = permissionMode
        self.useHappy = useHappy
        self.initialPrompt = initialPrompt
        self.issueNumber = issueNumber
    }
}
