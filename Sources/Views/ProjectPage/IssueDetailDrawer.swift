import GitHubOperations
import Models
import SwiftUI
import Theme

/// Detail drawer for a selected GitHub issue, showing body, timeline, and actions.
public struct IssueDetailDrawer: View {
    let issue: GitHubIssue
    let detail: IssueDetail?
    let labels: [IssueLabel]
    let isLoading: Bool
    let onClose: () -> Void
    let onComment: (String) -> Void
    let onCloseIssue: (CloseReason) -> Void
    let onReopen: () -> Void
    let onEdit: (String?, String?) -> Void
    let onUpdateLabels: ([String], [String]) -> Void
    let onUpdateAssignees: ([String], [String]) -> Void
    let onStartSession: ((GitHubIssue) -> Void)?

    @State private var selectedTab: IssueDetailTab = .overview
    @State private var inlineCommentText: String = ""
    @State private var activeSheet: ActiveSheet?

    enum ActiveSheet: Identifiable {
        case edit
        case labels
        case assignees

        var id: String { String(describing: self) }
    }

    @Environment(\.theme) private var theme

    public init(
        issue: GitHubIssue,
        detail: IssueDetail? = nil,
        labels: [IssueLabel] = [],
        isLoading: Bool = false,
        onClose: @escaping () -> Void = {},
        onComment: @escaping (String) -> Void = { _ in },
        onCloseIssue: @escaping (CloseReason) -> Void = { _ in },
        onReopen: @escaping () -> Void = {},
        onEdit: @escaping (String?, String?) -> Void = { _, _ in },
        onUpdateLabels: @escaping ([String], [String]) -> Void = { _, _ in },
        onUpdateAssignees: @escaping ([String], [String]) -> Void = { _, _ in },
        onStartSession: ((GitHubIssue) -> Void)? = nil
    ) {
        self.issue = issue
        self.detail = detail
        self.labels = labels
        self.isLoading = isLoading
        self.onClose = onClose
        self.onComment = onComment
        self.onCloseIssue = onCloseIssue
        self.onReopen = onReopen
        self.onEdit = onEdit
        self.onUpdateLabels = onUpdateLabels
        self.onUpdateAssignees = onUpdateAssignees
        self.onStartSession = onStartSession
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            if isLoading && detail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tabContent
            }
        }
        .background(theme.chrome.background)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit:
                EditIssueSheet(
                    issue: issue,
                    currentBody: detail?.body ?? "",
                    onSave: onEdit
                )
            case .labels:
                ManageLabelsSheet(
                    availableLabels: labels,
                    currentLabels: detail?.labels ?? [],
                    onSave: onUpdateLabels
                )
            case .assignees:
                ManageAssigneesSheet(
                    currentAssignees: detail?.assignees ?? issue.assignees,
                    onSave: onUpdateAssignees
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                stateBadge
                Text("#\(issue.number)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(issue.title)
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Label(issue.author, systemImage: "person")
                Text(issue.createdAt, style: .relative)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Labels
            let detailLabels = detail?.labels ?? []
            if !detailLabels.isEmpty {
                FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(detailLabels, id: \.name) { label in
                        IssueLabelPill(label: label)
                    }
                }
            }

            // Assignees
            let assignees = detail?.assignees ?? issue.assignees
            if !assignees.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(assignees, id: \.self) { assignee in
                        Text(assignee)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Action bar
            HStack(spacing: 8) {
                if let onStartSession {
                    Button {
                        onStartSession(issue)
                    } label: {
                        Label("Start Session", systemImage: "terminal")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if issue.state == .open {
                    Menu {
                        Button("Completed") { onCloseIssue(.completed) }
                        Button("Not planned") { onCloseIssue(.notPlanned) }
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                } else {
                    Button("Reopen") { onReopen() }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.chrome.green)
                        .controlSize(.small)
                }

                Button("Edit") { activeSheet = .edit }
                    .controlSize(.small)

                Button("Labels") { activeSheet = .labels }
                    .controlSize(.small)

                Button("Assignees") { activeSheet = .assignees }
                    .controlSize(.small)

                Spacer()

                Button {
                    if let url = URL(string: issue.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .controlSize(.small)
                .help("Open in browser")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch issue.state {
        case .open:
            Label("Open", systemImage: "circle.fill")
                .font(.callout)
                .foregroundColor(theme.chrome.green)
        case .closed:
            Label("Closed", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundColor(theme.chrome.purple)
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(IssueDetailTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text(tabTitle(tab))
                                .font(.subheadline)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                            Text("^\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundColor(selectedTab == tab ? theme.chrome.accent : theme.chrome.textDim)

                        Rectangle()
                            .fill(selectedTab == tab ? theme.chrome.accent : .clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
            Spacer()
        }
        .background(theme.chrome.surface)
    }

    private func tabTitle(_ tab: IssueDetailTab) -> String {
        switch tab {
        case .overview:
            return "Overview"
        case .timeline:
            let count = (detail?.comments.count ?? 0) + (detail?.timelineEvents.count ?? 0)
            return count > 0 ? "Timeline (\(count))" : "Timeline"
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .timeline:
            timelineTab
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let body = detail?.body, !body.isEmpty {
                    renderMarkdown(body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
                } else {
                    Text("No description provided")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Timeline Tab

    private var timelineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let items = timelineItems
                ForEach(items) { item in
                    switch item {
                    case .comment(let comment):
                        commentCard(comment)
                    case .event(let event):
                        eventRow(event)
                    }
                }

                // Comment input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a comment")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $inlineCommentText)
                        .frame(height: 60)
                        .font(.body)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.chrome.border, lineWidth: 1)
                        )
                    HStack {
                        Spacer()
                        Button("Comment") {
                            guard !inlineCommentText.isEmpty else { return }
                            onComment(inlineCommentText)
                            inlineCommentText = ""
                        }
                        .controlSize(.small)
                        .disabled(inlineCommentText.isEmpty)
                    }
                }
            }
            .padding(12)
        }
    }

    /// Unified timeline: comments + events sorted chronologically.
    private enum TimelineItem: Identifiable {
        case comment(IssueComment)
        case event(IssueTimelineEvent)

        var id: String {
            switch self {
            case .comment(let comment): "comment-\(comment.id)"
            case .event(let event): "event-\(event.id)"
            }
        }

        var date: Date {
            switch self {
            case .comment(let comment): comment.createdAt
            case .event(let event): event.createdAt
            }
        }
    }

    private var timelineItems: [TimelineItem] {
        var all: [TimelineItem] = []
        if let comments = detail?.comments {
            all += comments.map { .comment($0) }
        }
        if let events = detail?.timelineEvents {
            all += events.map { .event($0) }
        }
        return all.sorted { $0.date < $1.date }
    }

    private func commentCard(_ comment: IssueComment) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.chrome.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(comment.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                renderMarkdown(comment.body, inlineOnly: true)
                    .font(.body)
                    .foregroundColor(theme.chrome.text)
                    .textSelection(.enabled)
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func eventRow(_ event: IssueTimelineEvent) -> some View {
        HStack(spacing: 6) {
            eventIcon(event.event)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(event.actor)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            eventDescription(event)

            Spacer()

            Text(event.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }

    private func eventIcon(_ event: String) -> some View {
        let icon: String =
            switch event {
            case "labeled", "unlabeled": "tag"
            case "assigned", "unassigned": "person.badge.plus"
            case "closed": "xmark.circle"
            case "reopened": "arrow.counterclockwise"
            case "cross-referenced": "link"
            case "renamed": "pencil"
            case "milestoned", "demilestoned": "flag"
            default: "circle.fill"
            }
        return Image(systemName: icon)
    }

    @ViewBuilder
    private func eventDescription(_ event: IssueTimelineEvent) -> some View {
        switch event.event {
        case "labeled":
            HStack(spacing: 4) {
                Text("added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let label = event.label {
                    IssueLabelPill(label: label)
                }
            }
        case "unlabeled":
            HStack(spacing: 4) {
                Text("removed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let label = event.label {
                    IssueLabelPill(label: label)
                }
            }
        case "assigned":
            Text("assigned **\(event.assignee ?? "")**")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "unassigned":
            Text("unassigned **\(event.assignee ?? "")**")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "closed":
            Text("closed this")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "reopened":
            Text("reopened this")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "cross-referenced":
            if let source = event.source {
                HStack(spacing: 4) {
                    Text("referenced in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: source.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("\(source.type == "pullRequest" ? "PR" : "Issue") #\(source.number)")
                            .font(.caption)
                            .foregroundColor(theme.chrome.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        case "renamed":
            if let rename = event.rename {
                Text("renamed from \"\(rename.from)\" to \"\(rename.to)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        default:
            Text(event.event)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func renderMarkdown(_ source: String, inlineOnly: Bool = false) -> Text {
        let syntax: AttributedString.MarkdownParsingOptions.InterpretedSyntax =
            inlineOnly ? .inlineOnlyPreservingWhitespace : .full
        if let attributed = try? AttributedString(
            markdown: source, options: .init(interpretedSyntax: syntax)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }
}

// MARK: - Tab Enum

enum IssueDetailTab: String, CaseIterable {
    case overview
    case timeline
}

// MARK: - Issue Label Pill

struct IssueLabelPill: View {
    let label: IssueDetailLabel

    @Environment(\.theme) private var theme

    private var pillColor: Color {
        Color(hex: label.color) ?? theme.chrome.accent
    }

    var body: some View {
        Text(label.name)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.15))
            .overlay(Capsule().strokeBorder(pillColor.opacity(0.5), lineWidth: 0.5))
            .clipShape(Capsule())
            .foregroundColor(pillColor)
    }
}
