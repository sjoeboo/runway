import SwiftUI
import Models
import Persistence
import Theme
import Views
import Terminal
import StatusDetection

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
                Button("Todos") { store.currentView = .todos }
                    .keyboardShortcut("3", modifiers: .command)
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
            .sheet(isPresented: Binding(
                get: { store.showNewSessionDialog },
                set: { store.showNewSessionDialog = $0 }
            )) {
                NewSessionDialog(projects: store.projects) { request in
                    Task { await store.handleNewSessionRequest(request) }
                }
                .theme(theme)
            }
            .sheet(isPresented: Binding(
                get: { store.showNewProjectDialog },
                set: { store.showNewProjectDialog = $0 }
            )) {
                NewProjectDialog { name, path, branch in
                    store.createProject(name: name, path: path, defaultBranch: branch)
                }
                .theme(theme)
            }

            // Status message toast
            if let message = store.statusMessage {
                statusToast(message)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            store.statusMessage = nil
                        }
                    }
            }
        }
        .background(theme.chrome.background)
        .onChange(of: colorScheme) { _, newScheme in
            store.themeManager.updateForColorScheme(newScheme)
        }
    }

    // MARK: - Status Toast

    private func statusToast(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.chrome.red.opacity(0.9))
            .cornerRadius(6)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: message)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            viewPicker
            Divider()
            ProjectTreeView(
                projects: store.projects,
                sessions: store.sessions,
                selectedSessionID: Binding(
                    get: { store.selectedSessionID },
                    set: { store.selectedSessionID = $0 }
                )
            )
        }
        .frame(minWidth: 240)
    }

    private var viewPicker: some View {
        @Bindable var store = store
        return Picker(selection: $store.currentView) {
            Text("Sessions").tag(AppView.sessions)
            Text("PRs").tag(AppView.prs)
            Text("Todos").tag(AppView.todos)
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
               let session = store.sessions.first(where: { $0.id == sessionID }) {
                SessionDetailView(session: session)
            } else {
                EmptyStateView(
                    title: "No Session Selected",
                    subtitle: "Select a session from the sidebar or press ⌘N to create one"
                )
            }
        case .prs:
            PRDashboardView(pullRequests: store.pullRequests)
        case .todos:
            TodoBoardView(todos: store.todos)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                Button(action: { store.showNewProjectDialog = true }) {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button(action: { store.showNewSessionDialog = true }) {
                    Label("New Session", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - App View

enum AppView: String, CaseIterable {
    case sessions
    case prs
    case todos
}
