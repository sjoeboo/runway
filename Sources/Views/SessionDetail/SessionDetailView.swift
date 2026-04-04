import Models
import SwiftUI
import TerminalView
import Theme

public struct SessionDetailView: View {
    let session: Session
    var linkedPR: PullRequest?

    public init(session: Session, linkedPR: PullRequest? = nil) {
        self.session = session
        self.linkedPR = linkedPR
    }

    public var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(session: session, linkedPR: linkedPR)
            TerminalTabView(session: session)
        }
    }
}
