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
}

/// Sidebar view showing the hierarchical project tree with sessions.
///
/// Takes 4 data parameters + 1 actions object, replacing the previous 14-parameter init.
public struct ProjectTreeView: View {
    let projects: [Project]
    let sessions: [Session]
    let sessionPRs: [String: PullRequest]
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
        selectedSessionID: Binding<String?>,
        searchQuery: Binding<String>,
        focusSearch: Binding<Bool> = .constant(false),
        actions: SidebarActions
    ) {
        self.projects = projects
        self.sessions = sessions
        self.sessionPRs = sessionPRs
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
                            actions: actions
                        )
                        .tag(session.id)

                        ForEach(ungrouped.filter { $0.parentID == session.id }) { child in
                            SessionRowView(
                                session: child,
                                linkedPR: sessionPRs[child.id],
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
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextField("Search sessions…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isSearchFocused)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(theme.chrome.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.chrome.surface)
        }
    }
}

// MARK: - Project Section (collapsible with inline "+")

struct ProjectSection: View {
    let project: Project
    let sessions: [Session]
    let sessionPRs: [String: PullRequest]
    let actions: SidebarActions
    @AppStorage private var isExpanded: Bool
    @State private var isHeaderHovered = false
    @State private var isRenaming = false
    @State private var editName: String = ""
    @Environment(\.theme) private var theme

    init(
        project: Project,
        sessions: [Session],
        sessionPRs: [String: PullRequest],
        actions: SidebarActions
    ) {
        self.project = project
        self.sessions = sessions
        self.sessionPRs = sessionPRs
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
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(rootSessions) { session in
                SessionRowView(
                    session: session,
                    linkedPR: sessionPRs[session.id],
                    actions: actions
                )
                .tag(session.id)

                // Child sessions indented under parent
                ForEach(children(of: session.id)) { child in
                    SessionRowView(
                        session: child,
                        linkedPR: sessionPRs[child.id],
                        actions: actions
                    )
                    .padding(.leading, 20)
                    .tag(child.id)
                }
            }
            .onMove { fromOffsets, toOffset in
                actions.reorderSessions(in: project.id, fromOffsets: fromOffsets, toOffset: toOffset)
            }
        } label: {
            HStack(spacing: 4) {
                if isRenaming {
                    TextField("Project name", text: $editName)
                        .onSubmit {
                            if !editName.isEmpty {
                                actions.renameProject(id: project.id, name: editName)
                            }
                            isRenaming = false
                        }
                        .textFieldStyle(.plain)
                        .font(.system(.title3, weight: .semibold))
                        .onAppear { editName = project.name }
                } else {
                    Text(project.name)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundColor(theme.chrome.text)
                        .onTapGesture {
                            actions.selectProject(project.id)
                        }
                }
                Spacer()

                if isHeaderHovered && !isRenaming {
                    Button {
                        actions.newSession(projectID: project.id, parentID: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("New session in \(project.name)")
                }
            }
            .onHover { hovering in
                isHeaderHovered = hovering
            }
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
                actions.deleteProject(id: project.id)
            } label: {
                Label("Remove Project", systemImage: "folder.badge.minus")
            }
        }
    }
}

// MARK: - Session Row

/// A single session row in the sidebar with hover-revealed action buttons.
struct SessionRowView: View {
    let session: Session
    var linkedPR: PullRequest?
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
                    Text(session.title)
                        .font(.system(.body, design: .default))
                        .foregroundColor(theme.chrome.text)
                }
                if let branch = session.worktreeBranch {
                    Text(branch)
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
                // Linked PR info
                if let pr = linkedPR {
                    HStack(spacing: 4) {
                        Button {
                            if let url = URL(string: pr.url) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("#\(pr.number)")
                                .font(.caption2)
                                .foregroundColor(pr.numberColor(chrome: theme.chrome))
                        }
                        .buttonStyle(LinkButtonStyle())
                        .help("Open PR #\(pr.number) in browser")
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
                                .foregroundColor(theme.chrome.textDim)
                        }
                    }
                }
            }
            Spacer()

            if isHovered {
                HStack(spacing: 2) {
                    Button {
                        Task { await actions.restartSession(id: session.id) }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Restart session")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Delete session")
                }
            } else if session.tool != .claude {
                Text(session.tool.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.chrome.surface)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
        .onTapGesture {
            actions.selectSession(session.id)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                isRenaming = true
            } label: {
                Label("Rename Session", systemImage: "pencil")
            }

            Button {
                actions.newSession(projectID: session.projectID, parentID: session.id)
            } label: {
                Label("Spawn Sub-session", systemImage: "arrow.triangle.branch")
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
