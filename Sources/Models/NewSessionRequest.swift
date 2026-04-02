import Foundation

/// Request struct for creating a new session from a dialog.
public struct NewSessionRequest: Sendable {
    public let title: String
    public let projectID: String?
    public let path: String
    public let tool: Tool
    public let useWorktree: Bool
    public let branchName: String?
    public let permissionMode: PermissionMode

    public init(
        title: String,
        projectID: String?,
        path: String,
        tool: Tool,
        useWorktree: Bool,
        branchName: String?,
        permissionMode: PermissionMode = .default
    ) {
        self.title = title
        self.projectID = projectID
        self.path = path
        self.tool = tool
        self.useWorktree = useWorktree
        self.branchName = branchName
        self.permissionMode = permissionMode
    }
}
