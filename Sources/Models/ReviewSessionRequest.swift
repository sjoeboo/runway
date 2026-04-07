import Foundation

/// Request struct for creating a PR review session from the new session dialog.
public struct ReviewSessionRequest: Sendable {
    public let prNumber: Int
    public let repo: String
    public let host: String?
    public let sessionName: String
    public let projectID: String?
    public let permissionMode: PermissionMode
    public let initialPrompt: String

    public init(
        prNumber: Int,
        repo: String,
        host: String?,
        sessionName: String,
        projectID: String?,
        permissionMode: PermissionMode = .default,
        initialPrompt: String = "Review this PR"
    ) {
        self.prNumber = prNumber
        self.repo = repo
        self.host = host
        self.sessionName = sessionName
        self.projectID = projectID
        self.permissionMode = permissionMode
        self.initialPrompt = initialPrompt
    }
}
