import AppKit
import Models
import SwiftUI
import Theme

/// Sidebar view showing the hierarchical project tree with sessions.
public struct ProjectTreeView: View {
    let projects: [Project]
    let sessions: [Session]
    let sessionPRs: [String: PullRequest]
    @Binding var selectedSessionID: String?
    @Binding var selectedProjectID: String?
    var onRestart: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onNewSession: ((String?) -> Void)?
    var onNewProject: (() -> Void)?
    var onRenameSession: ((String, String) -> Void)?
    var onRenameProject: ((String, String) -> Void)?
    var onDeleteProject: ((String) -> Void)?
    var onViewPR: ((String) -> Void)?
    var onReorderSessions: ((String?, IndexSet, Int) -> Void)?
    var onReorderProjects: ((IndexSet, Int) -> Void)?
    var onSelectProject: ((String?) -> Void)?
    var onSelectSession: ((String?) -> Void)?
    @Environment(\.theme) private var theme

    public init(
        projects: [Project],
        sessions: [Session],
        sessionPRs: [String: PullRequest] = [:],
        selectedSessionID: Binding<String?>,
        selectedProjectID: Binding<String?> = .constant(nil),
        onRestart: ((String) -> Void)? = nil,
        onDelete: ((String) -> Void)? = nil,
        onNewSession: ((String?) -> Void)? = nil,
        onNewProject: (() -> Void)? = nil,
        onRenameSession: ((String, String) -> Void)? = nil,
        onRenameProject: ((String, String) -> Void)? = nil,
        onDeleteProject: ((String) -> Void)? = nil,
        onViewPR: ((String) -> Void)? = nil,
        onReorderSessions: ((String?, IndexSet, Int) -> Void)? = nil,
        onReorderProjects: ((IndexSet, Int) -> Void)? = nil,
        onSelectProject: ((String?) -> Void)? = nil,
        onSelectSession: ((String?) -> Void)? = nil
    ) {
        self.projects = projects
        self.sessions = sessions
        self.sessionPRs = sessionPRs
        self._selectedSessionID = selectedSessionID
        self._selectedProjectID = selectedProjectID
        self.onRestart = onRestart
        self.onDelete = onDelete
        self.onNewSession = onNewSession
        self.onNewProject = onNewProject
        self.onRenameSession = onRenameSession
        self.onRenameProject = onRenameProject
        self.onDeleteProject = onDeleteProject
        self.onViewPR = onViewPR
        self.onReorderSessions = onReorderSessions
        self.onReorderProjects = onReorderProjects
        self.onSelectProject = onSelectProject
        self.onSelectSession = onSelectSession
    }

    public var body: some View {
        List(selection: $selectedSessionID) {
            ForEach(projects) { project in
                ProjectSection(
                    project: project,
                    sessions: sessions.filter { $0.groupID == project.id },
                    sessionPRs: sessionPRs,
                    onRestart: onRestart,
                    onDelete: onDelete,
                    onNewSession: { onNewSession?(project.id) },
                    onRenameSession: onRenameSession,
                    onRenameProject: onRenameProject,
                    onDeleteProject: onDeleteProject,
                    onViewPR: onViewPR,
                    onReorderSessions: { fromOffsets, toOffset in
                        onReorderSessions?(project.id, fromOffsets, toOffset)
                    },
                    onSelectProject: onSelectProject,
                    onSelectSession: onSelectSession
                )
            }
            .onMove { fromOffsets, toOffset in
                onReorderProjects?(fromOffsets, toOffset)
            }

            // Ungrouped sessions
            let ungrouped = sessions.filter { $0.groupID == nil }
            if !ungrouped.isEmpty {
                Section("Sessions") {
                    ForEach(ungrouped) { session in
                        SessionRowView(
                            session: session,
                            linkedPR: sessionPRs[session.id],
                            onRestart: onRestart,
                            onDelete: onDelete,
                            onRenameSession: onRenameSession,
                            onViewPR: onViewPR,
                            onSelectSession: onSelectSession
                        )
                        .tag(session.id)
                    }
                    .onMove { fromOffsets, toOffset in
                        onReorderSessions?(nil, fromOffsets, toOffset)
                    }
                }
            }

            // Add project button
            Section {
                Button {
                    onNewProject?()
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                        .font(.system(.body))
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Project Section (collapsible with inline "+")

struct ProjectSection: View {
    let project: Project
    let sessions: [Session]
    let sessionPRs: [String: PullRequest]
    var onRestart: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onNewSession: (() -> Void)?
    var onRenameSession: ((String, String) -> Void)?
    var onRenameProject: ((String, String) -> Void)?
    var onDeleteProject: ((String) -> Void)?
    var onViewPR: ((String) -> Void)?
    var onReorderSessions: ((IndexSet, Int) -> Void)?
    var onSelectProject: ((String?) -> Void)?
    var onSelectSession: ((String?) -> Void)?
    @AppStorage private var isExpanded: Bool
    @State private var isHeaderHovered = false
    @State private var isRenaming = false
    @State private var editName: String = ""
    @Environment(\.theme) private var theme

    init(
        project: Project,
        sessions: [Session],
        sessionPRs: [String: PullRequest],
        onRestart: ((String) -> Void)?,
        onDelete: ((String) -> Void)?,
        onNewSession: (() -> Void)?,
        onRenameSession: ((String, String) -> Void)? = nil,
        onRenameProject: ((String, String) -> Void)? = nil,
        onDeleteProject: ((String) -> Void)? = nil,
        onViewPR: ((String) -> Void)? = nil,
        onReorderSessions: ((IndexSet, Int) -> Void)? = nil,
        onSelectProject: ((String?) -> Void)? = nil,
        onSelectSession: ((String?) -> Void)? = nil
    ) {
        self.project = project
        self.sessions = sessions
        self.sessionPRs = sessionPRs
        self.onRestart = onRestart
        self.onDelete = onDelete
        self.onNewSession = onNewSession
        self.onRenameSession = onRenameSession
        self.onRenameProject = onRenameProject
        self.onDeleteProject = onDeleteProject
        self.onViewPR = onViewPR
        self.onReorderSessions = onReorderSessions
        self.onSelectProject = onSelectProject
        self.onSelectSession = onSelectSession
        self._isExpanded = AppStorage(wrappedValue: true, "project.expanded.\(project.id)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(sessions) { session in
                SessionRowView(
                    session: session,
                    linkedPR: sessionPRs[session.id],
                    onRestart: onRestart,
                    onDelete: onDelete,
                    onRenameSession: onRenameSession,
                    onViewPR: onViewPR,
                    onSelectSession: onSelectSession
                )
                .tag(session.id)
            }
            .onMove { fromOffsets, toOffset in
                onReorderSessions?(fromOffsets, toOffset)
            }
        } label: {
            HStack(spacing: 4) {
                if isRenaming {
                    TextField(
                        "Project name", text: $editName,
                        onCommit: {
                            if !editName.isEmpty {
                                onRenameProject?(project.id, editName)
                            }
                            isRenaming = false
                        }
                    )
                    .textFieldStyle(.plain)
                    .font(.system(.title3, weight: .semibold))
                    .onAppear { editName = project.name }
                } else {
                    Text(project.name)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundColor(theme.chrome.text)
                        .onTapGesture {
                            onSelectProject?(project.id)
                        }
                }
                Spacer()

                if isHeaderHovered && !isRenaming {
                    Button {
                        onNewSession?()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
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
                onSelectProject?(project.id)
            } label: {
                Label("Project Settings\u{2026}", systemImage: "gear")
            }

            Divider()

            Button(role: .destructive) {
                onDeleteProject?(project.id)
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
    var onRestart: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onRenameSession: ((String, String) -> Void)?
    var onViewPR: ((String) -> Void)?
    var onSelectSession: ((String?) -> Void)?
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var editTitle: String = ""
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField(
                        "Session name", text: $editTitle,
                        onCommit: {
                            if !editTitle.isEmpty {
                                onRenameSession?(session.id, editTitle)
                            }
                            isRenaming = false
                        }
                    )
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
                                .foregroundColor(theme.chrome.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Open PR #\(pr.number) in browser")
                        if pr.checks.total > 0 {
                            if pr.checks.allPassed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(theme.chrome.green)
                            } else if pr.checks.hasFailed {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(theme.chrome.red)
                            } else {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(theme.chrome.yellow)
                            }
                            Text("\(pr.checks.passed)/\(pr.checks.total)")
                                .font(.caption2)
                                .foregroundColor(theme.chrome.textDim)
                        }
                        if pr.reviewDecision == .approved {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8))
                                .foregroundColor(theme.chrome.green)
                        } else if pr.reviewDecision == .changesRequested {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 8))
                                .foregroundColor(theme.chrome.orange)
                        }
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
                                .font(.system(size: 8))
                                .foregroundColor(theme.chrome.textDim)
                        }
                    }
                }
            }
            Spacer()

            if isHovered {
                HStack(spacing: 2) {
                    Button {
                        onRestart?(session.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                            .foregroundColor(theme.chrome.textDim)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Restart session")

                    Button {
                        onDelete?(session.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
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
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 2)
        .onTapGesture {
            onSelectSession?(session.id)
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

                Button {
                    onViewPR?(session.id)
                } label: {
                    Label("View PR", systemImage: "arrow.triangle.pull")
                }

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
                onRestart?(session.id)
            } label: {
                Label("Restart Session", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                onDelete?(session.id)
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.status {
        case .running:
            Circle().fill(theme.chrome.green).frame(width: 8, height: 8)
        case .waiting:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 8))
                .foregroundColor(theme.chrome.yellow)
        case .idle:
            Circle().stroke(theme.chrome.textDim, lineWidth: 1).frame(width: 8, height: 8)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 8))
                .foregroundColor(theme.chrome.red)
        case .starting:
            ProgressView().controlSize(.mini)
        case .stopped:
            Circle().stroke(theme.chrome.textDim, lineWidth: 1).frame(width: 8, height: 8)
                .opacity(0.5)
        }
    }
}
