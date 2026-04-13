import Models
import SwiftUI
import Terminal
import TerminalView
import Theme

public struct SessionDetailView: View {
    let session: Session
    let tmuxManager: TmuxSessionManager
    var linkedPR: PullRequest?
    var prDetail: PRDetail? = nil
    var onSelectPR: ((PullRequest) -> Void)?
    var parentSession: Session? = nil
    var onSelectSession: ((String) -> Void)? = nil
    @Binding var showSendBar: Bool
    @Binding var showTerminalSearch: Bool
    @Binding var splitHorizontalTrigger: Int
    @Binding var splitVerticalTrigger: Int
    @Binding var terminalRestartTrigger: Int
    @Binding var changesVisible: Bool
    @Binding var changesMode: ChangesMode
    let changes: [FileChange]
    let fileTree: [FileTreeNode]
    var activeDiffPath: String?
    var onSelectDiffFile: ((FileChange) -> Void)?
    var pendingDiffPath: String?
    var pendingDiffPatch: String?
    var diffOpenTrigger: Int = 0
    var onActiveDiffPathChanged: ((String?) -> Void)?
    var onToggleChanges: (() -> Void)?
    var onRestart: (() -> Void)?
    var savedPrompts: [SavedPrompt] = []
    @AppStorage("changesSidebarWidth") private var sidebarWidth: Double = 260
    @Environment(\.theme) private var theme

    public init(
        session: Session,
        tmuxManager: TmuxSessionManager,
        linkedPR: PullRequest? = nil,
        prDetail: PRDetail? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        parentSession: Session? = nil,
        onSelectSession: ((String) -> Void)? = nil,
        showSendBar: Binding<Bool>,
        showTerminalSearch: Binding<Bool>,
        splitHorizontalTrigger: Binding<Int> = .constant(0),
        splitVerticalTrigger: Binding<Int> = .constant(0),
        terminalRestartTrigger: Binding<Int> = .constant(0),
        changesVisible: Binding<Bool>,
        changesMode: Binding<ChangesMode>,
        changes: [FileChange] = [],
        fileTree: [FileTreeNode] = [],
        activeDiffPath: String? = nil,
        onSelectDiffFile: ((FileChange) -> Void)? = nil,
        pendingDiffPath: String? = nil,
        pendingDiffPatch: String? = nil,
        diffOpenTrigger: Int = 0,
        onActiveDiffPathChanged: ((String?) -> Void)? = nil,
        onToggleChanges: (() -> Void)? = nil,
        onRestart: (() -> Void)? = nil,
        savedPrompts: [SavedPrompt] = []
    ) {
        self.session = session
        self.tmuxManager = tmuxManager
        self.linkedPR = linkedPR
        self.prDetail = prDetail
        self.onSelectPR = onSelectPR
        self.parentSession = parentSession
        self.onSelectSession = onSelectSession
        self._showSendBar = showSendBar
        self._showTerminalSearch = showTerminalSearch
        self._splitHorizontalTrigger = splitHorizontalTrigger
        self._splitVerticalTrigger = splitVerticalTrigger
        self._terminalRestartTrigger = terminalRestartTrigger
        self._changesVisible = changesVisible
        self._changesMode = changesMode
        self.changes = changes
        self.fileTree = fileTree
        self.activeDiffPath = activeDiffPath
        self.onSelectDiffFile = onSelectDiffFile
        self.pendingDiffPath = pendingDiffPath
        self.pendingDiffPatch = pendingDiffPatch
        self.diffOpenTrigger = diffOpenTrigger
        self.onActiveDiffPathChanged = onActiveDiffPathChanged
        self.onToggleChanges = onToggleChanges
        self.onRestart = onRestart
        self.savedPrompts = savedPrompts
    }

    public var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(
                session: session,
                linkedPR: linkedPR,
                prDetail: prDetail,
                parentSession: parentSession,
                onSelectPR: onSelectPR,
                onSelectSession: onSelectSession,
                changesVisible: changesVisible,
                onToggleChanges: onToggleChanges
            )
            HStack(spacing: 0) {
                // Main content: terminal or diff view
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if changesVisible {
                    ResizableDivider(width: $sidebarWidth, minWidth: 200, maxWidth: 400, inverted: true)
                    ChangesSidebarView(
                        changes: changes,
                        nodes: fileTree,
                        mode: $changesMode,
                        selectedPath: activeDiffPath,
                        onSelectFile: { file in onSelectDiffFile?(file) }
                    )
                    .frame(width: CGFloat(sidebarWidth))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: changesVisible)
            SendTextBar(isVisible: $showSendBar, toolName: session.tool.displayName, savedPrompts: savedPrompts) { text in
                if let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) {
                    terminal.send(txt: text + "\r")
                }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        TerminalTabView(
            session: session,
            tmuxManager: tmuxManager,
            showSearch: $showTerminalSearch,
            splitHorizontalTrigger: $splitHorizontalTrigger,
            splitVerticalTrigger: $splitVerticalTrigger,
            terminalRestartTrigger: $terminalRestartTrigger,
            pendingDiffPath: pendingDiffPath,
            pendingDiffPatch: pendingDiffPatch,
            diffOpenTrigger: diffOpenTrigger,
            onActiveDiffPathChanged: onActiveDiffPathChanged,
            onRestart: onRestart
        )
        .id("terminal-\(session.id)-\(terminalRestartTrigger)")
    }
}
