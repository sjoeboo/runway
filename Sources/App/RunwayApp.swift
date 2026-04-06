import GitHubOperations
import Models
import Persistence
import StatusDetection
import SwiftUI
import Terminal
import Theme
import Views

@main
struct RunwayApp: App {
    @State private var store = RunwayStore()

    init() {
        // .app bundles from Finder/Dock inherit a minimal PATH from launchd.
        // Enrich it with the user's login shell PATH so Homebrew tools
        // (tmux, gh, claude, etc.) are found by /usr/bin/env.
        ShellRunner.enrichPath()

        // SPM executables don't get a proper .app bundle, so macOS doesn't
        // activate them as GUI apps. Force regular activation policy so
        // the window, dock icon, and menu bar all appear.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        AppIcon.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(store.themeManager)
                .theme(store.themeManager.currentTheme)
                .preferredColorScheme(store.themeManager.currentTheme.appearance == .dark ? .dark : .light)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Sessions") { store.currentView = .sessions }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Pull Requests") { store.currentView = .prs }
                    .keyboardShortcut("2", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    store.newSessionProjectID = nil
                    store.showNewSessionDialog = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Project") { store.showNewProjectDialog = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Send to Session") { store.showSendBar.toggle() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])

                Button("Find in Terminal") { store.showTerminalSearch.toggle() }
                    .keyboardShortcut("f", modifiers: .command)

                Button("Search Sessions") { store.focusSidebarSearch = true }
                    .keyboardShortcut("k", modifiers: .command)

                Button("Review PR") { store.showReviewPRDialog = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(store.themeManager)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            menuBarLabel
        }
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
            .navigationSplitViewStyle(.balanced)
            .toolbar {
                toolbarContent
            }
            .sheet(
                isPresented: Binding(
                    get: { store.showNewSessionDialog },
                    set: { store.showNewSessionDialog = $0 }
                )
            ) {
                NewSessionDialog(
                    projects: store.projects,
                    initialProjectID: store.newSessionProjectID,
                    parentID: store.newSessionParentID
                ) { request in
                    Task { await store.handleNewSessionRequest(request) }
                    store.newSessionProjectID = nil
                    store.newSessionParentID = nil
                }
                .theme(theme)
            }
            .sheet(
                isPresented: Binding(
                    get: { store.showNewProjectDialog },
                    set: { store.showNewProjectDialog = $0 }
                )
            ) {
                NewProjectDialog { name, path, branch in
                    store.createProject(name: name, path: path, defaultBranch: branch)
                }
                .theme(theme)
            }
            .sheet(
                isPresented: Binding(
                    get: { store.showReviewPRSheet },
                    set: { store.showReviewPRSheet = $0 }
                )
            ) {
                if let pr = store.reviewPRCandidate {
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
                        store.reviewPRCandidate = nil
                    }
                    .theme(theme)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { store.showReviewPRDialog },
                    set: { store.showReviewPRDialog = $0 }
                )
            ) {
                ReviewPRNumberDialog(
                    projects: store.projects,
                    isResolving: store.isResolvingPR,
                    onResolve: { number, repo, host in
                        Task { await store.resolvePRForReview(number: number, repo: repo, host: host) }
                        store.showReviewPRDialog = false
                    }
                )
                .theme(theme)
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
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(toastColor(for: msg.kind).opacity(0.9))
        .cornerRadius(6)
        .padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: msg)
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
            sessionPRs: store.sessionPRs,
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
            // Force re-render when selectionVersion changes (fixes nil→nil no-op on first launch)
            .id(store.selectionVersion)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.currentView {
        case .sessions:
            if let sessionID = store.selectedSessionID,
                let session = store.sessions.first(where: { $0.id == sessionID })
            {
                SessionDetailView(
                    session: session,
                    linkedPR: store.sessionPRs[sessionID],
                    onSelectPR: { pr in Task { await store.selectPR(pr) } },
                    showSendBar: Binding(
                        get: { store.showSendBar },
                        set: { store.showSendBar = $0 }
                    ),
                    showTerminalSearch: Binding(
                        get: { store.showTerminalSearch },
                        set: { store.showTerminalSearch = $0 }
                    )
                )
            } else if let projectID = store.selectedProjectID,
                let project = store.projects.first(where: { $0.id == projectID })
            {
                ProjectPageView(
                    project: project,
                    issues: store.projectIssues[projectID] ?? [],
                    pullRequests: store.pullRequests.filter { $0.repo == project.ghRepo },
                    labels: store.projectLabels[projectID] ?? [],
                    isLoadingIssues: store.isLoadingIssues,
                    onRefreshIssues: { Task { await store.fetchIssues(forProject: projectID) } },
                    onCreateIssue: { title, body, labels in
                        Task { await store.createIssue(forProject: projectID, title: title, body: body, labels: labels) }
                    },
                    onOpenIssue: { store.openIssueInBrowser($0) },
                    onSelectPR: { pr in Task { await store.selectPR(pr, navigate: false) } },
                    onRefreshPRs: { Task { await store.refreshPRsIfStale() } },
                    selectedPRID: store.selectedPRID,
                    prDetail: store.prDetail,
                    onApprovePR: { pr in Task { await store.approvePR(pr) } },
                    onCommentPR: { pr, body in Task { await store.commentOnPR(pr, body: body) } },
                    onRequestChangesPR: { pr, body in Task { await store.requestChangesOnPR(pr, body: body) } },
                    onMergePR: { pr, strategy in Task { await store.mergePR(pr, strategy: strategy) } },
                    onToggleDraftPR: { pr in Task { await store.togglePRDraft(pr) } },
                    onReviewPR: { pr in store.reviewPR(pr) },
                    onUpdateProject: { store.updateProjectSettings($0) },
                    onDetectRepo: { await store.detectGHRepo(for: project) },
                    onFetchLabels: { Task { await store.fetchLabels(forProject: projectID) } }
                )
            } else {
                EmptyStateView(
                    title: "No Session Selected",
                    subtitle: "Select a session from the sidebar or press ⌘N to create one"
                )
            }
        case .prs:
            PRDashboardView(
                pullRequests: store.pullRequests,
                selectedPRID: store.selectedPRID,
                detail: store.prDetail,
                isLoading: store.isLoadingPRs,
                sessionPRIDs: store.sessionPRIDs,
                selectedTab: Binding(
                    get: { store.prTab },
                    set: { store.prTab = $0 }
                ),
                onSelectPR: { pr in Task { await store.selectPR(pr) } },
                onRefresh: { Task { await store.fetchPRs() } },
                onApprove: { pr in Task { await store.approvePR(pr) } },
                onComment: { pr, body in Task { await store.commentOnPR(pr, body: body) } },
                onRequestChanges: { pr, body in Task { await store.requestChangesOnPR(pr, body: body) } },
                onMerge: { pr, strategy in Task { await store.mergePR(pr, strategy: strategy) } },
                onToggleDraft: { pr in Task { await store.togglePRDraft(pr) } },
                onSendToSession: { pr, _ in
                    if let sessionID = store.sessionPRs.first(where: { $0.value.id == pr.id })?.key {
                        store.selectSession(sessionID)
                        store.showSendBar = true
                    }
                },
                onReviewPR: { pr in store.reviewPR(pr) }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            viewPicker
        }
    }
}

// MARK: - App View

enum AppView: String, CaseIterable {
    case sessions
    case prs
}
