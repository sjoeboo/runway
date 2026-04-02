import Models
import SwiftUI
import Theme

/// Sidebar view showing the hierarchical project tree with sessions.
public struct ProjectTreeView: View {
    let projects: [Project]
    let sessions: [Session]
    @Binding var selectedSessionID: String?
    @Environment(\.theme) private var theme

    public init(
        projects: [Project],
        sessions: [Session],
        selectedSessionID: Binding<String?>
    ) {
        self.projects = projects
        self.sessions = sessions
        self._selectedSessionID = selectedSessionID
    }

    public var body: some View {
        List(selection: $selectedSessionID) {
            ForEach(projects) { project in
                Section(project.name) {
                    let projectSessions = sessions.filter { $0.groupID == project.id }
                    ForEach(projectSessions) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                    }
                }
            }

            // Ungrouped sessions
            let ungrouped = sessions.filter { $0.groupID == nil }
            if !ungrouped.isEmpty {
                Section("Sessions") {
                    ForEach(ungrouped) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// A single session row in the sidebar.
struct SessionRowView: View {
    let session: Session
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(.body, design: .default))
                    .foregroundColor(theme.chrome.text)
                if let branch = session.worktreeBranch {
                    Text(branch)
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
            }
            Spacer()
            if session.tool != .claude {
                Text(session.tool.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.chrome.surface)
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.status {
        case .running:
            Circle().fill(theme.chrome.green).frame(width: 8, height: 8)
        case .waiting:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 8))
                .foregroundColor(theme.chrome.yellow)
        case .idle:
            Circle().stroke(theme.chrome.textDim, lineWidth: 1).frame(width: 8, height: 8)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 8))
                .foregroundColor(theme.chrome.red)
        case .starting:
            ProgressView().controlSize(.mini)
        case .stopped:
            Circle().stroke(theme.chrome.textDim, lineWidth: 1).frame(width: 8, height: 8)
                .opacity(0.5)
        }
    }
}
