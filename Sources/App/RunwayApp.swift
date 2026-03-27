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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(store.themeManager)
                .theme(store.themeManager.currentTheme)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
        }
    }
}

/// Top-level content view with navigation split.
struct ContentView: View {
    @Environment(RunwayStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(theme.chrome.background)
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            viewPicker
            ProjectTreeView(
                projects: store.projects,
                sessions: store.sessions,
                selectedSessionID: Binding(
                    get: { store.selectedSessionID },
                    set: { store.selectedSessionID = $0 }
                )
            )
        }
        .frame(minWidth: 220)
    }

    private var viewPicker: some View {
        @Bindable var store = store
        return Picker("View", selection: $store.currentView) {
            Text("Sessions").tag(AppView.sessions)
            Text("PRs").tag(AppView.prs)
            Text("Todos").tag(AppView.todos)
        }
        .pickerStyle(.segmented)
        .padding(8)
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
            Button(action: { store.showNewSessionDialog = true }) {
                Label("New Session", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

// MARK: - App View

enum AppView: String, CaseIterable {
    case sessions
    case prs
    case todos
}
