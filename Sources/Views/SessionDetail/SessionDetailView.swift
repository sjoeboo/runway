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
    @Binding var splitHorizontalTrigger: Int
    @Binding var splitVerticalTrigger: Int

    public init(
        session: Session, linkedPR: PullRequest? = nil, onSelectPR: ((PullRequest) -> Void)? = nil, showSendBar: Binding<Bool>,
        showTerminalSearch: Binding<Bool>,
        splitHorizontalTrigger: Binding<Int> = .constant(0),
        splitVerticalTrigger: Binding<Int> = .constant(0)
    ) {
        self.session = session
        self.linkedPR = linkedPR
        self.onSelectPR = onSelectPR
        self._showSendBar = showSendBar
        self._showTerminalSearch = showTerminalSearch
        self._splitHorizontalTrigger = splitHorizontalTrigger
        self._splitVerticalTrigger = splitVerticalTrigger
    }

    public var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(session: session, linkedPR: linkedPR, onSelectPR: onSelectPR)
            TerminalTabView(
                session: session,
                showSearch: $showTerminalSearch,
                splitHorizontalTrigger: $splitHorizontalTrigger,
                splitVerticalTrigger: $splitVerticalTrigger
            )
            SendTextBar(isVisible: $showSendBar) { text in
                if let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) {
                    terminal.send(txt: text + "\r")
                }
            }
        }
    }
}
