import Models
import SwiftTerm
import SwiftUI
import Terminal
import TerminalView
import Theme

/// A tab model for terminal or diff instances within a session.
struct TerminalTab: Identifiable {
    let id: String
    let title: String
    let isMain: Bool

    enum Content {
        case terminal(TerminalConfig)
        case diff(filePath: String, patch: String)
        case transcript(path: String)
    }

    let content: Content

    /// The terminal config, if this is a terminal tab.
    var config: TerminalConfig? {
        if case .terminal(let config) = content { return config }
        return nil
    }

    init(id: String, title: String, config: TerminalConfig, isMain: Bool = false) {
        self.id = id
        self.title = title
        self.isMain = isMain
        self.content = .terminal(config)
    }

    init(id: String, title: String, filePath: String, patch: String) {
        self.id = id
        self.title = title
        self.isMain = false
        self.content = .diff(filePath: filePath, patch: patch)
    }

    init(id: String, title: String, transcriptPath: String) {
        self.id = id
        self.title = title
        self.isMain = false
        self.content = .transcript(path: transcriptPath)
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
    let pendingDiffPath: String?
    let pendingDiffPatch: String?
    let diffOpenTrigger: Int
    var onActiveDiffPathChanged: ((String?) -> Void)?
    var onRestart: (() -> Void)?
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabID: String?
    @State private var shellCounter: Int = 0
    private let tabStateCache = TerminalTabStateCache.shared
    @Environment(\.theme) private var theme
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13

    public init(
        session: Session,
        tmuxManager: TmuxSessionManager,
        showSearch: Binding<Bool>,
        splitHorizontalTrigger: Binding<Int> = .constant(0),
        splitVerticalTrigger: Binding<Int> = .constant(0),
        terminalRestartTrigger: Binding<Int> = .constant(0),
        pendingDiffPath: String? = nil,
        pendingDiffPatch: String? = nil,
        diffOpenTrigger: Int = 0,
        onActiveDiffPathChanged: ((String?) -> Void)? = nil,
        onRestart: (() -> Void)? = nil
    ) {
        self.session = session
        self.tmuxManager = tmuxManager
        self._showSearch = showSearch
        self._splitHorizontalTrigger = splitHorizontalTrigger
        self._splitVerticalTrigger = splitVerticalTrigger
        self._terminalRestartTrigger = terminalRestartTrigger
        self.pendingDiffPath = pendingDiffPath
        self.pendingDiffPatch = pendingDiffPatch
        self.diffOpenTrigger = diffOpenTrigger
        self.onActiveDiffPathChanged = onActiveDiffPathChanged
        self.onRestart = onRestart
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            // Terminal for selected tab
            if tabs.isEmpty, session.status == .error || session.status == .stopped {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: session.status == .error ? "exclamationmark.triangle" : "stop.circle")
                        .font(.title2)
                        .foregroundColor(session.status == .error ? theme.chrome.orange : theme.chrome.textDim)
                    Text(session.status == .error ? "Session failed to start" : "Session stopped")
                        .font(.callout)
                        .foregroundColor(theme.chrome.textDim)
                    if let error = session.lastError, session.status == .error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(theme.chrome.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                    if let onRestart {
                        Button(action: onRestart) {
                            Label("Restart Session", systemImage: "arrow.clockwise")
                                .font(.callout)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                Spacer()
            } else if tabs.isEmpty {
                Spacer()
                ProgressView("Connecting to session\u{2026}")
                    .font(.caption)
                Spacer()
            } else if let tab = selectedTab {
                switch tab.content {
                case .terminal(let config):
                    ZStack(alignment: .topTrailing) {
                        TerminalPane(
                            config: config,
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
                case .diff(_, let patch):
                    DiffView(patch: patch)
                case .transcript(let path):
                    TranscriptView(transcriptPath: path)
                }
            }
        }
        .onAppear { restoreOrInitializeTabs() }
        .onDisappear { saveTabState() }
        .onChange(of: session.id) { oldID, _ in
            // Save outgoing session's tab state, then reset for the new session.
            tabStateCache.save(
                .init(tabs: tabs, selectedTabID: selectedTabID, shellCounter: shellCounter),
                for: oldID
            )
            tabs = []
            selectedTabID = nil
            shellCounter = 0
            restoreOrInitializeTabs()
        }
        .onChange(of: splitHorizontalTrigger) { _, _ in splitDown() }
        .onChange(of: splitVerticalTrigger) { _, _ in splitRight() }
        .onChange(of: terminalRestartTrigger) { _, _ in
            // Force reinitialize tabs after restart — the status onChange may not
            // fire if SwiftUI coalesces .running → .starting → .running into no-op.
            tabStateCache.remove(sessionID: session.id)
            tabs = []
            selectedTabID = nil
            shellCounter = 0
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
                restoreOrInitializeTabs()
            }
        }
        .onChange(of: diffOpenTrigger) { _, _ in
            guard let path = pendingDiffPath, let patch = pendingDiffPatch else { return }
            openOrFocusDiffTab(path: path, patch: patch)
        }
        .onChange(of: selectedTabID) { _, _ in
            notifyActiveDiffPath()
            saveTabState()
        }
        .onChange(of: tabs.count) { _, _ in saveTabState() }
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

            // Transcript tab button (if session has a transcript)
            if let path = session.transcriptPath {
                Button {
                    openTranscriptTab(path: path)
                } label: {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("View session transcript")
                .accessibilityLabel("View transcript")
            }

            Spacer()

            // Split pane buttons (terminal tabs only)
            if let tab = selectedTab, case .terminal = tab.content {
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
            } else if case .diff = tab.content {
                Image(systemName: "doc.text")
                    .font(.caption2)
            }
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)

            if !tab.isMain {
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

    /// Restore tab state from cache if available, otherwise initialize from scratch.
    private func restoreOrInitializeTabs() {
        if let cached = tabStateCache.state(for: session.id) {
            tabs = cached.tabs
            selectedTabID = cached.selectedTabID
            shellCounter = cached.shellCounter
            return
        }
        initializeTabsIfReady()
    }

    /// Persist current tab state so it survives navigation away and back.
    private func saveTabState() {
        guard !tabs.isEmpty else { return }
        tabStateCache.save(
            .init(tabs: tabs, selectedTabID: selectedTabID, shellCounter: shellCounter),
            for: session.id
        )
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
        guard let tab = selectedTab, let config = tab.config, let tmuxName = config.tmuxSessionName
        else { return }
        Task {
            try? await tmuxManager.splitWindow(
                sessionName: tmuxName, direction: .horizontal, workDir: session.path
            )
        }
    }

    /// Split the current pane left/right (creates a vertical divider).
    private func splitRight() {
        guard let tab = selectedTab, let config = tab.config, let tmuxName = config.tmuxSessionName
        else { return }
        Task {
            try? await tmuxManager.splitWindow(
                sessionName: tmuxName, direction: .vertical, workDir: session.path
            )
        }
    }

    private func closeTab(_ id: String) {
        // Kill tmux session for terminal tabs
        if let tab = tabs.first(where: { $0.id == id }),
            let tmuxName = tab.config?.tmuxSessionName
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

    // MARK: - Diff Tab Management

    private func openOrFocusDiffTab(path: String, patch: String) {
        let tabID = "diff-\(path)"
        let title = Self.filename(from: path)

        if let index = tabs.firstIndex(where: { $0.id == tabID }) {
            // Update existing tab's patch (file may have changed) and select it
            tabs[index] = TerminalTab(id: tabID, title: title, filePath: path, patch: patch)
            selectedTabID = tabID
        } else {
            let tab = TerminalTab(id: tabID, title: title, filePath: path, patch: patch)
            tabs.append(tab)
            selectedTabID = tabID
        }
    }

    private func openTranscriptTab(path: String) {
        let tabID = "transcript"
        if tabs.contains(where: { $0.id == tabID }) {
            selectedTabID = tabID
        } else {
            let tab = TerminalTab(id: tabID, title: "Transcript", transcriptPath: path)
            tabs.append(tab)
            selectedTabID = tabID
        }
    }

    private func notifyActiveDiffPath() {
        if let tab = selectedTab, case .diff(let path, _) = tab.content {
            onActiveDiffPathChanged?(path)
        } else {
            onActiveDiffPathChanged?(nil)
        }
    }

    private static func filename(from path: String) -> String {
        if let lastSlash = path.lastIndex(of: "/") {
            return String(path[path.index(after: lastSlash)...])
        }
        return path
    }

    /// Count occurrences of a search term in the terminal buffer text.
    /// Iterates row-by-row instead of loading the entire scrollback buffer into memory,
    /// avoiding ~6MB allocation spikes per keystroke on large terminals.
    private func countMatches(_ term: String, in terminalView: LocalProcessTerminalView) -> Int {
        let terminal = terminalView.getTerminal()
        let searchTerm = term.lowercased()
        guard !searchTerm.isEmpty else { return 0 }

        var count = 0
        let totalRows = terminal.rows
        for row in 0..<totalRows {
            guard let line = terminal.getLine(row: row) else { continue }
            let text = line.translateToString(trimRight: true).lowercased()
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: searchTerm, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return count
    }
}
