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
                        .font(.system(size: 16, weight: .semibold))
                    if !project.path.isEmpty {
                        Text(project.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.chrome.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    editableProject = project
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
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
                    onSelectPR: onSelectPR
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsSheet(
                project: $editableProject,
                themes: ThemeManager().allThemes,
                onSave: { updated in onUpdateProject(updated) },
                onDetectRepo: onDetectRepo
            )
        }
        .onAppear {
            if project.issuesEnabled {
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
                        .font(.system(size: 13))
                        .foregroundColor(isActive ? theme.chrome.text : theme.chrome.textDim)

                    Text("\(count)")
                        .font(.caption2)
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
