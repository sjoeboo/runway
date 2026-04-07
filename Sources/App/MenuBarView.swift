import Models
import Sparkle
import SwiftUI
import Views

/// Mini status view shown in the macOS menu bar extra.
struct MenuBarView: View {
    @Environment(RunwayStore.self) private var store
    var updater: SPUUpdater?

    private var activeSessions: [Session] {
        store.sessions.filter { $0.status == .running || $0.status == .waiting }
    }

    private var recentSessions: [Session] {
        let activeIDs = Set(activeSessions.map(\.id))
        return store.sessions
            .filter { !activeIDs.contains($0.id) }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active sessions
            if activeSessions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("No active sessions")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                sectionHeader("Active", icon: "bolt.fill")

                ForEach(activeSessions) { session in
                    sessionRow(session)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Recent sessions
            sectionHeader("Recent", icon: "clock")

            ForEach(recentSessions) { session in
                sessionRow(session)
            }

            Divider()
                .padding(.vertical, 4)

            // Actions
            actionButton("New Session…", icon: "plus.circle") {
                store.showNewSessionDialog = true
                NSApplication.shared.activate()
            }

            if let updater {
                actionButton("Check for Updates…", icon: "arrow.triangle.2.circlepath") {
                    updater.checkForUpdates()
                }
            }

            actionButton("Open Runway", icon: "macwindow") {
                NSApplication.shared.activate()
            }

            Divider()
                .padding(.vertical, 4)

            actionButton("Quit Runway", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 240)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func sessionRow(_ session: Session) -> some View {
        Button {
            store.selectedSessionID = session.id
            store.currentView = .sessions
            NSApplication.shared.activate()
        } label: {
            HStack(spacing: 6) {
                SessionStatusIndicator(status: session.status, size: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .lineLimit(1)
                        .font(.callout)

                    if let projectName = projectName(for: session) {
                        Text(projectName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                statusLabel(session.status)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .font(.callout)
                Text(title)
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusLabel(_ status: SessionStatus) -> some View {
        switch status {
        case .running:
            capsuleBadge("Running", fg: .white, bg: .green)
        case .waiting:
            capsuleBadge("Waiting", fg: .white, bg: .orange)
        case .starting:
            capsuleBadge("Starting", fg: .white, bg: .blue)
        case .error:
            capsuleBadge("Error", fg: .white, bg: .red)
        case .idle:
            capsuleBadge("Idle", fg: .secondary, bg: Color.secondary.opacity(0.15))
        case .stopped:
            capsuleBadge("Stopped", fg: .secondary, bg: Color.secondary.opacity(0.15))
        }
    }

    private func capsuleBadge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func projectName(for session: Session) -> String? {
        guard let projectID = session.projectID else { return nil }
        return store.projects.first { $0.id == projectID }?.name
    }
}
