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
    let onOpenIssue: (GitHubIssue) -> Void
    let onFetchLabels: () -> Void

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
        onOpenIssue: @escaping (GitHubIssue) -> Void,
        onFetchLabels: @escaping () -> Void
    ) {
        self.issues = issues
        self.labels = labels
        self.isLoading = isLoading
        self.issuesEnabled = issuesEnabled
        self.onRefresh = onRefresh
        self.onCreate = onCreate
        self.onOpenIssue = onOpenIssue
        self.onFetchLabels = onFetchLabels
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
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh issues")

                Button {
                    onFetchLabels()
                    showNewIssue = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
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
                .foregroundColor(theme.chrome.textDim)
            Text("Issues not enabled")
                .font(.headline)
                .foregroundColor(theme.chrome.textDim)
            Text("Enable issues in Project Settings to use this feature.")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading issues…")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(theme.chrome.textDim)
            Text("No \(filter.rawValue.lowercased()) issues")
                .font(.headline)
                .foregroundColor(theme.chrome.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var issuesList: some View {
        List {
            ForEach(filteredIssues) { issue in
                IssueRowView(issue: issue, labels: labels)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenIssue(issue) }
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
                        .foregroundColor(theme.chrome.textDim)
                    Text(issue.title)
                        .font(.body)
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
                    .font(.caption2)
                    .foregroundColor(theme.chrome.textDim)
            }

            Spacer()
        }
        .padding(.vertical, 2)
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
