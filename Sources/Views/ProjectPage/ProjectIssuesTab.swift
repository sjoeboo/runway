import GitHubOperations
import Models
import SwiftUI
import Theme

// MARK: - Issue Filter

private enum IssueFilter: String, CaseIterable {
    case open = "Open"
    case closed = "Closed"
}

// MARK: - ProjectIssuesTab

public struct ProjectIssuesTab: View {
    let issues: [GitHubIssue]
    let labels: [IssueLabel]
    let isLoading: Bool
    let issuesEnabled: Bool
    let onRefresh: () -> Void
    let onCreate: (String, String, [String]) -> Void
    let onSelectIssue: (GitHubIssue?) -> Void
    let onFetchLabels: () -> Void
    var selectedIssueID: String?
    var issueDetail: IssueDetail?
    var isLoadingDetail: Bool = false
    var onComment: ((GitHubIssue, String) -> Void)?
    var onCloseIssue: ((GitHubIssue, CloseReason) -> Void)?
    var onReopen: ((GitHubIssue) -> Void)?
    var onEdit: ((GitHubIssue, String?, String?) -> Void)?
    var onUpdateLabels: ((GitHubIssue, [String], [String]) -> Void)?
    var onUpdateAssignees: ((GitHubIssue, [String], [String]) -> Void)?
    var onStartSession: ((GitHubIssue) -> Void)?

    @AppStorage("issueListWidth") private var issueListWidth: Double = 320
    @Environment(\.theme) private var theme
    @State private var filter: IssueFilter = .open
    @State private var showNewIssue: Bool = false

    public init(
        issues: [GitHubIssue],
        labels: [IssueLabel],
        isLoading: Bool,
        issuesEnabled: Bool,
        onRefresh: @escaping () -> Void,
        onCreate: @escaping (String, String, [String]) -> Void,
        onSelectIssue: @escaping (GitHubIssue?) -> Void,
        onFetchLabels: @escaping () -> Void,
        selectedIssueID: String? = nil,
        issueDetail: IssueDetail? = nil,
        isLoadingDetail: Bool = false,
        onComment: ((GitHubIssue, String) -> Void)? = nil,
        onCloseIssue: ((GitHubIssue, CloseReason) -> Void)? = nil,
        onReopen: ((GitHubIssue) -> Void)? = nil,
        onEdit: ((GitHubIssue, String?, String?) -> Void)? = nil,
        onUpdateLabels: ((GitHubIssue, [String], [String]) -> Void)? = nil,
        onUpdateAssignees: ((GitHubIssue, [String], [String]) -> Void)? = nil,
        onStartSession: ((GitHubIssue) -> Void)? = nil
    ) {
        self.issues = issues
        self.labels = labels
        self.isLoading = isLoading
        self.issuesEnabled = issuesEnabled
        self.onRefresh = onRefresh
        self.onCreate = onCreate
        self.onSelectIssue = onSelectIssue
        self.onFetchLabels = onFetchLabels
        self.selectedIssueID = selectedIssueID
        self.issueDetail = issueDetail
        self.isLoadingDetail = isLoadingDetail
        self.onComment = onComment
        self.onCloseIssue = onCloseIssue
        self.onReopen = onReopen
        self.onEdit = onEdit
        self.onUpdateLabels = onUpdateLabels
        self.onUpdateAssignees = onUpdateAssignees
        self.onStartSession = onStartSession
    }

    private var selectedIssue: GitHubIssue? {
        issues.first(where: { $0.id == selectedIssueID })
    }

    private var filteredIssues: [GitHubIssue] {
        issues.filter { issue in
            switch filter {
            case .open: issue.state == .open
            case .closed: issue.state == .closed
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Picker("Filter", selection: $filter) {
                    ForEach(IssueFilter.allCases, id: \.self) { filterOption in
                        Text(filterOption.rawValue).tag(filterOption)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("Refresh issues")

                Button {
                    onFetchLabels()
                    showNewIssue = true
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("New issue")
                .disabled(!issuesEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !issuesEnabled {
                issuesDisabledView
            } else if isLoading && issues.isEmpty {
                loadingView
            } else if filteredIssues.isEmpty {
                emptyStateView
            } else if let issue = selectedIssue {
                HStack(spacing: 0) {
                    issuesList
                        .frame(maxWidth: CGFloat(issueListWidth))
                    ResizableDivider(width: $issueListWidth)
                    IssueDetailDrawer(
                        issue: issue,
                        detail: issueDetail,
                        labels: labels,
                        isLoading: isLoadingDetail,
                        onClose: { onSelectIssue(nil) },
                        onComment: { body in onComment?(issue, body) },
                        onCloseIssue: { reason in onCloseIssue?(issue, reason) },
                        onReopen: { onReopen?(issue) },
                        onEdit: { title, body in onEdit?(issue, title, body) },
                        onUpdateLabels: { add, remove in onUpdateLabels?(issue, add, remove) },
                        onUpdateAssignees: { add, remove in onUpdateAssignees?(issue, add, remove) },
                        onStartSession: onStartSession
                    )
                }
            } else {
                issuesList
            }
        }
        .sheet(isPresented: $showNewIssue) {
            NewIssueSheet(labels: labels, onCreate: onCreate)
        }
    }

    // MARK: - Subviews

    private var issuesDisabledView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Issues not enabled")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enable issues in Project Settings to use this feature.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading issues…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No \(filter.rawValue.lowercased()) issues")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var issuesList: some View {
        List {
            ForEach(filteredIssues) { issue in
                IssueRowView(issue: issue, labels: labels, isSelected: issue.id == selectedIssueID)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectIssue(issue) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Issue Row

private struct IssueRowView: View {
    let issue: GitHubIssue
    let labels: [IssueLabel]
    var isSelected: Bool = false

    @Environment(\.theme) private var theme

    private var stateDotColor: Color {
        issue.state == .open ? theme.chrome.green : theme.chrome.textDim
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(stateDotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("#\(issue.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(issue.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels, id: \.self) { labelName in
                            LabelPill(labelName: labelName, labels: labels)
                        }
                    }
                }

                Text(issue.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.leading, isSelected ? 0 : 3)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.chrome.accent)
                    .frame(width: 3)
            }
        }
    }
}

// MARK: - Label Pill

private struct LabelPill: View {
    let labelName: String
    let labels: [IssueLabel]

    @Environment(\.theme) private var theme

    private var pillColor: Color {
        if let label = labels.first(where: { $0.name == labelName }),
            let color = Color(hex: label.color)
        {
            return color
        }
        return theme.chrome.accent
    }

    var body: some View {
        Text(labelName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.15))
            .overlay(Capsule().strokeBorder(pillColor.opacity(0.5), lineWidth: 0.5))
            .clipShape(Capsule())
            .foregroundColor(pillColor)
    }
}
