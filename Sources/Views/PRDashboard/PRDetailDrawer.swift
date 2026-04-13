import MarkdownRendering
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
    var onUpdateBranch: ((Bool) -> Void)?
    var onSendToSession: ((String) -> Void)?
    var onEnableAutoMerge: ((MergeStrategy) -> Void)?
    var onDisableAutoMerge: (() -> Void)?
    var onClosePR: (() -> Void)?

    @State private var selectedTab: PRDetailTab = .overview
    @State private var sheetCommentText: String = ""
    @State private var inlineCommentText: String = ""
    @State private var showMergeConfirm: Bool = false
    @State private var showCloseConfirm: Bool = false
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
        onUpdateBranch: ((Bool) -> Void)? = nil,
        onSendToSession: ((String) -> Void)? = nil,
        onEnableAutoMerge: ((MergeStrategy) -> Void)? = nil,
        onDisableAutoMerge: (() -> Void)? = nil,
        onClosePR: (() -> Void)? = nil
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
        self.onUpdateBranch = onUpdateBranch
        self.onEnableAutoMerge = onEnableAutoMerge
        self.onDisableAutoMerge = onDisableAutoMerge
        self.onClosePR = onClosePR
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
                .accessibilityLabel("Close detail panel")
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

            // Merge status
            let mergeable = detail?.mergeable ?? pr.mergeable
            let mergeStatus = detail?.mergeStateStatus ?? pr.mergeStateStatus
            mergeStatusBadge(mergeable: mergeable, status: mergeStatus)

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

                    autoMergeButton
                }

                if let onClosePR, pr.state == .open || pr.state == .draft {
                    Button {
                        showCloseConfirm = true
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                    .tint(theme.chrome.red)
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
            .alert("Close Pull Request", isPresented: $showCloseConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Close", role: .destructive) {
                    onClosePR?()
                }
            } message: {
                Text("Close #\(pr.number) without merging?")
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
                            Button("Cancel") {
                                requestChangesText = ""
                                activeSheet = nil
                            }
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
                            Button("Cancel") {
                                sheetCommentText = ""
                                activeSheet = nil
                            }
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

    @ViewBuilder
    private var autoMergeButton: some View {
        let isEnabled = detail?.autoMergeEnabled ?? pr.autoMergeEnabled
        if isEnabled {
            if let onDisableAutoMerge {
                Button {
                    onDisableAutoMerge()
                } label: {
                    Label("Auto-merge", systemImage: "bolt.circle.fill")
                }
                .controlSize(.small)
                .tint(theme.chrome.green)
                .help("Auto-merge is enabled — click to disable")
            }
        } else if let onEnableAutoMerge {
            Menu {
                ForEach(MergeStrategy.allCases, id: \.self) { strategy in
                    Button(strategy.displayName) {
                        onEnableAutoMerge(strategy)
                    }
                }
            } label: {
                Label("Auto-merge", systemImage: "bolt.circle")
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .help("Enable auto-merge when checks and reviews pass")
        }
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

    @ViewBuilder
    private func mergeStatusBadge(mergeable: MergeableState?, status: MergeStateStatus?) -> some View {
        if pr.state == .open {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if mergeable == .conflicting {
                        Label("Merge conflicts", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(theme.chrome.red)
                    } else if status == .behind {
                        Label("Behind base branch", systemImage: "arrow.down.circle")
                            .foregroundColor(theme.chrome.orange)
                    } else if status == .blocked {
                        Label("Merging blocked", systemImage: "hand.raised.fill")
                            .foregroundColor(theme.chrome.yellow)
                    } else if status == .unstable {
                        Label("Checks failing", systemImage: "exclamationmark.circle")
                            .foregroundColor(theme.chrome.orange)
                    } else if mergeable == .mergeable && (status == .clean || status == .hasHooks) {
                        Label("Ready to merge", systemImage: "checkmark.circle.fill")
                            .foregroundColor(theme.chrome.green)
                    }
                }
                .font(.callout)

                if let onUpdateBranch, needsBranchUpdate(mergeable: mergeable, status: status) {
                    Menu {
                        Button("Merge base into branch") { onUpdateBranch(false) }
                        Button("Rebase onto base") { onUpdateBranch(true) }
                    } label: {
                        Label("Update branch", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                }
            }
        }
    }

    private func needsBranchUpdate(mergeable: MergeableState?, status: MergeStateStatus?) -> Bool {
        status == .behind || mergeable == .conflicting || status == .dirty
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
                    MarkdownView(source: body, theme: theme)
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
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            let diffFiles = files.enumerated().map { index, file in
                DiffFile(
                    id: "prfile-\(index)",
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

        var lineIndex = 0
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
                lines.append(DiffLine(index: lineIndex, type: .hunk, content: rawLine, oldLineNo: nil, newLineNo: nil))
                lineIndex += 1
            } else if rawLine.hasPrefix("+") {
                lines.append(
                    DiffLine(index: lineIndex, type: .addition, content: String(rawLine.dropFirst()), oldLineNo: nil, newLineNo: newLine))
                lineIndex += 1
                newLine += 1
            } else if rawLine.hasPrefix("-") {
                lines.append(
                    DiffLine(index: lineIndex, type: .deletion, content: String(rawLine.dropFirst()), oldLineNo: oldLine, newLineNo: nil))
                lineIndex += 1
                oldLine += 1
            } else if rawLine.hasPrefix(" ") {
                lines.append(
                    DiffLine(index: lineIndex, type: .context, content: String(rawLine.dropFirst()), oldLineNo: oldLine, newLineNo: newLine)
                )
                lineIndex += 1
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
            case .review(let review): review.submittedAt ?? Date()
            case .comment(let comment): comment.createdAt
            }
        }
    }

    private var conversationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let inlineComments = detail?.comments.filter { $0.path != nil } ?? []

                // Inline comments grouped by file
                if !inlineComments.isEmpty {
                    Text("Inline Comments")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.chrome.textDim)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    let grouped = Dictionary(grouping: inlineComments, by: { $0.path ?? "" })
                    ForEach(grouped.keys.sorted(), id: \.self) { path in
                        Text(path)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(theme.chrome.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)

                        ForEach(grouped[path] ?? []) { comment in
                            inlineCommentCard(comment)
                        }
                    }

                    Divider().padding(.vertical, 8)
                }

                // Interleave reviews and comments by date
                let items: [TimelineItem] = {
                    var all: [TimelineItem] = []
                    if let reviews = detail?.reviews {
                        all += reviews.map { .review($0) }
                    }
                    if let comments = detail?.comments {
                        // Exclude inline comments (those with a file path) — they're
                        // already shown in the grouped "Inline Comments" section above
                        all += comments.filter { $0.path == nil }.map { .comment($0) }
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
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if !review.body.isEmpty {
                    MarkdownView(source: review.body, theme: theme, mode: .inline)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            MarkdownView(source: comment.body, theme: theme, mode: .inline)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func inlineCommentCard(_ comment: PRComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(.caption)
                    .fontWeight(.semibold)
                if let line = comment.line {
                    Text("line \(line)")
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                }
                Spacer()
                Text(comment.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(theme.chrome.textDim)
            }
            MarkdownView(source: comment.body, theme: theme, mode: .inline)
                .font(.caption)
                .textSelection(.enabled)

            if let onSendToSession {
                Button {
                    let path = comment.path ?? ""
                    let lineInfo = comment.line.map { " line \($0)" } ?? ""
                    let context = "Address the review comment on \(path)\(lineInfo):\n\n\(comment.body)"
                    onSendToSession(context)
                } label: {
                    Label("Send to Session", systemImage: "paperplane")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.chrome.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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

}

// MARK: - Tab Enum

enum PRDetailTab: String, CaseIterable {
    case overview
    case checks
    case diff
    case conversation
}
