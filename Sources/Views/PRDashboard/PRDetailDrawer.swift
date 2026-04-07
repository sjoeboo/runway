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
    let onRequestChanges: (String) -> Void
    let onMerge: (MergeStrategy) -> Void
    let onToggleDraft: () -> Void
    var onSendToSession: ((String) -> Void)?

    @State private var selectedTab: PRDetailTab = .overview
    @State private var sheetCommentText: String = ""
    @State private var inlineCommentText: String = ""
    @State private var showMergeConfirm: Bool = false
    @State private var selectedMergeStrategy: MergeStrategy = .squash
    @State private var requestChangesText: String = ""
    @State private var activeSheet: ActiveSheet?

    enum ActiveSheet: Identifiable {
        case comment
        case requestChanges

        var id: String { String(describing: self) }
    }
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        detail: PRDetail? = nil,
        onClose: @escaping () -> Void = {},
        onApprove: @escaping () -> Void = {},
        onComment: @escaping (String) -> Void = { _ in },
        onRequestChanges: @escaping (String) -> Void = { _ in },
        onMerge: @escaping (MergeStrategy) -> Void = { _ in },
        onToggleDraft: @escaping () -> Void = {},
        onSendToSession: ((String) -> Void)? = nil
    ) {
        self.pr = pr
        self.detail = detail
        self.onSendToSession = onSendToSession
        self.onClose = onClose
        self.onApprove = onApprove
        self.onComment = onComment
        self.onRequestChanges = onRequestChanges
        self.onMerge = onMerge
        self.onToggleDraft = onToggleDraft
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ReviewDecisionBadge(decision: pr.reviewDecision)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(pr.title)
                .font(.title3)
                .fontWeight(.semibold)

            // Repo name
            Text(pr.repo)
                .font(.callout)
                .foregroundColor(theme.chrome.cyan)

            HStack(spacing: 12) {
                Label(pr.author, systemImage: "person")
                let head = (detail?.headBranch).flatMap { $0.isEmpty ? nil : $0 } ?? pr.headBranch
                let base = (detail?.baseBranch).flatMap { $0.isEmpty ? nil : $0 } ?? pr.baseBranch
                if !head.isEmpty {
                    Label("\(head) → \(base)", systemImage: "arrow.triangle.branch")
                }
                let adds = detail?.additions ?? pr.additions
                let dels = detail?.deletions ?? pr.deletions
                if adds > 0 || dels > 0 {
                    Label("+\(adds) -\(dels)", systemImage: "doc.text")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Checks summary (from detail if available, otherwise from PR)
            let checks = detail?.checks ?? pr.checks
            if checks.total > 0 {
                detailChecksBar(checks)
            }

            // Review decision (from detail if available)
            let reviewStatus = detail?.reviewDecision ?? pr.reviewDecision
            if reviewStatus != .none {
                detailReviewBadge(reviewStatus)
            }

            // Action bar
            HStack(spacing: 8) {
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.chrome.green)
                    .controlSize(.small)

                Button("Request Changes") { activeSheet = .requestChanges }
                    .controlSize(.small)

                Button("Comment") { activeSheet = .comment }
                    .controlSize(.small)

                Spacer()

                if pr.isDraft {
                    Button("Mark Ready") { onToggleDraft() }
                        .controlSize(.small)
                        .tint(theme.chrome.accent)
                } else if pr.state == .open {
                    Button("Convert to Draft") { onToggleDraft() }
                        .controlSize(.small)
                }

                if !pr.isDraft && pr.state == .open {
                    Menu {
                        ForEach(MergeStrategy.allCases, id: \.self) { strategy in
                            Button(strategy.displayName) {
                                selectedMergeStrategy = strategy
                                showMergeConfirm = true
                            }
                        }
                    } label: {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                }

                if let onSendToSession {
                    Button {
                        let context = "Review PR #\(pr.number): \(pr.title)"
                        onSendToSession(context)
                    } label: {
                        Image(systemName: "paperplane")
                    }
                    .controlSize(.small)
                    .help("Send to linked session")
                }

                Button {
                    if let url = URL(string: pr.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .controlSize(.small)
                .help("Open in browser")
            }
            .alert("Merge Pull Request", isPresented: $showMergeConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Merge", role: .destructive) {
                    onMerge(selectedMergeStrategy)
                }
            } message: {
                Text("This will \(selectedMergeStrategy.displayName.lowercased()) #\(pr.number) into \(pr.baseBranch).")
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .requestChanges:
                    VStack(spacing: 12) {
                        Text("Request Changes on #\(pr.number)")
                            .font(.headline)
                        TextEditor(text: $requestChangesText)
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.3))
                        HStack {
                            Button("Cancel") { activeSheet = nil }
                            Spacer()
                            Button("Submit") {
                                onRequestChanges(requestChangesText)
                                requestChangesText = ""
                                activeSheet = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.chrome.orange)
                            .disabled(requestChangesText.isEmpty)
                        }
                    }
                    .padding()
                    .frame(width: 400)
                case .comment:
                    VStack(spacing: 12) {
                        Text("Comment on #\(pr.number)")
                            .font(.headline)
                        TextEditor(text: $sheetCommentText)
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.3))
                        HStack {
                            Button("Cancel") { activeSheet = nil }
                            Spacer()
                            Button("Comment") {
                                onComment(sheetCommentText)
                                sheetCommentText = ""
                                activeSheet = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(sheetCommentText.isEmpty)
                        }
                    }
                    .padding()
                    .frame(width: 400)
                }
            }
        }
        .padding(12)
    }

    private func detailChecksBar(_ checks: CheckSummary) -> some View {
        HStack(spacing: 8) {
            if checks.passed > 0 {
                Label("\(checks.passed) passed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(theme.chrome.green)
            }
            if checks.pending > 0 {
                Label("\(checks.pending) pending", systemImage: "clock.fill")
                    .foregroundColor(theme.chrome.yellow)
            }
            if checks.failed > 0 {
                Label("\(checks.failed) failed", systemImage: "xmark.circle.fill")
                    .foregroundColor(theme.chrome.red)
            }
        }
        .font(.callout)
    }

    private func detailReviewBadge(_ decision: ReviewDecision) -> some View {
        HStack(spacing: 4) {
            switch decision {
            case .approved:
                Label("Approved", systemImage: "checkmark.circle.fill")
                    .foregroundColor(theme.chrome.green)
            case .changesRequested:
                Label("Changes requested", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(theme.chrome.orange)
            case .pending:
                Label("Review required", systemImage: "clock")
                    .foregroundColor(theme.chrome.yellow)
            case .none:
                EmptyView()
            }
        }
        .font(.callout)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(PRDetailTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text(tabTitle(tab))
                                .font(.subheadline)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                            // Show shortcut hint for discoverability
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

    private func tabTitle(_ tab: PRDetailTab) -> String {
        switch tab {
        case .overview:
            return "Overview"
        case .checks:
            let checks = detail?.checks ?? pr.checks
            return checks.total > 0 ? "Checks (\(checks.total))" : "Checks"
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
        case .checks:
            checksTab
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

    private var checksTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let runs = detail?.checkRuns, !runs.isEmpty {
                    // Summary bar at top
                    let checks = detail?.checks ?? pr.checks
                    detailChecksBar(checks)
                        .padding(.bottom, 8)

                    ForEach(runs) { run in
                        checkRunRow(run)
                    }
                } else {
                    let checks = detail?.checks ?? pr.checks
                    if checks.total > 0 {
                        // Have summary counts but no individual runs yet
                        detailChecksBar(checks)
                            .padding(.bottom, 8)
                        Text("Loading check details…")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        EmptyStateView(
                            title: "No Checks",
                            subtitle: "No CI checks are configured for this PR",
                            systemImage: "checkmark.shield"
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkRunRow(_ run: CheckRun) -> some View {
        HStack(spacing: 8) {
            checkStatusIcon(run.status)
                .frame(width: 16)

            Text(run.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(run.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let urlString = run.detailsURL, let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(theme.chrome.accent)
                }
                .buttonStyle(.plain)
                .help("Open check details")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(checkRunBackground(run.status))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func checkStatusIcon(_ status: CheckStatus) -> some View {
        switch status {
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(theme.chrome.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(theme.chrome.red)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundColor(theme.chrome.yellow)
        }
    }

    private func checkRunBackground(_ status: CheckStatus) -> some View {
        switch status {
        case .failed:
            return theme.chrome.red.opacity(0.08)
        case .pending:
            return theme.chrome.yellow.opacity(0.05)
        case .passed:
            return theme.chrome.surface.opacity(1.0)
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
                    lines: file.patch.map { parsePatchLines($0) } ?? []
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

    /// Parse a per-file patch (from gh --json files) into DiffLines.
    /// Unlike full unified diffs, these don't have "diff --git" or "+++ b/" headers.
    private func parsePatchLines(_ patch: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0

        for rawLine in patch.components(separatedBy: "\n") {
            if rawLine.hasPrefix("@@") {
                let parts = rawLine.components(separatedBy: " ")
                if parts.count >= 3 {
                    let newPart = parts[2]
                    let nums = newPart.dropFirst().components(separatedBy: ",")
                    newLine = Int(nums[0]) ?? 0
                    let oldPart = parts[1]
                    let oldNums = oldPart.dropFirst().components(separatedBy: ",")
                    oldLine = Int(oldNums[0]) ?? 0
                }
                lines.append(DiffLine(type: .hunk, content: rawLine, oldLineNo: nil, newLineNo: nil))
            } else if rawLine.hasPrefix("+") {
                lines.append(DiffLine(type: .addition, content: String(rawLine.dropFirst()), oldLineNo: nil, newLineNo: newLine))
                newLine += 1
            } else if rawLine.hasPrefix("-") {
                lines.append(DiffLine(type: .deletion, content: String(rawLine.dropFirst()), oldLineNo: oldLine, newLineNo: nil))
                oldLine += 1
            } else if rawLine.hasPrefix(" ") {
                lines.append(DiffLine(type: .context, content: String(rawLine.dropFirst()), oldLineNo: oldLine, newLineNo: newLine))
                oldLine += 1
                newLine += 1
            }
        }

        return lines
    }

    /// Unified timeline item for sorting reviews and comments together.
    private enum TimelineItem: Identifiable {
        case review(PRReview)
        case comment(PRComment)

        var id: String {
            switch self {
            case .review(let review): "review-\(review.id)"
            case .comment(let comment): "comment-\(comment.id)"
            }
        }

        var date: Date {
            switch self {
            case .review(let review): review.submittedAt ?? .distantPast
            case .comment(let comment): comment.createdAt
            }
        }
    }

    private var conversationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Interleave reviews and comments by date
                let items: [TimelineItem] = {
                    var all: [TimelineItem] = []
                    if let reviews = detail?.reviews {
                        all += reviews.map { .review($0) }
                    }
                    if let comments = detail?.comments {
                        all += comments.map { .comment($0) }
                    }
                    return all.sorted { $0.date < $1.date }
                }()

                ForEach(items) { item in
                    switch item {
                    case .review(let review): reviewCard(review)
                    case .comment(let comment): commentCard(comment)
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

    private func reviewCard(_ review: PRReview) -> some View {
        HStack(spacing: 0) {
            // Colored left border indicating review decision
            RoundedRectangle(cornerRadius: 1)
                .fill(reviewColor(review.state))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: reviewIcon(review.state))
                        .font(.caption)
                        .foregroundColor(reviewColor(review.state))
                    Text(review.author)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text(review.state.lowercased())
                        .font(.caption)
                        .foregroundColor(reviewColor(review.state))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(reviewColor(review.state).opacity(0.1))
                        .cornerRadius(4)
                }
                if !review.body.isEmpty {
                    renderMarkdown(review.body, inlineOnly: true)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .cornerRadius(6)
    }

    private func reviewIcon(_ state: String) -> String {
        switch state.uppercased() {
        case "APPROVED": "checkmark.circle.fill"
        case "CHANGES_REQUESTED": "exclamationmark.triangle.fill"
        default: "clock"
        }
    }

    private func commentCard(_ comment: PRComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(.callout)
                    .fontWeight(.semibold)
                if let path = comment.path {
                    Text(path)
                        .font(.caption)
                        .foregroundColor(theme.chrome.accent)
                }
            }
            renderMarkdown(comment.body, inlineOnly: true)
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
                .font(.callout)
                .foregroundColor(theme.chrome.green)
        case .draft:
            Label("Draft", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .merged:
            Label("Merged", systemImage: "arrow.triangle.merge")
                .font(.callout)
                .foregroundColor(theme.chrome.purple)
        case .closed:
            Label("Closed", systemImage: "xmark.circle.fill")
                .font(.callout)
                .foregroundColor(theme.chrome.red)
        }
    }

    /// Render markdown as styled Text. Use `inlineOnly: true` for comments/reviews
    /// (preserves whitespace), `false` for PR body (supports headings, lists).
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

    private func stripHTML(_ html: String) -> String {
        // Strip HTML tags for plain text display
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Tab Enum

enum PRDetailTab: String, CaseIterable {
    case overview
    case checks
    case diff
    case conversation
}
