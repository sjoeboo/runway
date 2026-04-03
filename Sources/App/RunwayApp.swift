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
        // SPM executables don't get a proper .app bundle, so macOS doesn't
        // activate them as GUI apps. Force regular activation policy so
        // the window, dock icon, and menu bar all appear.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
            }
        }

        Settings {
            SettingsView()
                .environment(store.themeManager)
        }
    }
}

/// Top-level content view with navigation split.
struct ContentView: View {
    @Environment(RunwayStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView {
                sidebar
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
                    initialProjectID: store.newSessionProjectID
                ) { request in
                    Task { await store.handleNewSessionRequest(request) }
                    store.newSessionProjectID = nil
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

            // Status message toast
            if let msg = store.statusMessage {
                statusToast(msg)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            store.statusMessage = nil
                        }
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
            Image(systemName: msg.kind == .success ? "checkmark.circle.fill"
                  : msg.kind == .info ? "info.circle.fill"
                  : "exclamationmark.triangle.fill")
                .font(.caption)
            Text(msg.text)
                .font(.caption)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(toastColor(for: msg.kind).opacity(0.9))
        .cornerRadius(6)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: msg)
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
        VStack(spacing: 0) {
            viewPicker
            Divider()
            ProjectTreeView(
                projects: store.projects,
                sessions: store.sessions,
                sessionPRs: store.sessionPRs,
                selectedSessionID: Binding(
                    get: { store.selectedSessionID },
                    set: { store.selectedSessionID = $0 }
                ),
                onRestart: { id in Task { await store.restartSession(id: id) } },
                onDelete: { id in store.deleteSession(id: id) },
                onNewSession: { projectID in
                    store.newSessionProjectID = projectID
                    store.showNewSessionDialog = true
                },
                onNewProject: { store.showNewProjectDialog = true }
            )
        }
        .frame(minWidth: 240)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch store.currentView {
        case .sessions:
            if let sessionID = store.selectedSessionID,
                let session = store.sessions.first(where: { $0.id == sessionID })
            {
                SessionDetailView(session: session, linkedPR: store.sessionPRs[sessionID])
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
                onSelectPR: { pr in Task { await store.selectPR(pr) } },
                onFilterChange: { tab in
                    let filter: PRFilter =
                        switch tab {
                        case .all: .all
                        case .mine: .mine
                        case .reviewRequested: .reviewRequested
                        }
                    Task { await store.fetchPRs(filter: filter) }
                },
                onRefresh: { Task { await store.fetchPRs() } },
                onApprove: { pr in Task { await store.approvePR(pr) } },
                onComment: { pr, body in Task { await store.commentOnPR(pr, body: body) } }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Toolbar buttons removed — inline sidebar controls replace them.
        // Keyboard shortcuts are preserved via the Commands block in RunwayApp.
        ToolbarItem(placement: .primaryAction) {
            EmptyView()
        }
    }
}

// MARK: - App View

enum AppView: String, CaseIterable {
    case sessions
    case prs
}
