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
    let onOpenIssue: (GitHubIssue) -> Void
    let onSelectPR: (PullRequest) -> Void
    let onRefreshPRs: () -> Void
    var selectedPRID: String?
    var prDetail: PRDetail?
    var onApprovePR: ((PullRequest) -> Void)?
    var onCommentPR: ((PullRequest, String) -> Void)?
    var onRequestChangesPR: ((PullRequest, String) -> Void)?
    var onMergePR: ((PullRequest, MergeStrategy) -> Void)?
    var onToggleDraftPR: ((PullRequest) -> Void)?
    var onReviewPR: ((PullRequest) -> Void)?
    let onUpdateProject: (Project) -> Void
    let onDetectRepo: () async -> (repo: String, host: String?)?
    let onFetchLabels: () -> Void

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
        onOpenIssue: @escaping (GitHubIssue) -> Void,
        onSelectPR: @escaping (PullRequest) -> Void,
        onRefreshPRs: @escaping () -> Void,
        selectedPRID: String? = nil,
        prDetail: PRDetail? = nil,
        onApprovePR: ((PullRequest) -> Void)? = nil,
        onCommentPR: ((PullRequest, String) -> Void)? = nil,
        onRequestChangesPR: ((PullRequest, String) -> Void)? = nil,
        onMergePR: ((PullRequest, MergeStrategy) -> Void)? = nil,
        onToggleDraftPR: ((PullRequest) -> Void)? = nil,
        onReviewPR: ((PullRequest) -> Void)? = nil,
        onUpdateProject: @escaping (Project) -> Void,
        onDetectRepo: @escaping () async -> (repo: String, host: String?)?,
        onFetchLabels: @escaping () -> Void
    ) {
        self.project = project
        self.issues = issues
        self.pullRequests = pullRequests
        self.labels = labels
        self.isLoadingIssues = isLoadingIssues
        self.onRefreshIssues = onRefreshIssues
        self.onCreateIssue = onCreateIssue
        self.onOpenIssue = onOpenIssue
        self.onSelectPR = onSelectPR
        self.onRefreshPRs = onRefreshPRs
        self.selectedPRID = selectedPRID
        self.prDetail = prDetail
        self.onApprovePR = onApprovePR
        self.onCommentPR = onCommentPR
        self.onRequestChangesPR = onRequestChangesPR
        self.onMergePR = onMergePR
        self.onToggleDraftPR = onToggleDraftPR
        self.onReviewPR = onReviewPR
        self.onUpdateProject = onUpdateProject
        self.onDetectRepo = onDetectRepo
        self.onFetchLabels = onFetchLabels
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Tab bar
            HStack(spacing: 0) {
                TabButton(
                    title: "Issues",
                    count: openIssueCount,
                    isActive: selectedTab == .issues
                ) {
                    selectedTab = .issues
                }

                TabButton(
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
                    onOpenIssue: onOpenIssue,
                    onFetchLabels: onFetchLabels
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
                    onReviewPR: onReviewPR
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsSheet(
                project: $editableProject,
                themes: AppTheme.builtIn,
                onSave: { updated in onUpdateProject(updated) },
                onDetectRepo: onDetectRepo
            )
        }
        .onChange(of: project) { _, newProject in
            if editableProject.id == newProject.id {
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

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(isActive ? theme.chrome.text : theme.chrome.textDim)

                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(isActive ? theme.chrome.text : theme.chrome.textDim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(theme.chrome.surface.opacity(0.6))
                        )
                }

                // Underline indicator
                Rectangle()
                    .fill(isActive ? theme.chrome.accent : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
    }
}
