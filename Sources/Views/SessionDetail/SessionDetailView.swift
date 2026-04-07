import Models
import SwiftUI
import TerminalView
import Theme

public struct SessionDetailView: View {
    let session: Session
    var linkedPR: PullRequest?
    var onSelectPR: ((PullRequest) -> Void)?
    @Binding var showSendBar: Bool
    @Binding var showTerminalSearch: Bool
    @Binding var changesVisible: Bool
    @Binding var changesMode: ChangesMode
    let changes: [FileChange]
    var viewingDiffFile: FileChange?
    var diffPatch: String?
    var onSelectDiffFile: ((FileChange) -> Void)?
    var onDismissDiff: (() -> Void)?
    var onToggleChanges: (() -> Void)?
    @AppStorage("changesSidebarWidth") private var sidebarWidth: Double = 260
    @Environment(\.theme) private var theme

    public init(
        session: Session,
        linkedPR: PullRequest? = nil,
        onSelectPR: ((PullRequest) -> Void)? = nil,
        showSendBar: Binding<Bool>,
        showTerminalSearch: Binding<Bool>,
        changesVisible: Binding<Bool>,
        changesMode: Binding<ChangesMode>,
        changes: [FileChange] = [],
        viewingDiffFile: FileChange? = nil,
        diffPatch: String? = nil,
        onSelectDiffFile: ((FileChange) -> Void)? = nil,
        onDismissDiff: (() -> Void)? = nil,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.onSelectPR = onSelectPR
        self._showSendBar = showSendBar
        self._showTerminalSearch = showTerminalSearch
        self._changesVisible = changesVisible
        self._changesMode = changesMode
        self.changes = changes
        self.viewingDiffFile = viewingDiffFile
        self.diffPatch = diffPatch
        self.onSelectDiffFile = onSelectDiffFile
        self.onDismissDiff = onDismissDiff
        self.onToggleChanges = onToggleChanges
    }

    public var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(
                session: session,
                linkedPR: linkedPR,
                onSelectPR: onSelectPR,
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
                        mode: $changesMode,
                        selectedPath: viewingDiffFile?.path,
                        onSelectFile: { file in onSelectDiffFile?(file) }
                    )
                    .frame(width: CGFloat(sidebarWidth))
                }
            }
            SendTextBar(isVisible: $showSendBar) { text in
                if let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) {
                    terminal.send(txt: text + "\r")
                }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if let diffPatch, viewingDiffFile != nil {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { onDismissDiff?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back to terminal")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.chrome.surface.opacity(0.3))

                DiffView(patch: diffPatch)
            }
        } else {
            TerminalTabView(session: session, showSearch: $showTerminalSearch)
        }
    }
}
