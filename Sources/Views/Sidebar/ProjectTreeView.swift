import AppKit
import Models
import SwiftUI
import Theme

// MARK: - Sidebar Action Protocol

/// Consolidates all sidebar actions into a single protocol, replacing 11 separate callback closures.
/// The `App` target provides the concrete implementation backed by `RunwayStore`.
@MainActor
public protocol SidebarActions {
    func restartSession(id: String) async
    func forkSession(id: String)
    func deleteSession(id: String, deleteWorktree: Bool)
    func newSession(projectID: String?, parentID: String?)
    func newProject()
    func renameSession(id: String, title: String)
    func renameProject(id: String, name: String)
    func deleteProject(id: String)
    func reorderSessions(in projectID: String?, fromOffsets: IndexSet, toOffset: Int)
    func reorderProjects(fromOffsets: IndexSet, toOffset: Int)
    func selectProject(_ id: String?)
    func selectSession(_ id: String?)
    func selectPR(_ pr: PullRequest?) async
    func reviewPR(_ pr: PullRequest)
}

/// Sidebar view showing the hierarchical project tree with sessions.
///
/// Takes 4 data parameters + 1 actions object, replacing the previous 14-parameter init.
public struct ProjectTreeView: View {
    let projects: [Project]
    let sessions: [Session]
    let sessionPRs: [String: PullRequest]
    let provisioningWorktreeIDs: Set<String>
    let actions: SidebarActions
    @Binding var selectedSessionID: String?
    @Binding var searchQuery: String
    @Binding var focusSearch: Bool
    @FocusState private var isSearchFocused: Bool
    @Environment(\.theme) private var theme

    public init(
        projects: [Project],
        sessions: [Session],
        sessionPRs: [String: PullRequest] = [:],
        provisioningWorktreeIDs: Set<String> = [],
        selectedSessionID: Binding<String?>,
        searchQuery: Binding<String>,
        focusSearch: Binding<Bool> = .constant(false),
        actions: SidebarActions
    ) {
        self.projects = projects
        self.sessions = sessions
        self.sessionPRs = sessionPRs
        self.provisioningWorktreeIDs = provisioningWorktreeIDs
        self._selectedSessionID = selectedSessionID
        self._searchQuery = searchQuery
        self._focusSearch = focusSearch
        self.actions = actions
    }

    private var filteredSessions: [Session] {
        guard !searchQuery.isEmpty else { return sessions }
        let query = searchQuery.lowercased()
        return sessions.filter {
            $0.title.lowercased().contains(query)
                || ($0.worktreeBranch?.lowercased().contains(query) ?? false)
        }
    }

    private var filteredProjects: [Project] {
        guard !searchQuery.isEmpty else { return projects }
        let query = searchQuery.lowercased()
        let matchedProjectIDs = Set(filteredSessions.compactMap(\.projectID))
        return projects.filter {
            $0.name.lowercased().contains(query) || matchedProjectIDs.contains($0.id)
        }
    }

    public var body: some View {
        let sessionsByProject = Dictionary(grouping: filteredSessions) { $0.projectID ?? "" }
        List(selection: $selectedSessionID) {
            ForEach(filteredProjects) { project in
                ProjectSection(
                    project: project,
                    sessions: sessionsByProject[project.id] ?? [],
                    sessionPRs: sessionPRs,
                    provisioningWorktreeIDs: provisioningWorktreeIDs,
                    actions: actions
                )
            }
            .onMove { fromOffsets, toOffset in
                actions.reorderProjects(fromOffsets: fromOffsets, toOffset: toOffset)
            }

            // Ungrouped sessions
            let ungrouped = sessionsByProject[""] ?? []
            let ungroupedRoots = ungrouped.filter { $0.parentID == nil }
            if !ungrouped.isEmpty {
                Section("Sessions") {
                    ForEach(ungroupedRoots) { session in
                        SessionRowView(
                            session: session,
                            linkedPR: sessionPRs[session.id],
                            isProvisioningWorktree: provisioningWorktreeIDs.contains(session.id),
                            actions: actions
                        )
                        .tag(session.id)

                        ForEach(ungrouped.filter { $0.parentID == session.id }) { child in
                            SessionRowView(
                                session: child,
                                linkedPR: sessionPRs[child.id],
                                isProvisioningWorktree: provisioningWorktreeIDs.contains(child.id),
                                actions: actions
                            )
                            .padding(.leading, 20)
                            .tag(child.id)
                        }
                    }
                    .onMove { fromOffsets, toOffset in
                        actions.reorderSessions(in: nil, fromOffsets: fromOffsets, toOffset: toOffset)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
                TextField("Search sessions…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isSearchFocused)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.chrome.surface)
        }
        .onChange(of: focusSearch) { _, focused in
            if focused {
                isSearchFocused = true
                focusSearch = false
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    actions.newProject()
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                        .font(.callout)
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.chrome.surface)
        }
    }
}

// MARK: - Project Section (collapsible with inline "+")

struct ProjectSection: View {
    let project: Project
    let sessions: [Session]
    let sessionPRs: [String: PullRequest]
    let provisioningWorktreeIDs: Set<String>
    let actions: SidebarActions
    @AppStorage private var isExpanded: Bool
    @State private var isHeaderHovered = false
    @State private var isRenaming = false
    @State private var editName: String = ""
    @State private var showDeleteConfirmation = false
    @Environment(\.theme) private var theme

    init(
        project: Project,
        sessions: [Session],
        sessionPRs: [String: PullRequest],
        provisioningWorktreeIDs: Set<String> = [],
        actions: SidebarActions
    ) {
        self.project = project
        self.sessions = sessions
        self.sessionPRs = sessionPRs
        self.provisioningWorktreeIDs = provisioningWorktreeIDs
        self.actions = actions
        self._isExpanded = AppStorage(wrappedValue: true, "project.expanded.\(project.id)")
    }

    private var rootSessions: [Session] {
        sessions.filter { $0.parentID == nil }
    }

    private func children(of sessionID: String) -> [Session] {
        sessions.filter { $0.parentID == sessionID }
    }

    var body: some View {
        // Project header as a plain list row — avoids Section's hover disclosure arrow
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                .frame(width: 16)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }

            if isRenaming {
                TextField("Project name", text: $editName)
                    .onSubmit {
                        if !editName.isEmpty {
                            actions.renameProject(id: project.id, name: editName)
                        }
                        isRenaming = false
                    }
                    .textFieldStyle(.plain)
                    .font(.system(.callout, weight: .semibold))
                    .onAppear { editName = project.name }
            } else {
                Text(project.name)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundColor(theme.chrome.text)
                    .accessibilityLabel("Project: \(project.name)")
                    .accessibilityHint("Tap to open project settings")
                    .onTapGesture {
                        actions.selectProject(project.id)
                    }
            }
            Spacer()

            if !isRenaming {
                Button {
                    actions.newSession(projectID: project.id, parentID: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                        .foregroundColor(isHeaderHovered ? theme.chrome.text : theme.chrome.textDim)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New session in \(project.name)")
            }
        }
        .onHover { hovering in
            isHeaderHovered = hovering
        }
        .contextMenu {
            Button {
                isRenaming = true
            } label: {
                Label("Rename Project", systemImage: "pencil")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Button {
                actions.selectProject(project.id)
            } label: {
                Label("Project Settings\u{2026}", systemImage: "gear")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Remove Project", systemImage: "folder.badge.minus")
            }
        }
        .confirmationDialog(
            "Remove \"\(project.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Project and Sessions", role: .destructive) {
                actions.deleteProject(id: project.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the project and all its sessions from Runway. Worktrees on disk will not be deleted.")
        }

        // Session rows (flat list items, not inside a Section)
        if isExpanded {
            ForEach(rootSessions) { session in
                SessionRowView(
                    session: session,
                    linkedPR: sessionPRs[session.id],
                    isProvisioningWorktree: provisioningWorktreeIDs.contains(session.id),
                    actions: actions
                )
                .tag(session.id)

                // Child sessions indented under parent
                ForEach(children(of: session.id)) { child in
                    SessionRowView(
                        session: child,
                        linkedPR: sessionPRs[child.id],
                        isProvisioningWorktree: provisioningWorktreeIDs.contains(child.id),
                        actions: actions
                    )
                    .padding(.leading, 20)
                    .tag(child.id)
                }
            }
            .onMove { fromOffsets, toOffset in
                actions.reorderSessions(in: project.id, fromOffsets: fromOffsets, toOffset: toOffset)
            }
        }
    }
}

// MARK: - Session Row

/// A single session row in the sidebar with hover-revealed action buttons.
struct SessionRowView: View {
    let session: Session
    var linkedPR: PullRequest?
    var isProvisioningWorktree: Bool = false
    let actions: SidebarActions
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var editTitle: String = ""
    @State private var showDeleteConfirmation = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Session name", text: $editTitle)
                        .onSubmit {
                            if !editTitle.isEmpty {
                                actions.renameSession(id: session.id, title: editTitle)
                            }
                            isRenaming = false
                        }
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .default))
                        .onAppear { editTitle = session.title }
                } else {
                    HStack(spacing: 4) {
                        Text(session.title)
                            .font(.system(.body, design: .default))
                            .foregroundStyle(.primary)
                        if session.parentID != nil {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if isProvisioningWorktree {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Creating worktree\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let branch = session.worktreeBranch {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let activity = session.lastActivityText {
                    Text(activity)
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Linked PR info
                if linkedPR == nil, let issueNum = session.issueNumber {
                    Text("#\(issueNum)")
                        .font(.caption)
                        .foregroundColor(theme.chrome.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(theme.chrome.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let pr = linkedPR {
                    HStack(spacing: 4) {
                        Button {
                            Task { await actions.selectPR(pr) }
                        } label: {
                            Text("#\(pr.number)")
                                .font(.caption2)
                                .foregroundColor(pr.numberColor(chrome: theme.chrome))
                        }
                        .buttonStyle(LinkButtonStyle())
                        .help("View PR #\(pr.number) details")
                        CheckSummaryBadge(checks: pr.checks)
                        ReviewDecisionBadge(decision: pr.reviewDecision, style: .iconOnly)
                        if pr.additions > 0 || pr.deletions > 0 {
                            HStack(spacing: 1) {
                                Text("+\(pr.additions)")
                                    .foregroundColor(theme.chrome.green)
                                Text("-\(pr.deletions)")
                                    .foregroundColor(theme.chrome.red)
                            }
                            .font(.caption2)
                        }
                        if pr.isDraft {
                            Text("Draft")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()

            HStack(spacing: 4) {
                Button {
                    Task { await actions.restartSession(id: session.id) }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Restart session")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Delete session")
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)

            if !isHovered {
                HStack(spacing: 4) {
                    if session.useHappy {
                        Image(systemName: "iphone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if session.tool != .claude {
                        Text(session.tool.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(theme.chrome.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                isRenaming = true
            } label: {
                Label("Rename Session", systemImage: "pencil")
            }

            if session.worktreeBranch != nil {
                Button {
                    actions.forkSession(id: session.id)
                } label: {
                    Label("Fork Session", systemImage: "arrow.triangle.branch")
                }
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.path, forType: .string)
            } label: {
                Label("Copy Worktree Path", systemImage: "doc.on.doc")
            }

            if let branch = session.worktreeBranch {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(branch, forType: .string)
                } label: {
                    Label("Copy Branch Name", systemImage: "arrow.triangle.branch")
                }
            }

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.path)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Button {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Terminal", session.path]
                try? process.run()
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }

            if linkedPR != nil {
                Divider()

                if let prURL = linkedPR?.url, let url = URL(string: prURL) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open PR in Browser", systemImage: "safari")
                    }
                }
            }

            Divider()

            Button {
                Task { await actions.restartSession(id: session.id) }
            } label: {
                Label("Restart Session", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete '\(session.title)'?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Session Only") {
                actions.deleteSession(id: session.id, deleteWorktree: false)
            }
            if session.worktreeBranch != nil {
                Button("Delete Session & Worktree", role: .destructive) {
                    actions.deleteSession(id: session.id, deleteWorktree: true)
                }
            }
        } message: {
            if session.worktreeBranch != nil {
                Text("This will stop the session and remove it from Runway. You can also delete the worktree and branch.")
            } else {
                Text("This will stop the session and remove it from Runway.")
            }
        }
    }

    private var statusIndicator: some View {
        SessionStatusIndicator(status: session.status, size: 8)
    }
}
