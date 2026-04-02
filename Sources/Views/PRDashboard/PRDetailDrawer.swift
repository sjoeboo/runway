import Models
import SwiftUI
import Theme

/// Sliding drawer showing detailed PR information with tabbed content.
public struct PRDetailDrawer: View {
    let pr: PullRequest
    let detail: PRDetail?
    let onClose: () -> Void
    let onApprove: () -> Void
    let onComment: (String) -> Void

    @State private var selectedTab: PRDetailTab = .overview
    @State private var commentText: String = ""
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        detail: PRDetail? = nil,
        onClose: @escaping () -> Void = {},
        onApprove: @escaping () -> Void = {},
        onComment: @escaping (String) -> Void = { _ in }
    ) {
        self.pr = pr
        self.detail = detail
        self.onClose = onClose
        self.onApprove = onApprove
        self.onComment = onComment
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .background(theme.chrome.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                stateBadge
                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                reviewBadge
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
            }

            Text(pr.title)
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Label(pr.author, systemImage: "person")
                Label("\(pr.headBranch) → \(pr.baseBranch)", systemImage: "arrow.triangle.branch")
                Label("+\(pr.additions) -\(pr.deletions)", systemImage: "doc.text")
            }
            .font(.caption)
            .foregroundColor(theme.chrome.textDim)

            // Checks summary
            if pr.checks.total > 0 {
                checksBar
            }

            // Action buttons
            HStack(spacing: 8) {
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.chrome.green)
                    .controlSize(.small)

                Button("Open in Browser") {
                    if let url = URL(string: pr.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var checksBar: some View {
        HStack(spacing: 8) {
            if pr.checks.passed > 0 {
                Label("\(pr.checks.passed) passed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(theme.chrome.green)
            }
            if pr.checks.pending > 0 {
                Label("\(pr.checks.pending) pending", systemImage: "clock.fill")
                    .foregroundColor(theme.chrome.yellow)
            }
            if pr.checks.failed > 0 {
                Label("\(pr.checks.failed) failed", systemImage: "xmark.circle.fill")
                    .foregroundColor(theme.chrome.red)
            }
        }
        .font(.caption)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PRDetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Text(tabTitle(tab))
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? theme.chrome.accent : theme.chrome.textDim)

                        Rectangle()
                            .fill(selectedTab == tab ? theme.chrome.accent : .clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(theme.chrome.surface)
    }

    private func tabTitle(_ tab: PRDetailTab) -> String {
        switch tab {
        case .overview:
            return "Overview"
        case .diff:
            let count = detail?.files.count ?? pr.changedFiles
            return count > 0 ? "Diff (\(count))" : "Diff"
        case .conversation:
            let count = (detail?.comments.count ?? 0) + (detail?.reviews.count ?? 0)
            return count > 0 ? "Conversation (\(count))" : "Conversation"
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .diff:
            diffTab
        case .conversation:
            conversationTab
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let body = detail?.body, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
                } else {
                    Text("No description provided")
                        .foregroundColor(theme.chrome.textDim)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var diffTab: some View {
        if let files = detail?.files, !files.isEmpty {
            let diffFiles = files.map { file in
                DiffFile(
                    path: file.path,
                    additions: file.additions,
                    deletions: file.deletions,
                    lines: file.patch.map { DiffFile.parse(patch: $0).first?.lines ?? [] } ?? []
                )
            }
            DiffView(files: diffFiles)
        } else {
            EmptyStateView(
                title: "No Diff Available",
                subtitle: "Diff data hasn't been loaded yet",
                systemImage: "doc.text"
            )
        }
    }

    private var conversationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let reviews = detail?.reviews {
                    ForEach(reviews) { review in
                        reviewCard(review)
                    }
                }

                if let comments = detail?.comments {
                    ForEach(comments) { comment in
                        commentCard(comment)
                    }
                }

                // Comment input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a comment")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    TextEditor(text: $commentText)
                        .frame(height: 60)
                        .font(.body)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(theme.chrome.border, lineWidth: 1)
                        )
                    HStack {
                        Spacer()
                        Button("Comment") {
                            guard !commentText.isEmpty else { return }
                            onComment(commentText)
                            commentText = ""
                        }
                        .controlSize(.small)
                        .disabled(commentText.isEmpty)
                    }
                }
            }
            .padding(12)
        }
    }

    private func reviewCard(_ review: PRReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(review.author)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(review.state.lowercased())
                    .font(.caption2)
                    .foregroundColor(reviewColor(review.state))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(reviewColor(review.state).opacity(0.1))
                    .cornerRadius(4)
            }
            if !review.body.isEmpty {
                Text(review.body)
                    .font(.body)
                    .foregroundColor(theme.chrome.text)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .cornerRadius(6)
    }

    private func commentCard(_ comment: PRComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(.caption)
                    .fontWeight(.semibold)
                if let path = comment.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(theme.chrome.accent)
                }
            }
            Text(comment.body)
                .font(.body)
                .foregroundColor(theme.chrome.text)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .cornerRadius(6)
    }

    private func reviewColor(_ state: String) -> SwiftUI.Color {
        switch state.uppercased() {
        case "APPROVED": theme.chrome.green
        case "CHANGES_REQUESTED": theme.chrome.orange
        default: theme.chrome.yellow
        }
    }

    // MARK: - State Badge

    @ViewBuilder
    private var stateBadge: some View {
        switch pr.state {
        case .open:
            Label("Open", systemImage: "circle.fill")
                .font(.caption)
                .foregroundColor(theme.chrome.green)
        case .draft:
            Label("Draft", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
        case .merged:
            Label("Merged", systemImage: "arrow.triangle.merge")
                .font(.caption)
                .foregroundColor(theme.chrome.purple)
        case .closed:
            Label("Closed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(theme.chrome.red)
        }
    }

    @ViewBuilder
    private var reviewBadge: some View {
        switch pr.reviewDecision {
        case .approved:
            Label("Approved", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(theme.chrome.green)
        case .changesRequested:
            Label("Changes", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(theme.chrome.orange)
        case .pending:
            Label("Review needed", systemImage: "clock")
                .font(.caption2)
                .foregroundColor(theme.chrome.yellow)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Tab Enum

enum PRDetailTab: String, CaseIterable {
    case overview
    case diff
    case conversation
}
