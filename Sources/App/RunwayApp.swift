import GitHubOperations
import Models
import Persistence
import Sparkle
import StatusDetection
import SwiftUI
import Terminal
import Theme
import Views

@main
struct RunwayApp: App {
    @State private var store: RunwayStore
    private let updaterController: AppUpdaterController

    init() {
        // .app bundles from Finder/Dock inherit a minimal PATH from launchd.
        // Enrich it BEFORE constructing RunwayStore — its init fires a Task
        // that checks tmux availability, and waitUntilExit() pumps the
        // RunLoop which can let that Task sneak in with the un-enriched PATH.
        ShellRunner.enrichPath()

        _store = State(initialValue: RunwayStore())
        updaterController = AppUpdaterController()

        // SPM executables don't get a proper .app bundle, so macOS doesn't
        // activate them as GUI apps. Force regular activation policy so
        // the window, dock icon, and menu bar all appear.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        AppIcon.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(store.themeManager)
                .theme(store.themeManager.currentTheme)
                .preferredColorScheme(store.themeManager.currentTheme.appearance == .dark ? .dark : .light)
                .onOpenURL { url in
                    store.handleDeepLink(url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .sidebar) {
                Button("Sessions") { store.currentView = .sessions }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Pull Requests") { store.currentView = .prs }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Toggle Changes") { store.toggleChangesSidebar() }
                    .keyboardShortcut("3", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    store.newSessionProjectID = nil
                    store.activeSheet = .newSession
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Project") { store.activeSheet = .newProject }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Send to Session") { store.showSendBar.toggle() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])

                Button("Find in Terminal") { store.showTerminalSearch.toggle() }
                    .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Split Pane Down") { store.splitHorizontalTrigger += 1 }
                    .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Split Pane Right") { store.splitVerticalTrigger += 1 }
                    .keyboardShortcut("d", modifiers: .command)

                Button("Search Sessions") { store.focusSidebarSearch = true }
                    .keyboardShortcut("k", modifiers: .command)

                Button("Review PR") { store.activeSheet = .reviewPRDialog }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Stop All Sessions") { Task { await store.stopAllSessions() } }
                Button("Delete Stopped Sessions") { store.deleteStoppedSessions(deleteWorktrees: false) }
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(store.themeManager)
                .theme(store.themeManager.currentTheme)
                .preferredColorScheme(store.themeManager.currentTheme.appearance == .dark ? .dark : .light)
        }

        MenuBarExtra {
            MenuBarView(updater: updaterController.updater)
                .environment(store)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let running = store.sessions.filter { $0.status == .running }.count
        let waiting = store.sessions.filter { $0.status == .waiting }.count
        let active = running + waiting

        if active > 0 {
            Label("\(active)", systemImage: "terminal.fill")
        } else {
            Image(systemName: "terminal")
        }
    }
}

/// Top-level content view with navigation split.
struct ContentView: View {
    @Environment(RunwayStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 280

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: CGFloat(sidebarWidth), max: 500)
                    .background(theme.chrome.surface)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.prominentDetail)
            .toolbar {
                toolbarContent
            }
            .sheet(
                item: Binding(
                    get: { store.activeSheet },
                    set: {
                        store.activeSheet = $0
                        if $0 == nil {
                            store.newSessionProjectID = nil
                            store.newSessionParentID = nil
                            store.forkSourceSession = nil
                        }
                    }
                )
            ) { sheet in
                switch sheet {
                case .newSession:
                    NewSessionDialog(
                        projects: store.projects,
                        profiles: store.agentProfiles.isEmpty ? AgentProfile.builtIn : store.agentProfiles,
                        initialProjectID: store.newSessionProjectID,
                        parentID: store.newSessionParentID,
                        templates: store.availableTemplates(forProjectID: store.newSessionProjectID),
                        forkSource: store.forkSourceSession,
                        onCreate: { request in
                            Task { await store.handleNewSessionRequest(request) }
                            store.newSessionProjectID = nil
                            store.newSessionParentID = nil
                            store.forkSourceSession = nil
                        },
                        onCreateReview: { request in
                            try await store.handleReviewSessionRequest(request)
                        }
                    )
                    .theme(theme)

                case .newProject:
                    NewProjectDialog { name, path, branch in
                        store.createProject(name: name, path: path, defaultBranch: branch)
                    }
                    .theme(theme)

                case .reviewPRSheet:
                    if let pr = store.prCoordinator.reviewPRCandidate {
                        ReviewPRSheet(
                            pr: pr,
                            projects: store.projects
                        ) { sessionName, projectID, initialPrompt in
                            Task {
                                await store.handleReviewPR(
                                    pr: pr,
                                    sessionName: sessionName,
                                    projectID: projectID,
                                    initialPrompt: initialPrompt
                                )
                            }
                            store.prCoordinator.reviewPRCandidate = nil
                        }
                        .theme(theme)
                    }

                case .reviewPRDialog:
                    ReviewPRNumberDialog(
                        projects: store.projects,
                        isResolving: store.prCoordinator.isResolvingPR,
                        onResolve: { number, repo, host in
                            Task { await store.prCoordinator.resolvePRForReview(number: number, repo: repo, host: host) }
                            store.activeSheet = nil
                        }
                    )
                    .theme(theme)

                case .restartSession(let sessionID):
                    if let session = store.sessions.first(where: { $0.id == sessionID }) {
                        RestartSessionDialog(session: session) { useHappy in
                            Task { await store.restartSession(id: sessionID, withHappy: useHappy) }
                            store.activeSheet = nil
                        }
                        .theme(theme)
                    }
                }
            }

            // Status message toast — errors persist until dismissed, others auto-dismiss
            if let msg = store.statusMessage {
                statusToast(msg)
                    .task(id: msg) {
                        guard msg.kind != .error else { return }
                        try? await Task.sleep(for: .seconds(3))
                        store.statusMessage = nil
                    }
            }
        }
        .background(theme.chrome.background)
        .navigationTitle(windowTitle)
        .onChange(of: colorScheme) { _, newScheme in
            store.themeManager.updateForColorScheme(newScheme)
        }
    }

    private var windowTitle: String {
        if let id = store.selectedSessionID,
            let session = store.sessions.first(where: { $0.id == id })
        {
            return "Runway — \(session.title)"
        }
        return "Runway"
    }

    private var selectedSession: Session? {
        guard let id = store.selectedSessionID else { return nil }
        return store.sessions.first { $0.id == id }
    }

    // MARK: - Status Toast

    private func statusToast(_ msg: StatusMessage) -> some View {
        HStack(spacing: 6) {
            Image(
                systemName: msg.kind == .success
                    ? "checkmark.circle.fill"
                    : msg.kind == .info
                        ? "info.circle.fill"
                        : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            Text(msg.text)
                .font(.caption)
                .textSelection(.enabled)

            if msg.kind == .error {
                Button {
                    store.statusMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(toastColor(for: msg.kind))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: msg)
        .onAppear {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: msg.text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
        }
    }

    private func toastColor(for kind: StatusMessage.Kind) -> Color {
        switch kind {
        case .success: theme.chrome.green
        case .info: theme.chrome.accent
        case .error: theme.chrome.red
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var store = store
        return ProjectTreeView(
            projects: store.projects,
            sessions: store.sessions,
            sessionPRs: store.prCoordinator.sessionPRs,
            provisioningWorktreeIDs: store.provisioningWorktreeIDs,
            selectedSessionID: $store.selectedSessionID,
            searchQuery: $store.sidebarSearchQuery,
            focusSearch: $store.focusSidebarSearch,
            actions: store
        )
        .frame(minWidth: 200)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width) { _, newWidth in
                        if abs(Double(newWidth) - sidebarWidth) > 5 {
                            sidebarWidth = Double(newWidth)
                        }
                    }
            }
        )
    }

    private var viewPicker: some View {
        @Bindable var store = store
        return Picker(selection: $store.currentView) {
            Text("Sessions").tag(AppView.sessions)
            Text("PRs").tag(AppView.prs)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        detailContent
            .onChange(of: store.selectedSessionID) { _, newValue in
                // When a session is selected (e.g. via List selection binding),
                // clear selectedProjectID so the session detail takes priority.
                if newValue != nil {
                    store.selectedProjectID = nil
                }
                store.viewingDiffFile = nil
                store.viewingDiffPatch = nil
                store.activeDiffPath = nil
                if store.changesVisible {
                    store.fetchChangesForCurrentSession()
                }
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.currentView {
        case .sessions:
            if let projectID = store.selectedProjectID,
                let project = store.projects.first(where: { $0.id == projectID })
            {
                ProjectPageView(
                    project: project,
                    issues: store.projectIssues[projectID] ?? [],
                    pullRequests: store.prCoordinator.pullRequests.filter { $0.repo == project.ghRepo },
                    labels: store.projectLabels[projectID] ?? [],
                    isLoadingIssues: store.isLoadingIssues,
                    onRefreshIssues: { Task { await store.fetchIssues(forProject: projectID) } },
                    onCreateIssue: { title, body, labels in
                        Task { await store.createIssue(forProject: projectID, title: title, body: body, labels: labels) }
                    },
                    onSelectIssue: { issue in Task { await store.selectIssue(issue) } },
                    selectedIssueID: store.selectedIssueID,
                    issueDetail: store.issueDetail,
                    isLoadingIssueDetail: store.isLoadingIssueDetail,
                    onCommentOnIssue: { issue, body in Task { await store.commentOnIssue(issue, body: body) } },
                    onCloseIssue: { issue, reason in Task { await store.closeIssue(issue, reason: reason) } },
                    onReopenIssue: { issue in Task { await store.reopenIssue(issue) } },
                    onEditIssue: { issue, title, body in Task { await store.editIssue(issue, title: title, body: body) } },
                    onUpdateIssueLabels: { issue, add, remove in Task { await store.updateIssueLabels(issue, add: add, remove: remove) } },
                    onUpdateIssueAssignees: { issue, add, remove in
                        Task { await store.updateIssueAssignees(issue, add: add, remove: remove) }
                    },
                    onStartSessionFromIssue: { issue in
                        Task { await store.startSessionFromIssue(issue, projectID: projectID) }
                    },
                    onSelectPR: { pr in Task { await store.prCoordinator.selectPR(pr, navigate: false) } },
                    onRefreshPRs: { Task { await store.prCoordinator.refreshPRsIfStale() } },
                    selectedPRID: store.prCoordinator.selectedPRID,
                    prDetail: store.prCoordinator.prDetail,
                    onApprovePR: { pr in Task { await store.prCoordinator.approvePR(pr) } },
                    onCommentPR: { pr, body in Task { await store.prCoordinator.commentOnPR(pr, body: body) } },
                    onRequestChangesPR: { pr, body in Task { await store.prCoordinator.requestChangesOnPR(pr, body: body) } },
                    onMergePR: { pr, strategy in Task { await store.prCoordinator.mergePR(pr, strategy: strategy) } },
                    onToggleDraftPR: { pr in Task { await store.prCoordinator.togglePRDraft(pr) } },
                    onUpdateBranchPR: { pr, rebase in Task { await store.prCoordinator.updatePRBranch(pr, rebase: rebase) } },
                    onReviewPR: { pr in store.reviewPR(pr) },
                    onEnableAutoMergePR: { pr, strategy in Task { await store.prCoordinator.enableAutoMerge(pr, strategy: strategy) } },
                    onDisableAutoMergePR: { pr in Task { await store.prCoordinator.disableAutoMerge(pr) } },
                    onDeselectPR: { Task { await store.prCoordinator.selectPR(nil, navigate: false) } },
                    onUpdateProject: { store.updateProjectSettings($0) },
                    onDetectRepo: { await store.detectGHRepo(for: project) },
                    onFetchLabels: { Task { await store.fetchLabels(forProject: projectID) } },
                    templates: store.sessionTemplates.filter { $0.projectID == nil || $0.projectID == projectID },
                    onSaveTemplate: { template in store.saveTemplate(template) },
                    onDeleteTemplate: { id in store.deleteTemplate(id) }
                )
            } else if let sessionID = store.selectedSessionID,
                let session = store.sessions.first(where: { $0.id == sessionID })
            {
                SessionDetailView(
                    session: session,
                    tmuxManager: store.tmuxManager,
                    linkedPR: store.prCoordinator.sessionPRs[sessionID],
                    prDetail: store.prCoordinator.prDetailForSession(sessionID),
                    onSelectPR: { pr in Task { await store.prCoordinator.selectPR(pr) } },
                    parentSession: {
                        guard let parentID = session.parentID else { return nil }
                        return store.sessions.first(where: { $0.id == parentID })
                    }(),
                    onSelectSession: { id in store.selectSession(id) },
                    showSendBar: Binding(
                        get: { store.showSendBar },
                        set: { store.showSendBar = $0 }
                    ),
                    showTerminalSearch: Binding(
                        get: { store.showTerminalSearch },
                        set: { store.showTerminalSearch = $0 }
                    ),
                    splitHorizontalTrigger: Binding(
                        get: { store.splitHorizontalTrigger },
                        set: { store.splitHorizontalTrigger = $0 }
                    ),
                    splitVerticalTrigger: Binding(
                        get: { store.splitVerticalTrigger },
                        set: { store.splitVerticalTrigger = $0 }
                    ),
                    terminalRestartTrigger: Binding(
                        get: { store.terminalRestartTrigger },
                        set: { store.terminalRestartTrigger = $0 }
                    ),
                    changesVisible: Binding(
                        get: { store.changesVisible },
                        set: { store.changesVisible = $0 }
                    ),
                    changesMode: Binding(
                        get: { store.changesMode },
                        set: { newMode in
                            store.changesMode = newMode
                            store.fetchChangesForCurrentSession()
                        }
                    ),
                    changes: store.sessionChanges[sessionID] ?? [],
                    fileTree: store.sessionFileTree[sessionID] ?? [],
                    activeDiffPath: store.activeDiffPath,
                    onSelectDiffFile: { file in store.selectDiffFile(file) },
                    pendingDiffPath: store.viewingDiffFile?.path,
                    pendingDiffPatch: store.viewingDiffPatch,
                    diffOpenTrigger: store.diffOpenTrigger,
                    onActiveDiffPathChanged: { path in store.activeDiffPath = path },
                    onToggleChanges: { store.toggleChangesSidebar() },
                    onRestart: { store.presentRestartDialog(id: sessionID) },
                    worktreeManager: session.worktreeBranch != nil ? store.worktreeManager : nil,
                    defaultBranch: store.projects.first(where: { $0.id == session.projectID })?.defaultBranch ?? "main",
                    onRollback: { hash in
                        Task { try? await store.worktreeManager.resetToCommit(path: session.path, hash: hash) }
                    },
                    savedPrompts: store.savedPrompts
                )
            } else {
                if store.projects.isEmpty && store.sessions.isEmpty {
                    // First-run empty state with clear guidance
                    EmptyStateView(
                        title: "Welcome to Runway",
                        subtitle: "Add a project to get started with AI coding sessions, or jump straight in with a quick session.",
                        actionTitle: "Add Your First Project",
                        onAction: { store.activeSheet = .newProject }
                    )
                } else {
                    EmptyStateView(
                        title: "No Session Selected",
                        subtitle: "Select a session from the sidebar or press \u{2318}N to create one"
                    )
                }
            }
        case .prs:
            PRDashboardView(
                pullRequests: store.prCoordinator.pullRequests,
                selectedPRID: store.prCoordinator.selectedPRID,
                detail: store.prCoordinator.prDetail,
                isLoading: store.prCoordinator.isLoadingPRs,
                sessionPRIDs: store.prCoordinator.sessionPRIDs,
                selectedTab: Binding(
                    get: { store.prCoordinator.prTab },
                    set: { store.prCoordinator.prTab = $0 }
                ),
                onSelectPR: { pr in Task { await store.prCoordinator.selectPR(pr) } },
                onRefresh: { Task { await store.prCoordinator.fetchPRs() } },
                onApprove: { pr in Task { await store.prCoordinator.approvePR(pr) } },
                onComment: { pr, body in Task { await store.prCoordinator.commentOnPR(pr, body: body) } },
                onRequestChanges: { pr, body in Task { await store.prCoordinator.requestChangesOnPR(pr, body: body) } },
                onMerge: { pr, strategy in Task { await store.prCoordinator.mergePR(pr, strategy: strategy) } },
                onToggleDraft: { pr in Task { await store.prCoordinator.togglePRDraft(pr) } },
                onUpdateBranch: { pr, rebase in Task { await store.prCoordinator.updatePRBranch(pr, rebase: rebase) } },
                onSendToSession: { pr, _ in
                    if let sessionID = store.prCoordinator.sessionPRs.first(where: { $0.value.id == pr.id })?.key {
                        store.selectSession(sessionID)
                        store.showSendBar = true
                    }
                },
                onReviewPR: { pr in store.reviewPR(pr) },
                onEnableAutoMerge: { pr, strategy in Task { await store.prCoordinator.enableAutoMerge(pr, strategy: strategy) } },
                onDisableAutoMerge: { pr in Task { await store.prCoordinator.disableAutoMerge(pr) } },
                onClosePR: { pr in Task { await store.prCoordinator.closePR(pr) } },
                onAssignToMe: { pr in Task { await store.prCoordinator.assignPRToMe(pr) } },
                onUnassignMe: { pr in Task { await store.prCoordinator.unassignMeFromPR(pr) } },
                onToggleAssignee: { pr, login in
                    Task {
                        if pr.assignees.contains(login) {
                            await store.prCoordinator.updateAssignees(pr, adding: [], removing: [login])
                        } else {
                            await store.prCoordinator.updateAssignees(pr, adding: [login], removing: [])
                        }
                    }
                },
                onLoadCollaborators: { repo in
                    Task { await store.prCoordinator.loadCollaborators(for: repo) }
                },
                myLoginForHost: { host in
                    store.prCoordinator.warmWhoami(host: host)
                    return store.prCoordinator.myLogin(forHost: host)
                },
                collaboratorsForRepo: { repo in
                    store.prCoordinator.collaboratorsByRepo[repo] ?? []
                }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            viewPicker
        }

        // New Session — always visible
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.newSessionProjectID = nil
                store.activeSheet = .newSession
            } label: {
                Label("New Session", systemImage: "plus.rectangle")
            }
            .help("New Session (⌘N)")
        }

        // Session-specific actions — only when a session is selected
        if selectedSession != nil {
            ToolbarItem(placement: .automatic) {
                Button {
                    store.toggleChangesSidebar()
                } label: {
                    Label(
                        "Changes",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
                .help("Toggle changes sidebar (⌘3)")
                .accessibilityLabel("Toggle changes sidebar")
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    store.splitHorizontalTrigger += 1
                } label: {
                    Label("Split Down", systemImage: "rectangle.split.1x2")
                }
                .help("Split pane down (⌘⇧D)")
                .accessibilityLabel("Split pane down")

                Button {
                    store.splitVerticalTrigger += 1
                } label: {
                    Label("Split Right", systemImage: "rectangle.split.2x1")
                }
                .help("Split pane right (⌘D)")
                .accessibilityLabel("Split pane right")
            }
        }

        // Status counts — centered in the toolbar's principal slot. The window
        // title renders in its native leading slot via .navigationTitle, so we
        // don't duplicate it here.
        ToolbarItem(placement: .principal) {
            toolbarSessionCounts
        }
    }

    @ViewBuilder
    private var toolbarSessionCounts: some View {
        let counts = store.sessions.statusCounts
        if counts.hasAny {
            HStack(spacing: 14) {
                if counts.running > 0 {
                    statusChip(status: .running, count: counts.running, label: "running")
                }
                if counts.waiting > 0 {
                    statusChip(status: .waiting, count: counts.waiting, label: "waiting")
                }
                if counts.idle > 0 {
                    statusChip(status: .idle, count: counts.idle, label: "idle")
                }
                if counts.error > 0 {
                    statusChip(status: .error, count: counts.error, label: "error")
                }
            }
            .padding(.horizontal, 4)
            .help(toolbarCountsHelpText(counts))
        }
    }

    private func statusChip(status: SessionStatus, count: Int, label: String) -> some View {
        HStack(spacing: 5) {
            SessionStatusIndicator(status: status, size: 9)
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(theme.chrome.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label) \(count == 1 ? "session" : "sessions")")
    }

    private func toolbarCountsHelpText(_ counts: SessionStatusCounts) -> String {
        var parts: [String] = []
        if counts.running > 0 { parts.append("\(counts.running) running") }
        if counts.waiting > 0 { parts.append("\(counts.waiting) waiting") }
        if counts.idle > 0 { parts.append("\(counts.idle) idle") }
        if counts.error > 0 { parts.append("\(counts.error) error") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - App View

enum AppView: String, CaseIterable {
    case sessions
    case prs
}
