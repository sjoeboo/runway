import GitHubOperations
import Models
import SwiftUI
import Theme

// MARK: - Tab Enum

private enum ProjectTab {
    case issues
    case prs
}

// MARK: - ProjectPageView

public struct ProjectPageView: View {
    let project: Project
    let issues: [GitHubIssue]
    let pullRequests: [PullRequest]
    let labels: [IssueLabel]
    let isLoadingIssues: Bool
    let onRefreshIssues: () -> Void
    let onCreateIssue: (String, String, [String]) -> Void
    let onSelectIssue: (GitHubIssue?) -> Void
    var selectedIssueID: String?
    var issueDetail: IssueDetail?
    var isLoadingIssueDetail: Bool = false
    var onCommentOnIssue: ((GitHubIssue, String) -> Void)?
    var onCloseIssue: ((GitHubIssue, CloseReason) -> Void)?
    var onReopenIssue: ((GitHubIssue) -> Void)?
    var onEditIssue: ((GitHubIssue, String?, String?) -> Void)?
    var onUpdateIssueLabels: ((GitHubIssue, [String], [String]) -> Void)?
    var onUpdateIssueAssignees: ((GitHubIssue, [String], [String]) -> Void)?
    var onStartSessionFromIssue: ((GitHubIssue) -> Void)?
    let onSelectPR: (PullRequest) -> Void
    let onRefreshPRs: () -> Void
    var selectedPRID: String?
    var prDetail: PRDetail?
    var onApprovePR: ((PullRequest) -> Void)?
    var onCommentPR: ((PullRequest, String) -> Void)?
    var onRequestChangesPR: ((PullRequest, String) -> Void)?
    var onMergePR: ((PullRequest, MergeStrategy) -> Void)?
    var onToggleDraftPR: ((PullRequest) -> Void)?
    var onUpdateBranchPR: ((PullRequest, Bool) -> Void)?
    var onReviewPR: ((PullRequest) -> Void)?
    var onEnableAutoMergePR: ((PullRequest, MergeStrategy) -> Void)?
    var onDisableAutoMergePR: ((PullRequest) -> Void)?
    var onDeselectPR: (() -> Void)?
    let onUpdateProject: (Project) -> Void
    let onDetectRepo: () async -> (repo: String, host: String?)?
    let onFetchLabels: () -> Void
    var templates: [SessionTemplate] = []
    var onSaveTemplate: ((SessionTemplate) -> Void)?
    var onDeleteTemplate: ((String) -> Void)?

    @Environment(\.theme) private var theme
    @State private var selectedTab: ProjectTab = .issues
    @State private var showSettings: Bool = false
    @State private var editableProject: Project

    public init(
        project: Project,
        issues: [GitHubIssue],
        pullRequests: [PullRequest],
        labels: [IssueLabel],
        isLoadingIssues: Bool,
        onRefreshIssues: @escaping () -> Void,
        onCreateIssue: @escaping (String, String, [String]) -> Void,
        onSelectIssue: @escaping (GitHubIssue?) -> Void,
        selectedIssueID: String? = nil,
        issueDetail: IssueDetail? = nil,
        isLoadingIssueDetail: Bool = false,
        onCommentOnIssue: ((GitHubIssue, String) -> Void)? = nil,
        onCloseIssue: ((GitHubIssue, CloseReason) -> Void)? = nil,
        onReopenIssue: ((GitHubIssue) -> Void)? = nil,
        onEditIssue: ((GitHubIssue, String?, String?) -> Void)? = nil,
        onUpdateIssueLabels: ((GitHubIssue, [String], [String]) -> Void)? = nil,
        onUpdateIssueAssignees: ((GitHubIssue, [String], [String]) -> Void)? = nil,
        onStartSessionFromIssue: ((GitHubIssue) -> Void)? = nil,
        onSelectPR: @escaping (PullRequest) -> Void,
        onRefreshPRs: @escaping () -> Void,
        selectedPRID: String? = nil,
        prDetail: PRDetail? = nil,
        onApprovePR: ((PullRequest) -> Void)? = nil,
        onCommentPR: ((PullRequest, String) -> Void)? = nil,
        onRequestChangesPR: ((PullRequest, String) -> Void)? = nil,
        onMergePR: ((PullRequest, MergeStrategy) -> Void)? = nil,
        onToggleDraftPR: ((PullRequest) -> Void)? = nil,
        onUpdateBranchPR: ((PullRequest, Bool) -> Void)? = nil,
        onReviewPR: ((PullRequest) -> Void)? = nil,
        onEnableAutoMergePR: ((PullRequest, MergeStrategy) -> Void)? = nil,
        onDisableAutoMergePR: ((PullRequest) -> Void)? = nil,
        onDeselectPR: (() -> Void)? = nil,
        onUpdateProject: @escaping (Project) -> Void,
        onDetectRepo: @escaping () async -> (repo: String, host: String?)?,
        onFetchLabels: @escaping () -> Void,
        templates: [SessionTemplate] = [],
        onSaveTemplate: ((SessionTemplate) -> Void)? = nil,
        onDeleteTemplate: ((String) -> Void)? = nil
    ) {
        self.project = project
        self.issues = issues
        self.pullRequests = pullRequests
        self.labels = labels
        self.isLoadingIssues = isLoadingIssues
        self.onRefreshIssues = onRefreshIssues
        self.onCreateIssue = onCreateIssue
        self.onSelectIssue = onSelectIssue
        self.selectedIssueID = selectedIssueID
        self.issueDetail = issueDetail
        self.isLoadingIssueDetail = isLoadingIssueDetail
        self.onCommentOnIssue = onCommentOnIssue
        self.onCloseIssue = onCloseIssue
        self.onReopenIssue = onReopenIssue
        self.onEditIssue = onEditIssue
        self.onUpdateIssueLabels = onUpdateIssueLabels
        self.onUpdateIssueAssignees = onUpdateIssueAssignees
        self.onStartSessionFromIssue = onStartSessionFromIssue
        self.onSelectPR = onSelectPR
        self.onRefreshPRs = onRefreshPRs
        self.selectedPRID = selectedPRID
        self.prDetail = prDetail
        self.onApprovePR = onApprovePR
        self.onCommentPR = onCommentPR
        self.onRequestChangesPR = onRequestChangesPR
        self.onMergePR = onMergePR
        self.onToggleDraftPR = onToggleDraftPR
        self.onUpdateBranchPR = onUpdateBranchPR
        self.onReviewPR = onReviewPR
        self.onEnableAutoMergePR = onEnableAutoMergePR
        self.onDisableAutoMergePR = onDisableAutoMergePR
        self.onDeselectPR = onDeselectPR
        self.onUpdateProject = onUpdateProject
        self.onDetectRepo = onDetectRepo
        self.onFetchLabels = onFetchLabels
        self.templates = templates
        self.onSaveTemplate = onSaveTemplate
        self.onDeleteTemplate = onDeleteTemplate
        self._editableProject = State(initialValue: project)
    }

    private var openIssueCount: Int {
        issues.filter { $0.state == .open }.count
    }

    private var openPRCount: Int {
        pullRequests.filter { $0.state == .open || $0.state == .draft }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                    if !project.path.isEmpty {
                        Text(project.path)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    editableProject = project
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Project Settings")
                .accessibilityLabel("Project settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Tab bar
            HStack(spacing: 0) {
                TabBarButton(
                    title: "Issues",
                    count: openIssueCount,
                    isActive: selectedTab == .issues
                ) {
                    selectedTab = .issues
                }

                TabBarButton(
                    title: "Pull Requests",
                    count: openPRCount,
                    isActive: selectedTab == .prs
                ) {
                    selectedTab = .prs
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Divider()

            // Tab content
            switch selectedTab {
            case .issues:
                ProjectIssuesTab(
                    issues: issues,
                    labels: labels,
                    isLoading: isLoadingIssues,
                    issuesEnabled: project.issuesEnabled,
                    onRefresh: onRefreshIssues,
                    onCreate: onCreateIssue,
                    onSelectIssue: onSelectIssue,
                    onFetchLabels: onFetchLabels,
                    selectedIssueID: selectedIssueID,
                    issueDetail: issueDetail,
                    isLoadingDetail: isLoadingIssueDetail,
                    onComment: onCommentOnIssue,
                    onCloseIssue: onCloseIssue,
                    onReopen: onReopenIssue,
                    onEdit: onEditIssue,
                    onUpdateLabels: onUpdateIssueLabels,
                    onUpdateAssignees: onUpdateIssueAssignees,
                    onStartSession: onStartSessionFromIssue
                )
            case .prs:
                ProjectPRsTab(
                    pullRequests: pullRequests,
                    onSelectPR: onSelectPR,
                    onRefresh: onRefreshPRs,
                    selectedPRID: selectedPRID,
                    detail: prDetail,
                    onApprove: onApprovePR,
                    onComment: onCommentPR,
                    onRequestChanges: onRequestChangesPR,
                    onMerge: onMergePR,
                    onToggleDraft: onToggleDraftPR,
                    onUpdateBranch: onUpdateBranchPR,
                    onReviewPR: onReviewPR,
                    onEnableAutoMerge: onEnableAutoMergePR,
                    onDisableAutoMerge: onDisableAutoMergePR,
                    onDeselectPR: onDeselectPR
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsSheet(
                project: $editableProject,
                themes: AppTheme.builtIn,
                templates: templates,
                onSave: { updated in onUpdateProject(updated) },
                onSaveTemplate: onSaveTemplate,
                onDeleteTemplate: onDeleteTemplate,
                onDetectRepo: onDetectRepo
            )
        }
        .onChange(of: project) { _, newProject in
            // Don't overwrite user's unsaved edits while the settings sheet is open
            if !showSettings, editableProject.id == newProject.id {
                editableProject = newProject
            }
        }
        .task(id: project.id) {
            if project.issuesEnabled {
                // Auto-refresh uses staleness check; manual refresh button bypasses it
                onRefreshIssues()
            }
        }
    }
}
