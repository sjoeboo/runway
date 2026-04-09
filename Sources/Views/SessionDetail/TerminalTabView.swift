import Models
import SwiftTerm
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
    @Binding var splitHorizontalTrigger: Int
    @Binding var splitVerticalTrigger: Int
    @Binding var terminalRestartTrigger: Int
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabID: String?
    @State private var shellCounter: Int = 0
    @Environment(\.theme) private var theme
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13

    public init(
        session: Session,
        tmuxManager: TmuxSessionManager,
        showSearch: Binding<Bool>,
        splitHorizontalTrigger: Binding<Int> = .constant(0),
        splitVerticalTrigger: Binding<Int> = .constant(0),
        terminalRestartTrigger: Binding<Int> = .constant(0)
    ) {
        self.session = session
        self.tmuxManager = tmuxManager
        self._showSearch = showSearch
        self._splitHorizontalTrigger = splitHorizontalTrigger
        self._splitVerticalTrigger = splitVerticalTrigger
        self._terminalRestartTrigger = terminalRestartTrigger
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            // Terminal for selected tab
            if tabs.isEmpty, session.status == .error || session.status == .stopped {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(theme.chrome.textDim)
                    Text(session.status == .error ? "Session failed to start" : "Session stopped")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
                Spacer()
            } else if tabs.isEmpty {
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
                            guard !term.isEmpty else { return false }
                            return TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)?
                                .findNext(term) ?? false
                        },
                        onFindPrevious: { term in
                            guard !term.isEmpty else { return false }
                            return TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)?
                                .findPrevious(term) ?? false
                        },
                        onCountMatches: { term in
                            guard !term.isEmpty,
                                let terminal = TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)
                            else { return nil }
                            return countMatches(term, in: terminal)
                        },
                        onDismiss: {
                            TerminalSessionCache.shared.existing(sessionID: session.id, tabID: tab.id)?
                                .clearSearch()
                        }
                    )
                }
            }
        }
        .onAppear { initializeTabsIfReady() }
        .onChange(of: session.id) { _, _ in
            // Reset tabs when switching to a different session — without this,
            // @State persists the old session's tabs and the wrong terminal shows.
            tabs = []
            selectedTabID = nil
            initializeTabsIfReady()
        }
        .onChange(of: splitHorizontalTrigger) { _, _ in splitDown() }
        .onChange(of: splitVerticalTrigger) { _, _ in splitRight() }
        .onChange(of: terminalRestartTrigger) { _, _ in
            // Force reinitialize tabs after restart — the status onChange may not
            // fire if SwiftUI coalesces .running → .starting → .running into no-op.
            tabs = []
            selectedTabID = nil
            initializeTabsIfReady()
        }
        .onChange(of: session.status) { _, newStatus in
            // Wait for the tmux session to be created before attaching.
            // TerminalPane calls `tmux attach-session` immediately, so we
            // must not initialize tabs until the tmux session actually exists.
            // Only .running, .idle, and .waiting indicate a live tmux session —
            // .error and .stopped mean creation failed or the session is gone.
            // Note: tabs are NOT cleared on non-live status — restart uses .id()
            // to force full view recreation, and stale hook events from a killed
            // session could otherwise destroy the freshly created terminal.
            if tabs.isEmpty, newStatus.tmuxSessionExpected {
                initializeTabs()
            }
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
            .accessibilityLabel("New shell tab")

            Spacer()

            // Split pane buttons
            if selectedTab != nil {
                HStack(spacing: 2) {
                    Button(action: splitDown) {
                        Image(systemName: "rectangle.split.1x2")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Split pane down (top/bottom)")
                    .accessibilityLabel("Split pane down")

                    Button(action: splitRight) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Split pane right (left/right)")
                    .accessibilityLabel("Split pane right")
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(theme.chrome.surface)
    }

    private func tabButton(_ tab: TerminalTab) -> some View {
        let isSelected = tab.id == selectedTabID

        return HStack(spacing: 4) {
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
                        .font(.caption2.weight(.bold))
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? theme.chrome.background : theme.chrome.surface)
        .foregroundColor(isSelected ? theme.chrome.text : theme.chrome.textDim)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { selectedTabID = tab.id }
    }

    // MARK: - Tab Management

    private var selectedTab: TerminalTab? {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    /// Only initialize tabs once the tmux session exists.
    /// New sessions start as .starting and transition to .running once tmux is created.
    /// Restored sessions are .idle (tmux alive) or .stopped (tmux gone).
    /// Only attach when status indicates a live tmux session — .starting means
    /// it hasn't been created yet, .error/.stopped mean it's gone.
    private func initializeTabsIfReady() {
        guard session.status.tmuxSessionExpected else { return }
        initializeTabs()
    }

    private func initializeTabs() {
        guard tabs.isEmpty else { return }

        let mainTabID = "\(session.id)_main"
        let tmuxName = "runway-\(session.id)"

        // Build the command with permission flags for tools that support them
        let command: String = session.tool.command
        let arguments: [String]
        if session.tool.supportsPermissionModes {
            arguments = session.permissionMode.cliFlags(for: session.tool)
        } else {
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

    /// Split the current pane top/bottom (creates a horizontal divider).
    private func splitDown() {
        guard let tab = selectedTab, let tmuxName = tab.config.tmuxSessionName else { return }
        Task {
            try? await tmuxManager.splitWindow(
                sessionName: tmuxName, direction: .horizontal, workDir: session.path
            )
        }
    }

    /// Split the current pane left/right (creates a vertical divider).
    private func splitRight() {
        guard let tab = selectedTab, let tmuxName = tab.config.tmuxSessionName else { return }
        Task {
            try? await tmuxManager.splitWindow(
                sessionName: tmuxName, direction: .vertical, workDir: session.path
            )
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

    /// Count occurrences of a search term in the terminal buffer text.
    private func countMatches(_ term: String, in terminalView: LocalProcessTerminalView) -> Int {
        let data = terminalView.getTerminal().getBufferAsData()
        guard let text = String(data: data, encoding: .utf8) else { return 0 }

        // Case-insensitive count to match SwiftTerm's default SearchOptions
        let searchTerm = term.lowercased()
        let searchIn = text.lowercased()
        var count = 0
        var searchRange = searchIn.startIndex..<searchIn.endIndex
        while let range = searchIn.range(of: searchTerm, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<searchIn.endIndex
        }
        return count
    }
}
