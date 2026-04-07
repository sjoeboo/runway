import Models
import Sparkle
import SwiftUI

/// Mini status view shown in the macOS menu bar extra.
struct MenuBarView: View {
    @Environment(RunwayStore.self) private var store
    var updater: SPUUpdater?

    private var activeSessions: [Session] {
        store.sessions.filter { $0.status == .running || $0.status == .waiting }
    }

    private var recentSessions: [Session] {
        store.sessions
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeSessions.isEmpty {
                Text("No active sessions")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(activeSessions) { session in
                    sessionButton(session)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Text("Recent")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(recentSessions) { session in
                sessionButton(session)
            }

            Divider()
                .padding(.vertical, 4)

            Button("New Session…") {
                store.showNewSessionDialog = true
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            if let updater {
                CheckForUpdatesView(updater: updater)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Button("Open Runway") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 220)
    }

    private func sessionButton(_ session: Session) -> some View {
        Button {
            store.selectedSessionID = session.id
            store.currentView = .sessions
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 6) {
                statusDot(session.status)
                Text(session.title)
                    .lineLimit(1)
                Spacer()
                Text(session.status.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusDot(_ status: SessionStatus) -> some View {
        switch status {
        case .running:
            Circle().fill(.green).frame(width: 6, height: 6)
        case .waiting:
            Circle().fill(.yellow).frame(width: 6, height: 6)
        case .error:
            Circle().fill(.red).frame(width: 6, height: 6)
        case .idle:
            Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 6, height: 6)
        case .starting:
            Circle().fill(.blue).frame(width: 6, height: 6)
        case .stopped:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
        }
    }
}
