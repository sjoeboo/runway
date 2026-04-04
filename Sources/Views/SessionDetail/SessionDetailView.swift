import Models
import SwiftUI
import TerminalView
import Theme

public struct SessionDetailView: View {
    let session: Session
    var linkedPR: PullRequest?
    @Binding var showSendBar: Bool
    @Binding var showTerminalSearch: Bool

    public init(session: Session, linkedPR: PullRequest? = nil, showSendBar: Binding<Bool>, showTerminalSearch: Binding<Bool>) {
        self.session = session
        self.linkedPR = linkedPR
        self._showSendBar = showSendBar
        self._showTerminalSearch = showTerminalSearch
    }

    public var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(session: session, linkedPR: linkedPR)
            TerminalTabView(session: session, showSearch: $showTerminalSearch)
            SendTextBar(isVisible: $showSendBar) { text in
                if let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) {
                    terminal.send(txt: text + "\r")
                }
            }
        }
    }
}
