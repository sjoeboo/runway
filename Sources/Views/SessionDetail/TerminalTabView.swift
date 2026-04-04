import Models
import SwiftUI
import Terminal
import TerminalView
import Theme

/// A tab model for terminal instances within a session.
struct TerminalTab: Identifiable {
    let id: String
    let title: String
    let config: TerminalConfig
    let isMain: Bool

    init(id: String, title: String, config: TerminalConfig, isMain: Bool = false) {
        self.id = id
        self.title = title
        self.config = config
        self.isMain = isMain
    }
}

/// Tab bar + terminal pane container for multiple terminals per session.
public struct TerminalTabView: View {
    let session: Session
    let tmuxManager: TmuxSessionManager
    @Binding var showSearch: Bool
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabID: String?
    @State private var shellCounter: Int = 0
    @Environment(\.theme) private var theme
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13

    public init(session: Session, tmuxManager: TmuxSessionManager = TmuxSessionManager(), showSearch: Binding<Bool>) {
        self.session = session
        self.tmuxManager = tmuxManager
        self._showSearch = showSearch
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            // Terminal for selected tab
            if tabs.isEmpty {
                Spacer()
                ProgressView("Connecting to session\u{2026}")
                    .font(.caption)
                Spacer()
            } else if let tab = selectedTab {
                ZStack(alignment: .topTrailing) {
                    TerminalPane(
                        config: tab.config,
                        sessionID: session.id,
                        tabID: tab.id
                    )
                    .id("\(session.id)_\(tab.id)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TerminalSearchBar(
                        isVisible: $showSearch,
                        onFindNext: { term in
                            guard !term.isEmpty else { return }
                            TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)?
                                .findNext(term)
                        },
                        onFindPrevious: { term in
                            guard !term.isEmpty else { return }
                            TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)?
                                .findPrevious(term)
                        },
                        onDismiss: {
                            TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)?
                                .clearSearch()
                        }
                    )
                }
            }
        }
        .onAppear { initializeTabs() }
        .onChange(of: session.id) { _, _ in
            // Reset tabs when switching to a different session — without this,
            // @State persists the old session's tabs and the wrong terminal shows.
            tabs = []
            selectedTabID = nil
            initializeTabs()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }

            // Add tab button
            Button(action: addShellTab) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New shell tab")

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(theme.chrome.surface)
    }

    private func tabButton(_ tab: TerminalTab) -> some View {
        let isSelected = tab.id == selectedTabID

        return Button {
            selectedTabID = tab.id
        } label: {
            HStack(spacing: 4) {
                if tab.isMain {
                    Image(systemName: "terminal")
                        .font(.caption2)
                }
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)

                if !tab.isMain && tabs.count > 1 {
                    Button(action: { closeTab(tab.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(theme.chrome.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? theme.chrome.background : theme.chrome.surface)
            .foregroundColor(isSelected ? theme.chrome.text : theme.chrome.textDim)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Management

    private var selectedTab: TerminalTab? {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    private func initializeTabs() {
        guard tabs.isEmpty else { return }

        let mainTabID = "\(session.id)_main"
        let tmuxName = "runway-\(session.id)"

        // For Claude sessions, build the command with permission flags
        let command: String
        let arguments: [String]
        if session.tool == .claude {
            command = session.tool.command
            arguments = session.permissionMode.cliFlags
        } else {
            command = session.tool.command
            arguments = []
        }

        let mainTab = TerminalTab(
            id: mainTabID,
            title: session.tool.displayName,
            config: TerminalConfig(
                command: command,
                arguments: arguments,
                workingDirectory: session.path,
                environment: [
                    "RUNWAY_SESSION_ID": session.id,
                    "RUNWAY_TITLE": session.title,
                ],
                fontFamily: fontFamily,
                fontSize: Float(fontSize),
                tmuxSessionName: tmuxName
            ),
            isMain: true
        )

        tabs = [mainTab]
        selectedTabID = mainTab.id

        // Discover surviving shell tmux sessions from a previous app launch
        let capturedSessionID = session.id
        Task {
            let manager = tmuxManager
            let shellPrefix = "runway-\(capturedSessionID)-shell"
            let shellSessions = await manager.listSessions(prefix: shellPrefix)

            // Guard against rapid session switching — if the user selected a
            // different session while this Task was awaiting, don't append tabs.
            guard session.id == capturedSessionID else { return }

            for tmuxSession in shellSessions.sorted(by: { $0.name < $1.name }) {
                // Extract shell number from name (e.g., "runway-id-shell2" → "2")
                let suffix = tmuxSession.name.dropFirst(shellPrefix.count)
                let shellNum = Int(suffix) ?? (tabs.filter { !$0.isMain }.count + 1)
                let tabID = "\(session.id)_shell\(shellNum)"

                let tab = TerminalTab(
                    id: tabID,
                    title: "Shell \(shellNum)",
                    config: TerminalConfig(
                        command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                        workingDirectory: session.path,
                        environment: [
                            "RUNWAY_SESSION_ID": session.id
                        ],
                        fontFamily: fontFamily,
                        fontSize: Float(fontSize),
                        tmuxSessionName: tmuxSession.name
                    )
                )

                tabs.append(tab)
            }
            // Sync counter to highest discovered shell number
            let maxShell =
                tabs.compactMap { tab -> Int? in
                    guard !tab.isMain, let num = tab.id.split(separator: "shell").last else { return nil }
                    return Int(num)
                }.max() ?? 0
            shellCounter = max(shellCounter, maxShell)
        }
    }

    private func addShellTab() {
        shellCounter += 1
        let shellNum = shellCounter
        let tabID = "\(session.id)_shell\(shellNum)"
        let tmuxName = "runway-\(session.id)-shell\(shellNum)"

        // Create tmux session BEFORE adding the tab — TerminalPane needs it to exist
        Task {
            let manager = tmuxManager
            try? await manager.createSession(
                name: tmuxName,
                workDir: session.path,
                command: nil,
                env: ["RUNWAY_SESSION_ID": session.id]
            )

            // Add tab after tmux session is ready
            let tab = TerminalTab(
                id: tabID,
                title: "Shell \(shellNum)",
                config: TerminalConfig(
                    command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                    workingDirectory: session.path,
                    environment: [
                        "RUNWAY_SESSION_ID": session.id
                    ],
                    fontFamily: fontFamily,
                    fontSize: Float(fontSize),
                    tmuxSessionName: tmuxName
                )
            )

            tabs.append(tab)
            selectedTabID = tab.id
        }
    }

    private func closeTab(_ id: String) {
        // Kill tmux session for this tab
        if let tab = tabs.first(where: { $0.id == id }),
            let tmuxName = tab.config.tmuxSessionName
        {
            Task {
                let manager = tmuxManager
                try? await manager.killSession(name: tmuxName)
            }
        }

        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            selectedTabID = tabs.first?.id
        }
    }
}
