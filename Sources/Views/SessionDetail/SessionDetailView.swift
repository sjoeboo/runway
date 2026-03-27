import SwiftUI
import Models
import Theme

/// Main content area showing the selected session's terminal and status.
public struct SessionDetailView: View {
    let session: Session
    @Environment(\.theme) private var theme

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Terminal tabs area
            TerminalTabView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Status bar
            statusBar
        }
        .background(theme.chrome.background)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 4) {
                statusDot
                Text(session.status.rawValue.capitalized)
                    .font(.caption)
            }

            Divider().frame(height: 12)

            // Branch info
            if let branch = session.worktreeBranch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                    Text(branch)
                        .font(.caption)
                }
                .foregroundColor(theme.chrome.textDim)
            }

            Spacer()

            // Tool badge
            Text(session.tool.displayName)
                .font(.caption2)
                .foregroundColor(theme.chrome.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.chrome.surface)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.status {
        case .running:
            Circle().fill(theme.chrome.green).frame(width: 6, height: 6)
        case .waiting:
            Circle().fill(theme.chrome.yellow).frame(width: 6, height: 6)
        case .idle:
            Circle().fill(theme.chrome.textDim).frame(width: 6, height: 6)
        case .error:
            Circle().fill(theme.chrome.red).frame(width: 6, height: 6)
        case .starting, .stopped:
            Circle().fill(theme.chrome.textDim).frame(width: 6, height: 6).opacity(0.5)
        }
    }
}
